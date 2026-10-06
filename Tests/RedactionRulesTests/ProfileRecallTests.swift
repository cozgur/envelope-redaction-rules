import Foundation
import Testing

@testable import RedactionRules

/// L1 — the reader's own details — measured on letters that carry a profile
/// (redaction v2 plan §1, step 2).
///
/// A case gives the profile the reader would have entered, which need not be
/// spelled as the letter prints it, and three lists:
///
/// - `masked`: every value of the reader's that the letter prints. **Every
///   occurrence** of each must lie inside masked spans (honorifics apart).
///   This is L1 recall, and it is 100% or the step is not done.
/// - `kept`: text the explanation needs, the sender's details first. Masking
///   any occurrence is sender over-masking.
/// - `keptOrdinary`: the reader's surname used as an ordinary word or a
///   place. Masking it is **over-masking of ordinary words**, a failure
///   reported apart from sender over-masking (owner, 6 Oct 2026).
///
/// Checked by position against `RedactionResult.spans`, not by searching the
/// masked text: "De Groot Handelsonderneming" may stay while "heer De Groot"
/// goes, and a search for "Groot" cannot tell the two apart.
@Suite("Profile recall (L1)")
struct ProfileRecallTests {

    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        var id: String
        var country: String
        var profile: RedactionProfile
        var text: String
        var masked: [NLRecallTests.Masked]
        var kept: [String]
        var keptOrdinary: [String]
        var testDescription: String { id }
    }

    static func load(_ name: String) -> [Case] {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        do {
            return try JSONDecoder().decode([Case].self, from: data)
        } catch {
            Issue.record("\(name).json does not decode: \(error)")
            return []
        }
    }

    static let tolerance = load("l1-tolerance")
    static let ordinary = load("l1-ordinary-words")

    /// The fresh independent set step 2 is measured on, once it exists.
    static let independent = load("l1-independent-1")

    // MARK: - Position checks

    private static func offsets(of value: String, in text: String) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var start = text.startIndex
        while let range = text.range(of: value, range: start..<text.endIndex) {
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            found.append(lower..<(lower + value.count))
            start = range.upperBound
        }
        return found
    }

    /// The character offsets of `value`'s words, without honorifics.
    private static func wordOffsets(in value: String, at base: Int) -> [Range<Int>] {
        var words: [Range<Int>] = []
        var index = 0
        var current: Int?
        for character in value {
            if character.isLetter || character.isNumber {
                if current == nil { current = index }
            } else if let start = current {
                words.append((base + start)..<(base + index))
                current = nil
            }
            index += 1
        }
        if let start = current { words.append((base + start)..<(base + index)) }
        let honorifics = ProfileMatcher.honorifics
        return words.filter { range in
            let word = String(value.dropFirst(range.lowerBound - base).prefix(range.count))
            return !honorifics.contains(ProfileMatcher.fold(word))
        }
    }

    private static func covered(_ range: Range<Int>, by spans: [RedactionResult.MaskedSpan]) -> Bool {
        range.allSatisfy { offset in spans.contains { $0.originalRange.contains(offset) } }
    }

    private static func touched(_ range: Range<Int>, by spans: [RedactionResult.MaskedSpan]) -> Bool {
        spans.contains { $0.originalRange.overlaps(range) }
    }

    struct Tally {
        var masked: [String: (found: Int, total: Int)] = [:]
        var leaks: [String] = []
        var senderOverMasked: [String] = []
        var ordinaryOverMasked: [String] = []
        var missing: [String] = []
    }

    static func measure(_ cases: [Case]) -> Tally {
        var tally = Tally()
        for letter in cases {
            let result = RedactionEngine.redact(letter.text, countryHint: letter.country, profile: letter.profile)
            for item in letter.masked {
                let occurrences = offsets(of: item.value, in: letter.text)
                if occurrences.isEmpty { tally.missing.append("\(letter.id): “\(item.value)” is not in the text") }
                for occurrence in occurrences {
                    var entry = tally.masked[item.category] ?? (0, 0)
                    entry.total += 1
                    let words = wordOffsets(in: item.value, at: occurrence.lowerBound)
                    if words.allSatisfy({ covered($0, by: result.spans) }) {
                        entry.found += 1
                    } else {
                        tally.leaks.append("\(letter.id): \(item.category) “\(item.value)”")
                    }
                    tally.masked[item.category] = entry
                }
            }
            for value in letter.kept {
                for occurrence in offsets(of: value, in: letter.text) where touched(occurrence, by: result.spans) {
                    tally.senderOverMasked.append("\(letter.id): “\(value)”")
                }
            }
            for value in letter.keptOrdinary {
                let occurrences = offsets(of: value, in: letter.text)
                if occurrences.isEmpty { tally.missing.append("\(letter.id): “\(value)” is not in the text") }
                for occurrence in occurrences where touched(occurrence, by: result.spans) {
                    tally.ordinaryOverMasked.append("\(letter.id): “\(value)”")
                }
            }
        }
        return tally
    }

    private static func report(_ name: String, _ tally: Tally) {
        for (category, entry) in tally.masked.sorted(by: { $0.key < $1.key }) {
            print("L1 \(name) \(category) \(entry.found)/\(entry.total)")
        }
        print("L1 \(name) sender over-masking \(tally.senderOverMasked.count), ordinary-word over-masking \(tally.ordinaryOverMasked.count)")
    }

    // MARK: - Tests

    @Test("The fixtures load and cover names, addresses and postcodes")
    func fixturesLoad() {
        #expect(Self.tolerance.count >= 18)
        #expect(Self.ordinary.count >= 8)
        let categories = Set(Self.tolerance.flatMap { $0.masked.map(\.category) })
        #expect(categories.isSuperset(of: ["name", "address", "postcode"]))
    }

    @Test("Every tolerance rule: L1 finds every occurrence, and keeps what it must")
    func toleranceRules() {
        let tally = Self.measure(Self.tolerance)
        Self.report("tolerance", tally)
        #expect(tally.missing.isEmpty, "\(tally.missing)")
        #expect(tally.leaks.isEmpty, "missed: \(tally.leaks)")
        #expect(tally.senderOverMasked.isEmpty, "sender over-masking: \(tally.senderOverMasked)")
        #expect(tally.ordinaryOverMasked.isEmpty, "ordinary-word over-masking: \(tally.ordinaryOverMasked)")
    }

    @Test("Ordinary words kept: the reader's surname as a word or a place is not masked")
    func ordinaryWordsKept() {
        let tally = Self.measure(Self.ordinary)
        Self.report("ordinary", tally)
        #expect(tally.missing.isEmpty, "\(tally.missing)")
        #expect(tally.ordinaryOverMasked.isEmpty, "ordinary-word over-masking: \(tally.ordinaryOverMasked)")
        #expect(tally.leaks.isEmpty, "missed: \(tally.leaks)")
        #expect(tally.senderOverMasked.isEmpty, "sender over-masking: \(tally.senderOverMasked)")
    }

    @Test("The independent set: L1 = 100% in every category")
    func independentSet() {
        guard !Self.independent.isEmpty else { return }
        let tally = Self.measure(Self.independent)
        Self.report("independent-1", tally)
        #expect(tally.missing.isEmpty, "\(tally.missing)")
        #expect(tally.leaks.isEmpty, "missed: \(tally.leaks)")
        #expect(tally.ordinaryOverMasked.isEmpty, "ordinary-word over-masking: \(tally.ordinaryOverMasked)")
        // Sender over-masking is Gate A's ≤ 5% line, measured in step 6; it is
        // reported here, not gated.
    }

    @Test("A digit postcode never takes part of a phone number")
    func digitPostcodeAndPhone() {
        let profile = RedactionProfile(person: .init(surname: "Yilmaz"), postcode: "34100", city: "İstanbul")
        let result = RedactionEngine.redact("Telefon: 0212 34100 55", countryHint: "TR", profile: profile)
        #expect(!result.redactedText.contains("[ADDRESS"))
    }

    @Test("Without a window, the rules' recipient block takes in the profile's matches whole")
    func blockAbsorbsProfile() {
        let text = "Westminster City Council\n64 Victoria Street\nLondon SW1E 6QP\n\nMs A. Yilmaz\n12 High Street, Flat 4\nLondon SW1A 1AA\n\nDear Ms Yilmaz,"
        let profile = RedactionProfile(person: .init(givenNames: "Ayse", surname: "Yilmaz"),
                                       street: "High Street", houseNumber: "12", postcode: "SW1A 1AA", city: "London")
        let result = RedactionEngine.redact(text, countryHint: "GB", profile: profile)
        #expect(!result.redactedText.contains("Flat 4"))
        #expect(!result.redactedText.contains("London SW1A"))
        #expect(result.redactedText.contains("Westminster City Council"))
        #expect(result.redactedText.contains("Dear Ms [NAME_"))
    }

    @Test("No profile is exactly the engine without one")
    func noProfile() {
        let text = "Mw. A. Yilmaz\nHoofdstraat 1\n1011 AA Amsterdam\n\nGeachte mevrouw Yilmaz,"
        #expect(RedactionEngine.redact(text, countryHint: "NL", profile: nil) == RedactionEngine.redact(text, countryHint: "NL"))
    }
}
