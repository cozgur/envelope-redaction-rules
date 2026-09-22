import Foundation

/// Removes personal data from a letter and can put it back.
///
/// The engine is deterministic and model-free, which is the point: it is the
/// one component standing between the user's identity numbers and the network
/// (H1), so it has to be auditable line by line and testable against fixtures
/// rather than sampled for quality.
///
/// It is not, and does not try to be, complete. Names are not removed in v1 --
/// that needs a model, which is what running on device is meant to avoid --
/// and the limitation is documented rather than glossed over.
public enum RedactionEngine {

    /// Rules in the order their claims are honoured.
    ///
    /// Order is the conflict resolution, and it runs from most certain to
    /// least. Formats carrying their own checksum come first, then the
    /// keyword-anchored fallbacks -- a letter that prints a number directly
    /// after the word "Burgerservicenummer" has told us what it is -- and
    /// only then the pattern detectors.
    ///
    /// Phone deliberately runs last of the value rules. `NSDataDetector`
    /// happily reads a bare nine-digit identity number as a phone number, and
    /// while both end up masked, a placeholder naming the wrong kind is a lie
    /// the reply header would act on. Going the other way is safe: a real
    /// phone number is not a contiguous run of exactly nine digits in any of
    /// the launch countries, so the identity rules do not reach it.
    private static func rules(countryHint: String?) -> [any RedactionRule] {
        var identityRules = NationalIDFormat.all
        if let hint = countryHint?.uppercased(),
           let preferred = NationalIDFormat.format(for: hint),
           let position = identityRules.firstIndex(where: { $0.country == preferred.country }) {
            // The hint orders; it never filters. A letter can quote a number
            // from a country the user does not live in.
            identityRules.remove(at: position)
            identityRules.insert(preferred, at: 0)
        }

        return [EmailRule(), IBANRule()]
            + identityRules.map { NationalIDRule(format: $0) }
            + [
                // After the identity formats, not before. Luhn is the whole of
                // a card number's validation and one random digit string in
                // ten passes it, so a fifteen-digit French NIR is a card
                // number one time in ten -- masked either way, but labelled
                // with a kind the reply header would then resolve wrongly. An
                // identity format is far more specific: a leading 1 or 2, a
                // real month, a department, a two-digit key. Nothing goes the
                // other way, because no identity pattern can match a card:
                // a sixteen-digit run offers no word boundary at nine or
                // eleven digits, and a fifteen-digit Amex starts with a 3.
                CardNumberRule(),
                DigitRunFallbackRule(),
                AccountNumberFallbackRule(),
                ReferenceNumberRule(),
                // The recipient block runs before the salutation, and before
                // the general address detector. Before the salutation because
                // the block contains the same name: if the name were claimed
                // first, the block claim would overlap it and be dropped,
                // leaving the street and postcode in the clear. Before the
                // general detector because the block is the larger, better
                // answer wherever both apply.
                RecipientBlockRule(),
                SalutationNameRule(),
                DataDetectorRule.phone,
                PhoneNumberPatternRule(),
                PhoneKeywordRule(),
                DataDetectorRule.address,
            ]
    }

