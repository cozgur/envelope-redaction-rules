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
@Suite("NL held-out recall (Gate A)")
struct NLHoldoutTests {

    static let file = "nl-holdout-1"

    static let cases: [NLRecallTests.Case] = {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(file)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([NLRecallTests.Case].self, from: data)
        else { return [] }
        return decoded
    }()

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
                if NLRecallTests.leaks(item.value, in: redacted) {
                    entry.missed.append("\(letter.id): \(item.value)")
                } else {
                    entry.masked += 1
                }
                tally[item.category] = entry
            }
        }
        for (category, entry) in tally.sorted(by: { $0.key < $1.key }) {
            print("RECALL \(category) \(entry.masked)/\(entry.total)")
            #expect(entry.masked == entry.total,
                    "\(category) \(entry.masked)/\(entry.total), missed: \(entry.missed)")
        }
    }

    @Test("What must survive survives", arguments: cases)
    func keepsWhatTheExplanationNeeds(_ letter: NLRecallTests.Case) {
        let redacted = RedactionEngine.redact(letter.text, countryHint: "NL").redactedText
        for value in letter.kept {
            #expect(redacted.contains(value), "“\(value)” was masked in \(letter.id):\n\(redacted)")
        }
    }
}
