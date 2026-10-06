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
        /// The letter laid out on page 1 in one or more kinds (from the
        /// step-6 set on). Each is measured as its own text, with its boxes
        /// fed to L2.
        var layouts: [CaseLayout] = []
        var testDescription: String { id }

        enum CodingKeys: String, CodingKey { case id, country, profile, text, masked, kept, keptOrdinary, layouts }

        /// `keptOrdinary` may be left out where a letter has none.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            country = try container.decode(String.self, forKey: .country)
            profile = try container.decode(RedactionProfile.self, forKey: .profile)
            text = try container.decode(String.self, forKey: .text)
            masked = try container.decode([NLRecallTests.Masked].self, forKey: .masked)
            kept = try container.decodeIfPresent([String].self, forKey: .kept) ?? []
            keptOrdinary = try container.decodeIfPresent([String].self, forKey: .keptOrdinary) ?? []
            layouts = try container.decodeIfPresent([CaseLayout].self, forKey: .layouts) ?? []
        }
    }

    /// An independent set's layout, as the author brief gives it.
    struct CaseLayout: Decodable, Sendable {
        struct Page: Decodable, Sendable { var widthMM: Double?; var heightMM: Double? }
        struct Line: Decodable, Sendable { var text: String; var box: [Double] }
        var kind: String
        var rectified: Bool
        var page: Page?
        var lines: [Line]

        /// The layout's own text -- its lines joined by newlines -- and the
        /// engine's layout for it.
        var letter: (text: String, layout: LetterLayout) {
            var offset = 0
            var lines: [LayoutLine] = []
            for line in self.lines {
                let box = line.box.count == 4
                    ? LayoutBox(x: line.box[0], y: line.box[1], width: line.box[2], height: line.box[3])
                    : LayoutBox(x: 0, y: 0, width: 0, height: 0)
                lines.append(LayoutLine(text: line.text, box: box, characterOffset: offset))
                offset += line.text.count + 1
            }
            let page = LayoutPage(lines: lines, widthMM: page?.widthMM, heightMM: page?.heightMM, rectified: rectified)
            return (self.lines.map(\.text).joined(separator: "\n"), LetterLayout(pages: [page]))
        }
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

    /// Failing fixtures made from set 1's in-scope misses, and the given-name
    /// rule's cases (owner, 6 Oct 2026).
    static let fixes = load("l1-fixes-1")

    /// Independent set 1 -- retired to regression on 6 Oct 2026, after its
    /// misses became `l1-fixes-1`. Its two ambiguous given names alone
    /// outside a salutation ("Noor", "Leon") are out of scope by the
    /// owner's rule and are not counted.
    static let regression = load("l1-independent-1").map { letter in
        var letter = letter
        letter.masked.removeAll { item in
            (letter.id == "nl-basisschool-ouders" && item.value == "Noor")
                || (letter.id == "de-schule-mensa" && item.value == "Leon")
        }
        return letter
    }

    /// Failing fixtures made from set 2's in-scope misses, Polish case forms,
    /// NL street abbreviations and city aliases (owner, 6 Oct 2026).
    static let fixes2 = load("l1-fixes-2")

    /// Independent set 2 -- retired to regression on 6 Oct 2026. Its
    /// "Długiej 12/4" without "ul." is outside the owner's Polish street rule
    /// and counts as a non-NL miss (non-NL is ≥ 95%, not 100%).
    static let regression2 = load("l1-independent-2")

    /// Failing fixtures made from set 3's misses and the forms the owner
    /// listed (6 Oct 2026).
    static let fixes3 = load("l1-fixes-3")

    /// Independent set 3 -- retired to regression on 6 Oct 2026. The L1-only
    /// loop ends with it (owner): Gate A is measured on the full engine.
    static let regression3 = load("l1-independent-3")

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

    /// Whether the occurrence stands right beside the profile's postcode --
    /// after it, or before it with at most a state code between -- which is
    /// what "on the postcode's line" means for a city.
    private static func onPostcodeLine(_ occurrence: Range<Int>, of letter: Case) -> Bool {
        guard let postcode = letter.profile.postcode else { return false }
        var pattern = ""
        for (index, character) in postcode.filter({ !$0.isWhitespace }).enumerated() {
            if index > 0 { pattern += #"[ \t]{0,2}"# }
            switch character {
            case "0": pattern += "[0Oo]"
            case "1": pattern += "[1lI]"
            default: pattern += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let text = letter.text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: range.upperBound)
            let gapAfter = occurrence.lowerBound - upper
            let gapBefore = lower - occurrence.upperBound
            if (0...4).contains(gapAfter) || (0...5).contains(gapBefore) { return true }
        }
        return false
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
        // A letter with layouts is measured once per layout, each its own
        // text with its boxes given to L2; one without, as plain text.
        let expanded: [(letter: Case, layout: LetterLayout?)] = cases.flatMap { letter -> [(Case, LetterLayout?)] in
            guard !letter.layouts.isEmpty else { return [(letter, nil)] }
            return letter.layouts.map { layout in
                var one = letter
                let built = layout.letter
                one.id = "\(letter.id) [\(layout.kind)]"
                one.text = built.text
                return (one, built.layout)
            }
        }
        var tally = Tally()
        for (letter, layout) in expanded {
            let result = RedactionEngine.redact(letter.text, countryHint: letter.country, layout: layout, profile: letter.profile)
            for item in letter.masked {
                // Gate A's scope (owner, 6 Oct 2026): names everywhere, and
                // NL-format addresses, are 100%; other address formats are
                // counted apart (≥ 95% for 1.0).
                let category = item.category == "name" || letter.country == "NL"
                    ? item.category : "\(item.category) (non-NL)"
                var occurrences = offsets(of: item.value, in: letter.text)
                if occurrences.isEmpty { tally.missing.append("\(letter.id): “\(item.value)” is not in the text") }
                // A city alone in a sentence is out of scope (owner, 6 Oct
                // 2026): only a city on the postcode's line is counted.
                if item.category == "city" {
                    occurrences = occurrences.filter { onPostcodeLine($0, of: letter) }
                }
                for occurrence in occurrences {
                    var entry = tally.masked[category] ?? (0, 0)
                    entry.total += 1
                    let words = wordOffsets(in: item.value, at: occurrence.lowerBound)
                    if words.allSatisfy({ covered($0, by: result.spans) }) {
                        entry.found += 1
                    } else {
                        tally.leaks.append("\(letter.id): \(category) “\(item.value)”")
                    }
                    tally.masked[category] = entry
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
        for leak in tally.leaks { print("L1 \(name) missed \(leak)") }
    }

    /// What Gate A's L1 line requires of a tally: no name and no NL-format
    /// miss, and non-NL address formats at 95% or more.
    static func scopeFailures(_ tally: Tally) -> [String] {
        var failures = tally.leaks.filter { !$0.contains("(non-NL)") }
        let nonNL = tally.masked.filter { $0.key.hasSuffix("(non-NL)") }.values
        let found = nonNL.reduce(0) { $0 + $1.found }
        let total = nonNL.reduce(0) { $0 + $1.total }
        if total > 0, Double(found) / Double(total) < 0.95 {
            failures.append("non-NL addresses \(found)/\(total) < 95%: \(tally.leaks.filter { $0.contains("(non-NL)") })")
        }
        return failures
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

    @Test("Set 1's misses and the given-name rule: fixed")
    func fixesFromSetOne() {
        let tally = Self.measure(Self.fixes)
        Self.report("fixes-1", tally)
        #expect(Self.fixes.count >= 20)
        #expect(tally.missing.isEmpty, "\(tally.missing)")
        #expect(Self.scopeFailures(tally).isEmpty, "\(Self.scopeFailures(tally))")
        #expect(tally.ordinaryOverMasked.isEmpty, "ordinary-word over-masking: \(tally.ordinaryOverMasked)")
        // Sender over-masking is reported, not gated here: set 1's "kept"
        // lists include phone numbers and references, which the rules mask
        // by design, and sender addresses are L3's (Gate A, step 6).
    }

    @Test("Set 2's misses, Polish case forms, NL abbreviations and aliases: fixed")
    func fixesFromSetTwo() {
        let tally = Self.measure(Self.fixes2)
        Self.report("fixes-2", tally)
        #expect(tally.missing.isEmpty, "\(tally.missing)")
        #expect(tally.leaks.isEmpty, "missed: \(tally.leaks)")
        #expect(tally.ordinaryOverMasked.isEmpty, "ordinary-word over-masking: \(tally.ordinaryOverMasked)")
    }

    @Test("Independent set 2, retired: holds Gate A's L1 scope")
    func regressionSetTwo() {
        let tally = Self.measure(Self.regression2)
        Self.report("independent-2 (regression)", tally)
        #expect(Self.scopeFailures(tally).isEmpty, "\(Self.scopeFailures(tally))")
        #expect(tally.ordinaryOverMasked.isEmpty, "ordinary-word over-masking: \(tally.ordinaryOverMasked)")
    }

    @Test("Independent set 1, retired: holds Gate A's L1 scope")
    func regressionSetOne() {
        let tally = Self.measure(Self.regression)
        Self.report("independent-1 (regression)", tally)
        #expect(Self.scopeFailures(tally).isEmpty, "\(Self.scopeFailures(tally))")
        #expect(tally.ordinaryOverMasked.isEmpty, "ordinary-word over-masking: \(tally.ordinaryOverMasked)")
    }

    @Test("Set 3's misses and the listed forms: fixed")
    func fixesFromSetThree() {
        let tally = Self.measure(Self.fixes3)
        Self.report("fixes-3", tally)
        #expect(tally.missing.isEmpty, "\(tally.missing)")
        #expect(tally.leaks.isEmpty, "missed: \(tally.leaks)")
        #expect(tally.ordinaryOverMasked.isEmpty, "ordinary-word over-masking: \(tally.ordinaryOverMasked)")
    }

    @Test("Independent set 3, retired: holds Gate A's L1 scope")
    func regressionSetThree() {
        let tally = Self.measure(Self.regression3)
        Self.report("independent-3 (regression)", tally)
        #expect(Self.scopeFailures(tally).isEmpty, "\(Self.scopeFailures(tally))")
        #expect(tally.ordinaryOverMasked.isEmpty, "ordinary-word over-masking: \(tally.ordinaryOverMasked)")
    }

    /// Gate A, step 6 (owner, 6 Oct 2026): independent set 4, written from
    /// the brief with page layouts by an agent that saw nothing else, and
    /// committed (`024cdc2`) before this first run. Every layout of every
    /// letter is measured as its own page, full engine, with the letter's
    /// profile.
    static let gateA = load("l1-independent-4")

    @Test("Gate A on independent set 4: L1 scope, and sender over-masking ≤ 5% of letters")
    func gateASetFour() {
        #expect(Self.gateA.count >= 40)
        let tally = Self.measure(Self.gateA)
        Self.report("set4", tally)
        let letters = Set(Self.gateA.map(\.id))
        let overMaskedLetters = Set(tally.senderOverMasked.map { $0.components(separatedBy: " [").first ?? $0 })
        let pages = Self.gateA.reduce(0) { $0 + max(1, $1.layouts.count) }
        let overMaskedPages = Set(tally.senderOverMasked.map { $0.components(separatedBy: ": ").first ?? $0 })
        print("GATEA set4 letters \(letters.count), pages \(pages)")
        print("GATEA set4 sender over-masking: \(overMaskedLetters.count)/\(letters.count) letters, \(overMaskedPages.count)/\(pages) pages")
        for one in tally.senderOverMasked { print("GATEA set4 over-masked \(one)") }
        for one in tally.ordinaryOverMasked { print("GATEA set4 ordinary over-masked \(one)") }
        #expect(tally.missing.isEmpty, "\(tally.missing)")
        // Gate A failed on this set, 6 Oct 2026 (docs/reports in the app
        // repo: 2026-10-06-gate-a-and-cp6.md): names 439/442, NL addresses
        // 90/98, sender over-masking 20/46 letters. Strict known issues, so
        // CI stays green and the run fails the day either line passes.
        withKnownIssue("Gate A set 4: L1 scope misses (names, NL addresses)", isIntermittent: false) {
            #expect(Self.scopeFailures(tally).isEmpty, "\(Self.scopeFailures(tally))")
        }
        withKnownIssue("Gate A set 4: sender over-masking above 5% of letters", isIntermittent: false) {
            #expect(Double(overMaskedLetters.count) <= 0.05 * Double(letters.count), "\(tally.senderOverMasked)")
        }
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