    /// Replaces every detected value with a typed, indexed placeholder.
    ///
    /// The same original value always receives the same placeholder within one
    /// letter, so a reference quoted three times reads as one reference rather
    /// than three.
    public static func redact(_ text: String, countryHint: String? = nil) -> RedactionResult {
        guard !text.isEmpty else { return RedactionResult(redactedText: text, map: [:]) }

        var protected = ProtectedSpans.compute(in: text)
        if let letterhead = LetterStructure(text).letterheadRange {
            // The sender's own block. It stops address and name claims and
            // nothing else: masking it would delete the one thing an
            // explanation most needs -- who wrote -- while an IBAN printed in
            // a letterhead is still an IBAN.
            //
            // Held here rather than inside the address rule because the
            // repeated-occurrence pass has to respect it as well. A court's
            // street appears in its letterhead *and* in the sentence telling
            // the reader where to turn up; masking the sentence would
            // otherwise drag the letterhead copy with it.
            protected.append(
                ProtectedSpans.Span(
                    range: letterhead,
                    exemptKinds: Set(PIIKind.allCases).subtracting([.address, .name])
                )
            )
        }
        var claims: [Claim] = []

        for rule in rules(countryHint: countryHint) {
            for range in rule.matches(in: text) {
                guard !protected.contains(where: {
                    $0.vetoes(rule.kind) && $0.range.overlaps(range)
                }) else { continue }
                guard !claims.contains(where: { $0.range.overlaps(range) }) else { continue }
                claims.append(Claim(kind: rule.kind, range: range))
            }
        }

        // A value identified anywhere in the letter is that value everywhere
        // in it. Official mail repeats a reference three or four times -- in
        // the field block, mid-sentence, and again in the payment
        // instruction -- and only the first mention sits beside a label. Once
        // a rule has recognised the value, the rest are the same secret and
        // are masked on sight rather than re-detected.
        claims += repeatedOccurrences(of: claims, in: text, avoiding: protected)

        claims.sort { $0.range.lowerBound < $1.range.lowerBound }

        var placeholderForValue: [PlaceholderKey: String] = [:]
        var map: [String: String] = [:]
        var nextIndex: [PIIKind: Int] = [:]
        var replacements: [(range: Range<String.Index>, placeholder: String)] = []

        for claim in claims {
            let original = String(text[claim.range])
            let key = PlaceholderKey(kind: claim.kind, value: original)

            let placeholder: String
            if let existing = placeholderForValue[key] {
                placeholder = existing
            } else {
                let index = (nextIndex[claim.kind] ?? 0) + 1
                nextIndex[claim.kind] = index
                placeholder = claim.kind.placeholder(index: index)
                placeholderForValue[key] = placeholder
                map[placeholder] = original
            }
            replacements.append((claim.range, placeholder))
        }

        // Back to front, so earlier ranges stay valid as the string changes.
        var redacted = text
        for replacement in replacements.reversed() {
            redacted.replaceSubrange(replacement.range, with: replacement.placeholder)
        }

        return RedactionResult(
            redactedText: redacted,
            map: map,
            counts: nextIndex
        )
    }

    /// Puts the original values back.
    ///
    /// Used on device only: to show the user their own reference number, and
    /// to fill a reply header the server only ever saw in placeholder form.
    /// Longer placeholders are substituted first so `[IBAN_1]` cannot be
    /// partially consumed while `[IBAN_10]` is still pending.
    public static func restore(_ text: String, map: [String: String]) -> String {
        var restored = text
        for placeholder in map.keys.sorted(by: { $0.count > $1.count }) {
            guard let original = map[placeholder] else { continue }
            restored = restored.replacingOccurrences(of: placeholder, with: original)
        }
        return restored
    }

    // MARK: - Internals

    /// Every further occurrence of a value some rule already claimed.
    private static func repeatedOccurrences(
        of claims: [Claim],
        in text: String,
        avoiding protected: [ProtectedSpans.Span]
    ) -> [Claim] {
        var found: [Claim] = []
        var taken = claims.map(\.range)

        // Longest first, so a value that contains a shorter one claims its own
        // occurrences before the shorter value can split them.
        let distinct = Set(claims.map { PlaceholderKey(kind: $0.kind, value: String(text[$0.range])) })
        for key in distinct.sorted(by: { $0.value.count > $1.value.count }) {
            // A value too short, or an ordinary function word, is never spread
            // across the letter. Spreading one replaces every article in the
            // prose, and nothing about the result says which words used to be
            // ordinary.
            guard !Stopwords.blocksRepeat(key.value) else { continue }
            var searchStart = text.startIndex
            while let range = text.range(of: key.value, range: searchStart..<text.endIndex) {
                searchStart = range.upperBound
                guard !taken.contains(where: { $0.overlaps(range) }),
                      !protected.contains(where: {
                          $0.vetoes(key.kind) && $0.range.overlaps(range)
                      })
                else { continue }
                found.append(Claim(kind: key.kind, range: range))
                taken.append(range)
            }
        }
        return found
    }

    /// How many *additional* occurrences of `value` the repeat pass would
    /// mask in `text`.
    ///
    /// Exposed for the guard's tests: asserting on the redacted output alone
    /// cannot distinguish "the guard blocked it" from "no rule claimed it in
    /// the first place".
    static func repeatableOccurrenceCount(
        of value: String,
        kind: PIIKind,
        in text: String
    ) -> Int {
        guard let first = text.range(of: value) else { return 0 }
        let protected = ProtectedSpans.compute(in: text)
        return repeatedOccurrences(
            of: [Claim(kind: kind, range: first)],
            in: text,
            avoiding: protected
        ).count
    }

    private struct Claim {
        var kind: PIIKind
        var range: Range<String.Index>
    }

    /// Identity of a masked value. Keyed by kind as well as text so the same
    /// digits appearing as two different kinds stay distinguishable.
    private struct PlaceholderKey: Hashable {
        var kind: PIIKind
        var value: String
    }
}
