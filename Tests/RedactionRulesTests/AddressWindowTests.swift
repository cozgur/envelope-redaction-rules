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

    /// nl-pension of the layout variants: the sender's name printed on the
    /// row right above the window, in the same column, and again in the
    /// letter's body. It is the sender's, not the reader's (owner, 6 Oct
    /// 2026: counts toward Gate A's sender over-masking).
    private func senderNameAboveWindow(company: String, repeated: Bool) -> (String, LetterLayout) {
        let letter = SyntheticLayout.Letter(
            sender: [company, "Postbus 1100", "1180 BH Amstelveen"],
            recipient: ["De heer C.W.M. van den Heuvel", "Stationsweg 3a", "6811 GD  ARNHEM"],
            body: ["Geachte heer Van den Heuvel,", repeated ? "Met vriendelijke groet, \(company)" : "Met vriendelijke groet"]
        )
        let (text, layout) = SyntheticLayout.make(letter, kind: .a4LeftWindow)
        var moved = layout
        let first = layout.pages[0].lines.first { $0.text == letter.recipient[0] }!
        moved.pages[0].lines = layout.pages[0].lines.map { line in
            guard line.text == company else { return line }
            var line = line
            line.box.y = first.box.maxY + first.box.height * 0.3
            line.box.x = first.box.x
            return line
        }
        return (text, moved)
    }

    @Test("The sender's name right above the window, repeated in the letter, is not part of it")
    func senderNameAboveWindowIsLeftOut() {
        let (text, layout) = senderNameAboveWindow(company: "Sociale Verzekeringsbank", repeated: true)
        let claim = AddressWindow.find(in: text, layout: layout, countryHint: "NL")
        #expect(claim.map { $0.ranges.map { String(text[$0]) } } == ["De heer C.W.M. van den Heuvel", "Stationsweg 3a", "6811 GD  ARNHEM"])
    }

    @Test("A recipient company's name, printed once, stays in the window")
    func recipientCompanyStays() {
        let (text, layout) = senderNameAboveWindow(company: "Northgate Joinery Ltd", repeated: false)
        let claim = AddressWindow.find(in: text, layout: layout, countryHint: "NL")
        #expect(claim.map { $0.ranges.map { String(text[$0]) } }?.first == "Northgate Joinery Ltd")
    }

    @Test("No layout is exactly the engine without one")
    func noLayout() {
        let (text, _) = SyntheticLayout.make(Self.nl, kind: .a4LeftWindow)
        let profile = RedactionProfile(person: .init(surname: "Yilmaz"))
        #expect(RedactionEngine.redact(text, countryHint: "NL", layout: nil, profile: profile)
            == RedactionEngine.redact(text, countryHint: "NL", profile: profile))
    }

    // MARK: - A real-device miss (owner, 6 Oct 2026: an RDW letter, scanned)

    /// The scan's shape: a standard three-line block in the A4 left window,
    /// a dotless non-ASCII initial, a house number with an apartment, and no
    /// letterhead text above the block (a logo).
    static let rdw = SyntheticLayout.Letter(
        sender: [],
        recipient: ["Ö Yılmaz", "Van Vollenhovenstraat 3 401", "3016 BE Rotterdam"],
        body: ["Datum 1 oktober 2026", "Onderwerp: tenaamstelling", "Geachte heer Yılmaz,", "Uw voertuig staat op uw naam."]
    )

    @Test("A person line with a dotless initial in any script: \"Ö Yılmaz\", \"Ş Kaya\", \"Ł Nowak\", \"É Martin\"", arguments: ["Ö Yılmaz", "Ş Kaya", "Ł Nowak", "É Martin", "J Jansen"])
    func dotlessInitial(line: String) {
        #expect(AddressWindow.looksLikeRecipient(line))
    }

    @Test("The RDW block is found when it is the topmost text on the page")
    func rdwTopmostBlock() {
        let (text, layout) = SyntheticLayout.make(Self.rdw, kind: .a4LeftWindow)
        let found = AddressWindow.detect(in: text, layout: layout, countryHint: "NL")
        #expect(found?.kind == .a4Left)
        #expect(found?.boxes.count == 3)
    }

    /// The page inside a larger image: background above and below (about 5%
    /// each), a hand at the left edge. The image is wider than A4's ratio,
    /// which read as US Letter.
    static func loose(_ layout: LetterLayout, bounds: Bool) -> LetterLayout {
        let page = LayoutBox(x: 0.1, y: 0.05, width: 1 / 1.12, height: 0.9)
        var moved = layout
        moved.pages[0].widthMM = 210 * 1.12
        moved.pages[0].heightMM = 297 / 0.9
        moved.pages[0].pageBounds = bounds ? page : nil
        moved.pages[0].lines = layout.pages[0].lines.map { line in
            var line = line
            line.box = LayoutBox(
                x: page.x + line.box.x * page.width, y: page.y + line.box.y * page.height,
                width: line.box.width * page.width, height: line.box.height * page.height
            )
            return line
        }
        return moved
    }

    @Test("A loose crop: the rectangles are measured on the detected page, not the image")
    func looseCropWithBounds() {
        let (text, layout) = SyntheticLayout.make(Self.nl, kind: .a4LeftWindow)
        let found = AddressWindow.detect(in: text, layout: Self.loose(layout, bounds: true), countryHint: "NL")
        #expect(found?.kind == .a4Left)
        #expect(found?.boxes.count == 3)
    }

    @Test("A loose crop with no known page bounds is read as a photo: the shape rule alone")
    func looseCropWithoutBounds() {
        let (text, layout) = SyntheticLayout.make(Self.nl, kind: .a4LeftWindow)
        let found = AddressWindow.detect(in: text, layout: Self.loose(layout, bounds: false), countryHint: "NL")
        #expect(found?.kind == .shape)
    }

    @Test("The RDW scan as it was: loose crop, dotless initial, no letterhead text")
    func rdwAsScanned() {
        let (text, layout) = SyntheticLayout.make(Self.rdw, kind: .a4LeftWindow)
        let found = AddressWindow.detect(in: text, layout: Self.loose(layout, bounds: true), countryHint: "NL")
        #expect(found?.kind == .a4Left)
        #expect(found?.boxes.count == 3)
    }

    // MARK: - The reason, for the DEBUG L2 check

    @Test("The diagnosis gives the reason: page read, bounds, every candidate, the chosen one's components")
    func diagnosisExplains() throws {
        let (text, layout) = SyntheticLayout.make(Self.rdw, kind: .a4LeftWindow)
        let loose = Self.loose(layout, bounds: true)
        let found = AddressWindow.diagnose(in: text, layout: loose, countryHint: "NL")
        #expect(found.rectifiedAsGiven && found.rectified)
        #expect(found.pageBounds == loose.pages[0].pageBounds)
        #expect(found.candidates.count >= 2)
        let accepted = try #require(found.candidates.first { $0.rejection == .accepted })
        #expect(accepted.kind == .a4Left)
        #expect(accepted.personLine && accepted.postcodeLine && !accepted.poBox && !accepted.organisation)
        #expect((accepted.score ?? 0) > 0)
        #expect(found.candidates.contains { $0.rejection == .outsideRectangles })
        // Boxes are the image's, for drawing over it.
        #expect(accepted.boxes.first == loose.pages[0].lines.first { $0.text == "Ö Yılmaz" }?.box)
        #expect(found.detection?.boxes.count == 3)
    }

    @Test("Without page bounds the diagnosis says the rectified page was read as a photo")
    func diagnosisWithoutBounds() {
        let (text, layout) = SyntheticLayout.make(Self.nl, kind: .a4LeftWindow)
        let found = AddressWindow.diagnose(in: text, layout: Self.loose(layout, bounds: false), countryHint: "NL")
        #expect(found.rectifiedAsGiven)
        #expect(!found.rectified)
        #expect(found.pageBounds == nil)
        #expect(found.candidates.allSatisfy { $0.kind == .shape })
    }

    @Test("A sender block scores low and says so")
    func diagnosisLowScore() {
        let letter = SyntheticLayout.Letter(
            sender: [], recipient: ["Gemeente Utrecht", "Postbus 16200", "3500 CE Utrecht"],
            body: ["Datum 1 oktober 2026", "Geachte heer, mevrouw,"]
        )
        let (text, layout) = SyntheticLayout.make(letter, kind: .a4LeftWindow)
        let found = AddressWindow.diagnose(in: text, layout: layout, countryHint: "NL")
        #expect(found.detection == nil)
        #expect(found.candidates.contains { $0.rejection == .lowScore && $0.poBox && $0.organisation })
    }

    // MARK: - The RDW letter again (owner, 6 Oct 2026): synthetic values, the same signatures

    @Test("An NL postcode line is found whatever the phone's region, with OCR's spacing and misreads", arguments: [
        ("3016 BE Rotterdam", "TR"), ("3016BE ROTTERDAM", "TR"), ("3016  BE  Rotterdam", "TR"),
        ("3016\u{00A0}BE Rotterdam", "NL"), ("3016\tBE Rotterdam", "NL"), ("3O16 BE Rotterdam", "NL"),
        ("3016 BE Rotterdam", nil), ("3016 BE Rotterdam", "DE"),
    ] as [(String, String?)])
    func postcodeLineAnyRegion(line: String, region: String?) {
        #expect(AddressWindow.hasPostcode(line, country: region?.uppercased()))
    }

    @Test("A person line: one capital in any script, with or without a dot, then capitalised words", arguments: [
        "Ö Çelik", "O Celik", "Ö. Çelik", "Ş ÖZDEMİR", "Ł Żółkiewski", "É Lefèvre-Durand", "Ž Novák", "Ö Yılmaz-Şahin",
    ])
    func personLineAnyScript(line: String) {
        #expect(AddressWindow.looksLikeRecipient(line))
    }

    @Test("Not a person line: a street, a postcode line, a sentence", arguments: [
        "Van Vollenhovenstraat 3 401", "3016 BE Rotterdam", "Postbus 30000", "Datum 1 oktober 2026",
    ])
    func notAPersonLine(line: String) {
        #expect(!AddressWindow.looksLikeRecipient(line))
    }

    @Test("The RDW page read with a Turkish phone region: the window is found on a full-bleed rectified page")
    func rdwWithTurkishRegion() {
        let letter = SyntheticLayout.Letter(
            sender: [], recipient: ["Ö Çelik", "Van Vollenhovenstraat 3 401", "3016 BE Rotterdam"],
            body: ["Datum 1 oktober 2026", "Geachte heer Çelik,", "Uw voertuig staat op uw naam."]
        )
        let (text, layout) = SyntheticLayout.make(letter, kind: .a4LeftWindow)
        let found = AddressWindow.detect(in: text, layout: layout, countryHint: "TR")
        #expect(found?.kind == .a4Left)
        #expect(found?.boxes.count == 3)
    }

    @Test("A line's signature: classes only, no text", arguments: [
        ("Ö Çelik", "A_Aaaaa"), ("3016 BE Rotterdam", "DDDD_AA_Aaaaaaaaa"), ("Van Vollenhovenstraat 3 401", "Aaa_Aaaaaaaaaaaaaaaaa_D_DDD"),
        ("Postbus 30.000,-", "Aaaaaaa_DD.DDD,-"),
    ])
    func lineSignature(line: String, signature: String) {
        #expect(AddressWindow.signature(of: line) == signature)
    }

    @Test("The diagnosis carries each candidate's line signatures and postcode matches")
    func diagnosisLineSignatures() throws {
        let (text, layout) = SyntheticLayout.make(Self.rdw, kind: .a4LeftWindow)
        let found = AddressWindow.diagnose(in: text, layout: layout, countryHint: "NL")
        let accepted = try #require(found.candidates.first { $0.rejection == .accepted })
        #expect(accepted.lineSignatures == ["A_Aaaaaa", "Aaa_Aaaaaaaaaaaaaaaaa_D_DDD", "DDDD_AA_Aaaaaaaaa"])
        #expect(accepted.linePostcode == [false, false, true])
    }
}
