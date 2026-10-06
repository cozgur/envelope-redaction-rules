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
                FieldLineNameRule(),
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
        redact(text, countryHint: countryHint, known: [])
    }

    /// The same, with claims made outside the rules: the address window the
    /// app found on the page (L2) and the reader's own details (L1).
    ///
    /// Merge order (redaction v2 plan §1, owner, 6 Oct 2026): **window claims
    /// first**, so the whole window is one `[ADDRESS_n]` with the recipient's
    /// name inside it; then profile claims, which win everywhere outside the
    /// window; then the rules. An earlier claim wins an overlap. The
    /// letterhead guard applies to profile claims and rules, never to a
    /// window claim: the window's position is the evidence.
    public static func redact(
        _ text: String,
        countryHint: String? = nil,
        known: [KnownClaim]
    ) -> RedactionResult {
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

        for claim in known where claim.source == .window && !claim.ranges.isEmpty {
            guard !claims.contains(where: { $0.overlaps(claim.ranges) }) else { continue }
            claims.append(Claim(kind: claim.kind, ranges: claim.ranges, rank: Claim.windowRank))
        }
        for claim in known where claim.source == .profile {
            let guarded = !claim.strongContext
            for range in claim.ranges {
                guard !guarded || !protected.contains(where: { $0.vetoes(claim.kind) && $0.range.overlaps(range) }),
                      !claims.contains(where: { $0.overlaps(range) })
                else { continue }
                claims.append(Claim(kind: claim.kind, ranges: [range], rank: Claim.profileRank))
            }
        }

        for (index, rule) in rules(countryHint: countryHint).enumerated() {
            for range in rule.matches(in: text) {
                guard !protected.contains(where: {
                    $0.vetoes(rule.kind) && $0.range.overlaps(range)
                }) else { continue }
                let overlapping = claims.indices.filter { claims[$0].overlaps(range) }
                if !overlapping.isEmpty {
                    // A rule's address block that wholly contains profile
                    // matches is the better answer where the app found no
                    // window: the block masks the flat number and the city
                    // line too, which the profile does not know. It takes
                    // their place. Anything else that overlaps wins.
                    let absorbs = rule.kind == .address && overlapping.allSatisfy { index in
                        let claim = claims[index]
                        return claim.rank == Claim.profileRank
                            && claim.ranges.allSatisfy { range.contains($0.lowerBound) && $0.upperBound <= range.upperBound }
                    }
                    guard absorbs else { continue }
                    for index in overlapping.sorted(by: >) { claims.remove(at: index) }
                }
                claims.append(Claim(kind: rule.kind, ranges: [range], rank: Claim.firstRuleRank + index))
            }
        }

        claims = wholeTokens(claims, in: text)

        // A value identified anywhere in the letter is that value everywhere
        // in it. Official mail repeats a reference three or four times -- in
        // the field block, mid-sentence, and again in the payment
        // instruction -- and only the first mention sits beside a label. Once
        // a rule has recognised the value, the rest are the same secret and
        // are masked on sight rather than re-detected.
        //
        // The recipient's name is one of those values even though no rule
        // claims it alone: it is inside the address block, which is claimed
        // whole. It is read back out of the block's first line so that "the
        // application of K.L. Brandsma" further down is masked too.
        let seeds = claims
            .filter { $0.kind == .address }
            .compactMap { PersonName.onFirstLine(of: $0.value(in: text)) }
        claims = withRepeatedOccurrences(of: claims, seeds: seeds, in: text, avoiding: protected)
        claims += surnamesAfterHonorifics(
            of: seeds, in: text, taken: claims.flatMap(\.ranges), avoiding: protected
        )
        claims = oneLabelPerValue(claims, in: text)

        // Every range in text order, each knowing its claim, so placeholders
        // are numbered in the order a reader meets them.
        let pieces = claims.indices
            .flatMap { index in claims[index].ranges.map { (range: $0, claim: index) } }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }

        var placeholderForValue: [PlaceholderKey: String] = [:]
        var placeholderForClaim: [Int: String] = [:]
        var map: [String: String] = [:]
        var nextIndex: [PIIKind: Int] = [:]
        var replacements: [(range: Range<String.Index>, placeholder: String)] = []
        var spans: [RedactionResult.MaskedSpan] = []

        // Walked forward alongside the ranges, which are sorted and do not
        // overlap, so each span's offsets fall out of the one before it
        // rather than out of a distance measured from the start of the text.
        var cursor = text.startIndex
        var originalOffset = 0
        var drift = 0

        for piece in pieces {
            let claim = claims[piece.claim]
            let placeholder: String
            if let existing = placeholderForClaim[piece.claim] {
                placeholder = existing
            } else {
                let value = claim.value(in: text)
                let key = PlaceholderKey(kind: claim.kind, value: value)
                if let existing = placeholderForValue[key] {
                    placeholder = existing
                } else {
                    let index = (nextIndex[claim.kind] ?? 0) + 1
                    nextIndex[claim.kind] = index
                    placeholder = claim.kind.placeholder(index: index)
                    placeholderForValue[key] = placeholder
                    map[placeholder] = value
                }
                placeholderForClaim[piece.claim] = placeholder
            }
            replacements.append((piece.range, placeholder))

            let length = text[piece.range].count
            let start = originalOffset + text.distance(from: cursor, to: piece.range.lowerBound)
            spans.append(
                RedactionResult.MaskedSpan(
                    placeholder: placeholder,
                    kind: claim.kind,
                    originalRange: start..<(start + length),
                    redactedRange: (start + drift)..<(start + drift + placeholder.count)
                )
            )
            drift += placeholder.count - length
            cursor = piece.range.upperBound
            originalOffset = start + length
        }

        // Back to front, so earlier ranges stay valid as the string changes.
        var redacted = text
        for replacement in replacements.reversed() {
            redacted.replaceSubrange(replacement.range, with: replacement.placeholder)
        }

        return RedactionResult(
            redactedText: redacted,
            map: map,
            counts: nextIndex,
            spans: spans
        )
    }

    /// The full engine: the address window from the page's layout (L2), the
    /// reader's own details (L1), then the rules (L3).
    ///
    /// The profile's matches join `known` as profile claims; a window claim
    /// in `known` also gives the matcher its strong context (a surname
    /// inside the window may be two edits off). With no profile this is
    /// `redact(_:countryHint:known:)`.
    public static func redact(
        _ text: String,
        countryHint: String? = nil,
        layout: LetterLayout? = nil,
        known: [KnownClaim] = [],
        profile: RedactionProfile?
    ) -> RedactionResult {
        // L2: the address window, when the page's geometry shows one.
        var known = known
        if let layout, !known.contains(where: { $0.source == .window }),
           let window = AddressWindow.find(in: text, layout: layout, countryHint: countryHint) {
            known.insert(window, at: 0)
        }
        guard let profile else { return redact(text, countryHint: countryHint, known: known) }
        let window = known.filter { $0.source == .window }.flatMap(\.ranges)
        let matched = ProfileMatcher.claims(in: text, profile: profile, window: window, countryHint: countryHint)
        return redact(text, countryHint: countryHint, known: known + matched)
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

    /// The whole token, for a number the phone or reference rule caught part
    /// of.
    ///
    /// `STU-2026-11842` is one token; a phone pattern finds `2026-11842` in
    /// it and the `STU-` stays in the clear (redaction v2 plan §1 L3). A
    /// claim is widened to the token it sits in -- letters and digits joined
    /// by `-` or `/`, never across whitespace or other punctuation -- and a
    /// phone claim whose token carries a letter is a reference: a letter
    /// prefix or suffix is what a reference looks like and what a phone
    /// number never has. Widened only where nothing else is claimed in the
    /// token.
    private static func wholeTokens(_ claims: [Claim], in text: String) -> [Claim] {
        var result = claims
        for index in result.indices {
            let claim = result[index]
            guard claim.ranges.count == 1, claim.rank >= Claim.firstRuleRank,
                  claim.kind == .phone || claim.kind == .reference,
                  let range = claim.ranges.first
            else { continue }
            let token = tokenRange(around: range, in: text)
            guard token != range,
                  !result.indices.contains(where: { $0 != index && result[$0].overlaps(token) })
            else { continue }
            let hasLetter = text[token].contains { $0.isLetter }
            result[index] = Claim(
                kind: claim.kind == .phone && hasLetter ? .reference : claim.kind,
                ranges: [token],
                rank: claim.rank
            )
        }
        return result
    }

    /// The run of letters and digits, joined by single `-` or `/`, that
    /// `range` sits in.
    private static func tokenRange(around range: Range<String.Index>, in text: String) -> Range<String.Index> {
        let isPart: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        let isJoiner: (Character) -> Bool = { $0 == "-" || $0 == "/" }
        var lower = range.lowerBound
        while lower > text.startIndex {
            let previous = text.index(before: lower)
            if isPart(text[previous]) {
                lower = previous
            } else if isJoiner(text[previous]), previous > text.startIndex,
                      isPart(text[text.index(before: previous)]) {
                lower = text.index(before: previous)
            } else {
                break
            }
        }
        var upper = range.upperBound
        while upper < text.endIndex {
            if isPart(text[upper]) {
                upper = text.index(after: upper)
            } else if isJoiner(text[upper]) {
                let next = text.index(after: upper)
                guard next < text.endIndex, isPart(text[next]) else { break }
                upper = text.index(after: next)
            } else {
                break
            }
        }
        return lower..<upper
    }

    /// The claims, with every further occurrence of a claimed value added.
    ///
    /// An occurrence that already holds a smaller claim -- the phone rule's
    /// `2026-11842` inside the body's `STU-2026-11842` -- is not skipped: the
    /// whole value replaces what is inside it. An occurrence that another
    /// claim crosses, or that sits inside a larger claim, is left alone.
    private static func withRepeatedOccurrences(
        of claims: [Claim],
        seeds: [String] = [],
        in text: String,
        avoiding protected: [ProtectedSpans.Span]
    ) -> [Claim] {
        var result = claims

        var distinct: [PlaceholderKey: Int] = [:]
        // Not a profile match: the matcher has already found every occurrence
        // its precision guards allow, and spreading its value here would mask
        // "der Koch" because "Frau Koch" was the reader.
        for claim in claims where claim.ranges.count == 1 && claim.rank != Claim.profileRank {
            let key = PlaceholderKey(kind: claim.kind, value: claim.value(in: text))
            distinct[key] = min(distinct[key] ?? .max, claim.rank)
        }
        for seed in seeds {
            let key = PlaceholderKey(kind: .name, value: seed)
            distinct[key] = distinct[key] ?? Claim.seedRank
        }

        // Longest first, so a value that contains a shorter one claims its own
        // occurrences before the shorter value can split them. Ties by text,
        // so the order -- and the output -- never depends on hashing.
        let ordered = distinct.sorted {
            $0.key.value.count != $1.key.value.count
                ? $0.key.value.count > $1.key.value.count
                : ($0.key.value, $0.key.kind.rawValue) < ($1.key.value, $1.key.kind.rawValue)
        }
        for (key, rank) in ordered {
            // A value too short, or an ordinary function word, is never spread
            // across the letter. Spreading one replaces every article in the
            // prose, and nothing about the result says which words used to be
            // ordinary.
            guard !Stopwords.blocksRepeat(key.value) else { continue }
            // Nor a name that is one ordinary word or place (Bakker, Koch,
            // Zwolle) or under four letters: masked where a rule found it,
            // never on sight elsewhere (redaction v2 plan §1, precision
            // guards).
            if key.kind == .name, ProfileMatcher.isAmbiguousAlone(key.value) { continue }
            var searchStart = text.startIndex
            while let range = text.range(of: key.value, range: searchStart..<text.endIndex) {
                searchStart = range.upperBound
                guard !protected.contains(where: {
                    $0.vetoes(key.kind) && $0.range.overlaps(range)
                }) else { continue }
                let overlapping = result.indices.filter { result[$0].overlaps(range) }
                if overlapping.isEmpty {
                    result.append(Claim(kind: key.kind, ranges: [range], rank: rank))
                    continue
                }
                // Replace only rule claims lying wholly inside this occurrence;
                // anything else keeps its place.
                let replaceable = overlapping.allSatisfy { index in
                    let claim = result[index]
                    guard claim.ranges.count == 1, claim.rank >= Claim.firstRuleRank else { return false }
                    let inner = claim.ranges[0]
                    return inner != range
                        && inner.lowerBound >= range.lowerBound
                        && inner.upperBound <= range.upperBound
                }
                guard replaceable else { continue }
                for index in overlapping.sorted(by: >) { result.remove(at: index) }
                result.append(Claim(kind: key.kind, ranges: [range], rank: rank))
            }
        }
        return result
    }

    /// One value, one kind: the kind its most certain claim gave it.
    ///
    /// The same digits claimed as a reference on the field line and as a
    /// phone number in a sentence are one secret with two labels -- and the
    /// reply header resolves labels by kind. Rank is rule order, which runs
    /// from most certain to least, so a keyword-anchored reference outranks a
    /// pattern-matched phone number.
    private static func oneLabelPerValue(_ claims: [Claim], in text: String) -> [Claim] {
        var best: [String: (kind: PIIKind, rank: Int)] = [:]
        for claim in claims where claim.ranges.count == 1 {
            let value = claim.value(in: text)
            if let current = best[value], current.rank <= claim.rank { continue }
            best[value] = (claim.kind, claim.rank)
        }
        return claims.map { claim in
            guard claim.ranges.count == 1, let chosen = best[claim.value(in: text)] else { return claim }
            return Claim(kind: chosen.kind, ranges: claim.ranges, rank: claim.rank)
        }
    }

    /// The recipient's surname where the letter uses it alone, after an
    /// honorific: "wij nemen contact op met mevrouw Brandsma".
    ///
    /// Only after an honorific. A surname on its own is too often an
    /// ordinary word -- Bakker, Visser, De Groot -- to be masked on sight;
    /// after *mevrouw* it is only ever a name.
    private static func surnamesAfterHonorifics(
        of names: [String],
        in text: String,
        taken: [Range<String.Index>],
        avoiding protected: [ProtectedSpans.Span]
    ) -> [Claim] {
        var found: [Claim] = []
        var taken = taken
        for name in names {
            guard let surname = PersonName.surname(of: name), surname.count >= 3 else { continue }
            let pattern = #"(?i:(?<!\p{L})(?:heer|mevrouw|meneer|mw\.|dhr\.|mr\.|mrs\.|ms\.)[ \t]+)("#
                + NSRegularExpression.escapedPattern(for: surname) + #")(?!\p{L})"#
            for range in RegexScanner.ranges(of: pattern, captureGroup: 1, in: text)
            where !taken.contains(where: { $0.overlaps(range) })
                && !protected.contains(where: { $0.vetoes(.name) && $0.range.overlaps(range) }) {
                found.append(Claim(kind: .name, ranges: [range], rank: Claim.seedRank))
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
        return withRepeatedOccurrences(
            of: [Claim(kind: kind, ranges: [first], rank: Claim.firstRuleRank)],
            in: text,
            avoiding: protected
        ).count - 1
    }

    /// One claim: a kind and the ranges it covers, all under one placeholder.
    ///
    /// Several ranges only for a window claim, whose lines OCR may serialise
    /// apart. Rank is where the claim came from and decides the kind when one
    /// value is claimed twice: the window, then the profile, then the rules in
    /// their order, then the values spread from the recipient's name.
    private struct Claim {
        static let windowRank = 0
        static let profileRank = 1
        static let firstRuleRank = 2
        static let seedRank = Int.max - 1

        var kind: PIIKind
        var ranges: [Range<String.Index>]
        var rank: Int

        func overlaps(_ others: [Range<String.Index>]) -> Bool {
            ranges.contains { mine in others.contains { $0.overlaps(mine) } }
        }

        func overlaps(_ other: Range<String.Index>) -> Bool { overlaps([other]) }

        /// The text the map keeps: the ranges' text joined by newlines, in
        /// the order the claim lists them (reading order, for a window).
        func value(in text: String) -> String {
            ranges.map { String(text[$0]) }.joined(separator: "\n")
        }
    }

    /// Identity of a masked value. Keyed by kind as well as text so the same
    /// digits appearing as two different kinds stay distinguishable.
    private struct PlaceholderKey: Hashable {
        var kind: PIIKind
        var value: String
    }
}
