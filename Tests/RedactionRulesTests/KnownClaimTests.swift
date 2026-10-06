import Foundation
import Testing

@testable import RedactionRules

/// Claims made outside the rules, and the order they merge in.
///
/// Redaction v2 plan §1 (owner, 6 October 2026): inside the address window,
/// the window's block claim wins, so the whole window is one `[ADDRESS_n]`,
/// the recipient's name included; the reader's own details (L1) claim
/// everywhere outside it; then the rules.
@Suite("Known claims")
struct KnownClaimTests {

    static let letter = """
    Gemeente Amsterdam
    Amstel 1
    1011 PN Amsterdam

    Mevrouw A. Yilmaz
    Hoofdstraat 1
    1011 AA Amsterdam

    Geachte mevrouw Yilmaz,

    Wij hebben uw aanvraag ontvangen.
    """

    private func range(of value: String, in text: String, after: String? = nil) throws -> Range<String.Index> {
        let start = try after.map { try #require(text.range(of: $0)).upperBound } ?? text.startIndex
        return try #require(text.range(of: value, range: start..<text.endIndex))
    }

    private func windowLines(_ text: String) throws -> [Range<String.Index>] {
        try ["Mevrouw A. Yilmaz", "Hoofdstraat 1", "1011 AA Amsterdam"].map { try range(of: $0, in: text) }
    }

    @Test("The window's name is part of ADDRESS_1; the salutation's surname is NAME_1")
    func windowWinsInsideProfileOutside() throws {
        let text = Self.letter
        let window = KnownClaim(kind: .address, ranges: try windowLines(text), source: .window)
        // L1 found the reader's name twice: inside the window and in the
        // salutation. Inside, the window claim wins; outside, L1 does.
        let profile = KnownClaim(
            kind: .name,
            ranges: [try range(of: "A. Yilmaz", in: text), try range(of: "Yilmaz", in: text, after: "Geachte mevrouw ")],
            source: .profile
        )

        let result = RedactionEngine.redact(text, countryHint: "NL", known: [window, profile])

        #expect(result.map["[ADDRESS_1]"] == "Mevrouw A. Yilmaz\nHoofdstraat 1\n1011 AA Amsterdam")
        #expect(result.map["[NAME_1]"] == "Yilmaz")
        #expect(result.redactedText.contains("Geachte mevrouw [NAME_1],"))
        #expect(!result.redactedText.contains("Yilmaz"))
        #expect(!result.redactedText.contains("Hoofdstraat"))
        // The window is one claim: no name label inside it.
        let windowSpans = result.spans.filter { $0.placeholder == "[ADDRESS_1]" }
        #expect(windowSpans.count == 3)
        #expect(result.spans.filter { $0.kind == .name }.count == 1)
        // And the sender's letterhead stays.
        #expect(result.redactedText.hasPrefix("Gemeente Amsterdam\nAmstel 1\n1011 PN Amsterdam"))
    }

    @Test("A window whose lines OCR serialised apart is still one ADDRESS, in reading order")
    func nonContiguousWindow() throws {
        // A right-hand window read row by row: each window line comes after
        // the letterhead's line on the same row.
        let text = """
        Belastingdienst          Mevrouw A. Yilmaz
        Postbus 2865             Hoofdstraat 1
        6401 DJ Heerlen          1011 AA Amsterdam

        Geachte mevrouw Yilmaz,
        """
        let lines = try windowLines(text)
        let result = RedactionEngine.redact(
            text, countryHint: "NL",
            known: [KnownClaim(kind: .address, ranges: lines, source: .window)]
        )
        #expect(result.map["[ADDRESS_1]"] == "Mevrouw A. Yilmaz\nHoofdstraat 1\n1011 AA Amsterdam")
        #expect(result.counts[.address] == 1)
        #expect(result.redactedText.contains("Belastingdienst          [ADDRESS_1]"))
        #expect(result.redactedText.contains("Postbus 2865             [ADDRESS_1]"))
    }

    @Test("The window claim wins over the rules' own recipient block")
    func windowOverRules() throws {
        let text = Self.letter
        // Only the street and postcode lines: the rules would claim the
        // block with the name line; the window decides what the block is.
        let lines = try ["Hoofdstraat 1", "1011 AA Amsterdam"].map { try range(of: $0, in: text) }
        let result = RedactionEngine.redact(
            text, countryHint: "NL",
            known: [KnownClaim(kind: .address, ranges: lines, source: .window)]
        )
        #expect(result.map["[ADDRESS_1]"] == "Hoofdstraat 1\n1011 AA Amsterdam")
    }

    @Test("A profile match inside the sender's letterhead is not masked")
    func profileRespectsLetterhead() throws {
        // A reader who lives on the street the municipality is on.
        let text = Self.letter
        let inLetterhead = KnownClaim(kind: .address, ranges: [try range(of: "Amstel 1", in: text)], source: .profile)
        let result = RedactionEngine.redact(text, countryHint: "NL", known: [inLetterhead])
        #expect(result.redactedText.contains("Amstel 1\n1011 PN Amsterdam"))
    }

    @Test("No known claims is exactly today's engine")
    func emptyKnownIsTheOldCall() {
        for text in [Self.letter, "Studentnummer: STU-2026-11842\nquoting STU-2026-11842."] {
            #expect(RedactionEngine.redact(text, countryHint: "NL")
                == RedactionEngine.redact(text, countryHint: "NL", known: []))
        }
    }
}
