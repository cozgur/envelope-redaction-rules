import Foundation
import Testing

@testable import RedactionRules

/// Gate A's measurement: recall on a held-out set of Dutch letters.
///
/// The fix fixtures in `NLRecallTests` were written beside the rules they
/// test, so passing them says the rules do what their author meant. This set
/// was written without looking at those fixtures or reusing their layouts --
/// Belastingdienst, IND, CAK, DUO, UWV, a health insurer, a housing
/// association, CJIB and two municipalities, with the address window left
/// and right, columns interleaved by OCR, return-address lines, T.a.v. and
/// c/o, house-number suffixes and initials with tussenvoegsels -- and it was
/// committed before the engine was first run on it. Every value is invented.
///
/// A miss here is not patched here. It becomes a failing fixture in
/// `NLRecallTests`, the rules are fixed against that, and a new held-out set
/// replaces this one: a set the rules have been tuned to is no longer
/// held out.
///
/// From set 6 the held-out set is written by a separate agent that has not
/// seen the rules or any earlier fixture, given only the senders, the kinds
/// of layout to vary and this file's format.
@Suite("NL held-out recall (Gate A)")
struct NLHoldoutTests {

    /// The set Gate A is measured on.
    static let file = "nl-holdout-6"
    /// Earlier held-out sets. Each was retired when the rules were fixed
    /// against its misses; they stay as regression tests and no longer
    /// count for the gate.
    static let retired = ["nl-holdout-1", "nl-holdout-2", "nl-holdout-3", "nl-holdout-4", "nl-holdout-5"]

    static func load(_ name: String) -> [NLRecallTests.Case] {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([NLRecallTests.Case].self, from: data)
        else { return [] }
        return decoded
    }

    static let cases = load(file)

    /// Set 6's five known failures (owner, 6 Oct 2026): recorded as known
    /// issues so CI is green, and strict -- `withKnownIssue` with
    /// `isIntermittent: false` is Swift Testing's `XCTExpectFailure(strict:)`
    /// -- so the run fails the day one of them is fixed, and the entry is
    /// taken out. Set 6 was measured on L3 alone; Gate A is now measured on
    /// the full engine (plan §2), on a new set.
    static let knownSet6Misses: Set<String> = ["address", "name", "postcode", "reference"]
    /// Emptied 6 Oct 2026: the L3 sender-address precision fix (PO boxes,
    /// an organisation's own lines) keeps the string it used to mask.
    static let knownSet6Kept: Set<String> = []

    @Test("Retired held-out sets stay at 100%", arguments: retired)
    func retiredSetsHold(_ name: String) {
        let letters = Self.load(name)
        #expect(letters.count == 20)
        for letter in letters {
            let redacted = RedactionEngine.redact(letter.text, countryHint: "NL").redactedText
            for item in letter.masked {
                #expect(!NLRecallTests.leaks(item.value, in: redacted, original: letter.text), "\(name) \(letter.id): \(item.category) \(item.value)")
            }
            for value in letter.kept {
                #expect(redacted.contains(value), "\(name) \(letter.id): “\(value)” was masked")
            }
        }
    }

    @Test("The held-out set is present: 20 letters, every category")
    func fixturesLoad() {
        #expect(Self.cases.count == 20)
        let categories = Set(Self.cases.flatMap { $0.masked.map(\.category) })
        #expect(categories == ["name", "address", "postcode", "bsn", "iban", "reference"])
    }

    @Test("Recall is 100% in every category")
    func recallByCategory() {
        var tally: [String: (masked: Int, total: Int, missed: [String])] = [:]
        for letter in Self.cases {
            let redacted = RedactionEngine.redact(letter.text, countryHint: "NL").redactedText
            for item in letter.masked {
                var entry = tally[item.category] ?? (0, 0, [])
                entry.total += 1
                if NLRecallTests.leaks(item.value, in: redacted, original: letter.text) {
                    entry.missed.append("\(letter.id): \(item.value)")
                } else {
                    entry.masked += 1
                }
                tally[item.category] = entry
            }
        }
        for (category, entry) in tally.sorted(by: { $0.key < $1.key }) {
            print("RECALL \(category) \(entry.masked)/\(entry.total)")
            let check = {
                #expect(entry.masked == entry.total,
                        "\(category) \(entry.masked)/\(entry.total), missed: \(entry.missed)")
            }
            if Self.knownSet6Misses.contains(category) {
                withKnownIssue("set 6 (nl-holdout-6): \(category) recall below 100% on L3 alone", isIntermittent: false, check)
            } else {
                check()
            }
        }
    }

    @Test("What must survive survives", arguments: cases)
    func keepsWhatTheExplanationNeeds(_ letter: NLRecallTests.Case) {
        let redacted = RedactionEngine.redact(letter.text, countryHint: "NL").redactedText
        let check = {
            for value in letter.kept {
                #expect(redacted.contains(value), "“\(value)” was masked in \(letter.id):\n\(redacted)")
            }
        }
        if Self.knownSet6Kept.contains(letter.id) {
            withKnownIssue("set 6 (nl-holdout-6): a kept string masked in \(letter.id)", isIntermittent: false, check)
        } else {
            check()
        }
    }
}
