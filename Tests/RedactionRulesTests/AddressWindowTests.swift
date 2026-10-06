import Foundation
import Testing

@testable import RedactionRules
import RedactionRulesTestSupport

/// L2 -- the address window from the page's geometry (redaction v2 plan §1,
/// step 3), on synthetic layouts of every kind the plan names.
@Suite("Address window (L2)")
struct AddressWindowTests {

    static let nl = SyntheticLayout.Letter(
        sender: ["Gemeente Utrecht", "Postbus 16200", "3500 CE Utrecht"],
        recipient: ["Mw. A. Yilmaz", "Hoofdstraat 12-II", "3511 AB  UTRECHT"],
        returnLine: "Retouradres Postbus 16200 3500 CE Utrecht",
        body: ["Datum: 1 oktober 2026", "Betreft: uw aanvraag", "", "Geachte mevrouw Yilmaz,", "Wij hebben uw aanvraag ontvangen."]
    )
    static let gb = SyntheticLayout.Letter(
        sender: ["Westminster City Council", "64 Victoria Street", "London SW1E 6QP"],
        recipient: ["Ms A. Yilmaz", "12 High Street, Flat 4", "London SW1A 1AA"],
        body: ["Date: 1 October 2026", "Dear Ms Yilmaz,", "We have received your application."]
    )
    static let us = SyntheticLayout.Letter(
        sender: ["Department of the Treasury", "Internal Revenue Service", "Kansas City, MO 64999-0002"],
        recipient: ["MS A YILMAZ", "12 MAIN ST APT 4B", "BROOKLYN NY 11201-1234"],
        body: ["Notice date October 1, 2026", "Dear Ms. Yilmaz,", "You have a balance due."]
    )

    private func windowText(_ letter: SyntheticLayout.Letter, _ kind: SyntheticLayout.Kind, country: String) -> String? {
        let (text, layout) = SyntheticLayout.make(letter, kind: kind)
        guard let claim = AddressWindow.find(in: text, layout: layout, countryHint: country) else { return nil }
        return claim.ranges.map { String(text[$0]) }.joined(separator: "\n")
    }

    @Test("Finds the recipient block, and only it, on every NL layout", arguments: [
        SyntheticLayout.Kind.a4LeftWindow, .a4RightWindow, .a4SameRow, .a4ReturnLine, .photoSkewed,
    ])
    func dutchLayouts(kind: SyntheticLayout.Kind) {
        #expect(windowText(Self.nl, kind, country: "NL") == Self.nl.recipient.joined(separator: "\n"))
    }

    @Test("UK: the DL and C5 windows", arguments: [SyntheticLayout.Kind.ukDL, .ukC5])
    func ukWindows(kind: SyntheticLayout.Kind) {
        #expect(windowText(Self.gb, kind, country: "GB") == Self.gb.recipient.joined(separator: "\n"))
    }

    @Test("US Letter: the #10 window, chosen by the page's aspect ratio")
    func usWindow() {
        #expect(windowText(Self.us, .us10, country: "US") == Self.us.recipient.joined(separator: "\n"))
    }

    @Test("The same-row layout's window is several ranges in the text, read in order")
    func sameRowIsInterleaved() throws {
        let (text, layout) = SyntheticLayout.make(Self.nl, kind: .a4SameRow)
        // OCR interleaves the columns: sender line, recipient line, …
        #expect(text.hasPrefix("Gemeente Utrecht\nMw. A. Yilmaz\nPostbus 16200\nHoofdstraat 12-II"))
        let claim = try #require(AddressWindow.find(in: text, layout: layout, countryHint: "NL"))
        #expect(claim.ranges.count == 3)
    }

    @Test("The return-address line is left out")
    func returnLineExcluded() {
        let found = windowText(Self.nl, .a4ReturnLine, country: "NL")
        #expect(found?.contains("Retouradres") == false)
    }

    @Test("A rectified page uses the rectangles: a block outside them is not the window")
    func rectifiedNeedsTheRectangle() {
        let (text, layout) = SyntheticLayout.make(Self.nl, kind: .a4LeftWindow)
        // Move the recipient block to the foot of the page.
        var moved = layout
        moved.pages[0].lines = layout.pages[0].lines.map { line in
            guard Self.nl.recipient.contains(line.text) else { return line }
            var line = line
            line.box.y -= 0.6
            return line
        }
        #expect(AddressWindow.find(in: text, layout: moved, countryHint: "NL") == nil)
    }

    @Test("A photo uses the shape alone, and never takes the sender's letterhead")
    func photoNeverTakesTheLetterhead() {
        let letter = SyntheticLayout.Letter(
            sender: ["Gemeente Utrecht", "Postbus 16200", "3500 CE Utrecht"],
            recipient: ["Gemeente Utrecht", "Postbus 16200", "3500 CE Utrecht"].map { $0 + " " },
            body: ["Geachte heer, mevrouw,"]
        )
        // Both blocks look like the sender's: no recipient opener, a PO box.
        let (text, layout) = SyntheticLayout.make(letter, kind: .photoSkewed)
        #expect(AddressWindow.find(in: text, layout: layout, countryHint: "NL") == nil)
    }

    @Test("Through the engine: the window is one ADDRESS, name included; the salutation is NAME_1")
    func throughTheEngine() {
        let (text, layout) = SyntheticLayout.make(Self.nl, kind: .a4SameRow)
        let profile = RedactionProfile(person: .init(givenNames: "Ayşe", surname: "Yılmaz"))
        let result = RedactionEngine.redact(text, countryHint: "NL", layout: layout, profile: profile)
        #expect(result.map["[ADDRESS_1]"] == Self.nl.recipient.joined(separator: "\n"))
        #expect(result.redactedText.contains("Geachte mevrouw [NAME_1],"))
        #expect(result.redactedText.contains("Gemeente Utrecht"))
        #expect(result.redactedText.contains("Postbus 16200"))
    }

    @Test("No layout is exactly the engine without one")
    func noLayout() {
        let (text, _) = SyntheticLayout.make(Self.nl, kind: .a4LeftWindow)
        let profile = RedactionProfile(person: .init(surname: "Yilmaz"))
        #expect(RedactionEngine.redact(text, countryHint: "NL", layout: nil, profile: profile)
            == RedactionEngine.redact(text, countryHint: "NL", profile: profile))
    }
}
