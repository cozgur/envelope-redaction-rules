import Foundation
import Testing

@testable import RedactionRules

/// Recall on Dutch letters: name, address, postcode, BSN, IBAN, reference.
///
/// Every value in the fixture set is invented. The gate (Envelope spec §9,
/// Gate A) is 100% on each category: one value left in the clear is the
/// thing the whole engine exists to prevent, and a rate below one is a
/// letter that leaks. The kept values are the other half -- a letterhead,
/// an amount or a date masked away is a letter that cannot be explained.
@Suite("NL recall")
struct NLRecallTests {

    struct Masked: Decodable, Sendable {
        var value: String
        var category: String
        /// From gate-a-7 (owner, 6 Oct 2026): a reference printed after a
        /// reference label, or not. Absent counts as labelled.
        var labelled: Bool?
        /// From gate-a-7: where a third party is printed -- "block" (the
        /// recipient block), "salutation" or "body".
        var `where`: String?
    }

    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        var id: String
        var text: String
        var masked: [Masked]
        var kept: [String]
        /// Values that must become exactly one placeholder, not several.
        var oneToken: [String]
        var testDescription: String { id }
    }

    /// Whether any of a value is still in the text: the whole of it, or any
    /// piece of four characters or more. Checking only the whole value would
    /// pass a reference masked as `[REFERENCE_1] 8834 1107`, which is the
    /// leak this suite was written for.
    ///
    /// Except a piece that is a year. The `2026` of `2026 4471 0098 55` is
    /// also the year in the date line, which is meant to survive. Nothing
    /// else is forgiven for appearing elsewhere: a name repeated in the
    /// salutation is the same name, and it leaks there too.
    static func leaks(_ value: String, in redacted: String, original: String = "") -> Bool {
        if redacted.contains(value) { return true }
        return value
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 4 && !isYear($0) && !isHonorific($0) }
            .contains { containsWord($0, in: redacted) }
    }

    /// As a whole word: "Spaarne" of a masked street is not left in the
    /// sender's name "Woonstichting Spaarnestad".
    private static func containsWord(_ piece: String, in text: String) -> Bool {
        let pattern = #"(?<![\p{L}\d])"# + NSRegularExpression.escapedPattern(for: piece) + #"(?![\p{L}\d])"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// "heer" of a value written as "heer Hoekstra" is the honorific, which
    /// every salutation keeps; only the name after it is the secret.
    private static func isHonorific(_ piece: String) -> Bool {
        ["heer", "mevrouw", "meneer", "fam", "familie", "mevr", "dhr", "drs", "prof"]
            .contains(piece.lowercased().trimmingCharacters(in: .punctuationCharacters))
    }

    private static func isYear(_ piece: String) -> Bool {
        guard piece.count == 4, let year = Int(piece) else { return false }
        return (1900...2099).contains(year)
    }

    static let cases: [Case] = {
        guard let url = Bundle.module.url(forResource: "Fixtures/nl-recall", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Case].self, from: data)
        else { return [] }
        return decoded
    }()

    @Test("The fixtures are present, and cover every category")
    func fixturesLoad() {
        #expect(Self.cases.count >= 21)
        let categories = Set(Self.cases.flatMap { $0.masked.map(\.category) })
        #expect(categories == ["name", "address", "postcode", "bsn", "iban", "reference"])
    }

    @Test("Nothing that should be masked is left in the clear", arguments: cases)
    func masksEverything(_ letter: Case) {
        let redacted = RedactionEngine.redact(letter.text, countryHint: "NL").redactedText
        for item in letter.masked {
            #expect(!Self.leaks(item.value, in: redacted, original: letter.text), "\(item.category) “\(item.value)” left in:\n\(redacted)")
        }
    }

    @Test("What must survive survives", arguments: cases)
    func keepsWhatTheExplanationNeeds(_ letter: Case) {
        let redacted = RedactionEngine.redact(letter.text, countryHint: "NL").redactedText
        for value in letter.kept {
            #expect(redacted.contains(value), "“\(value)” was masked:\n\(redacted)")
        }
    }

    @Test("A spaced reference is one placeholder", arguments: cases.filter { !$0.oneToken.isEmpty })
    func spacedReferenceIsOneToken(_ letter: Case) {
        let result = RedactionEngine.redact(letter.text, countryHint: "NL")
        for value in letter.oneToken {
            #expect(result.map.values.contains(value), "“\(value)” is not one masked value: \(result.map)")
        }
    }

    @Test("Recall is 100% in every category")
    func recallByCategory() {
        var found: [String: (masked: Int, total: Int)] = [:]
        for letter in Self.cases {
            let redacted = RedactionEngine.redact(letter.text, countryHint: "NL").redactedText
            for item in letter.masked {
                var tally = found[item.category] ?? (0, 0)
                tally.total += 1
                if !Self.leaks(item.value, in: redacted, original: letter.text) { tally.masked += 1 }
                found[item.category] = tally
            }
        }
        for (category, tally) in found.sorted(by: { $0.key < $1.key }) {
            #expect(tally.masked == tally.total, "\(category): \(tally.masked)/\(tally.total)")
        }
    }
}
