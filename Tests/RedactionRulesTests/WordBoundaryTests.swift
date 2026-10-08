import Foundation
import Testing

@testable import RedactionRules

/// A name is masked as a word, never inside one (owner, 9 Oct 2026).
///
/// Found writing the App Review demo letters: a reader named "Voorbeeld" on a
/// letter from "Voorbeeld Zorgverzekeringen" in "Voorbeeldhaven", imported
/// as a PDF, came out as "[NAME_1] Zorgverzekeringen" and "[NAME_1]haven".
/// A PDF's text layer has no blank lines between blocks, which is the path
/// that found the surname; the repeat pass then spread it as a substring.
/// Synthetic values throughout.
@Suite("Word boundaries")
struct WordBoundaryTests {
    /// The health insurer demo letter's text layer, as PDFKit reads it.
    static let pdfTextLayer = """
        Voorbeeld Zorgverzekeringen
        Postbus 0001 · 2000 AB Voorbeeldhaven
        De heer B. Voorbeeld
        Proefweg 7
        2011 CD Voorbeeldhaven
        Voorbeeldhaven, 4 november 2026
        Relatienummer: 88 4410 29
        Polisnummer: VZ-2026-551870
        Herinnering: openstaande premie
        Geachte heer Voorbeeld,
        Wij hebben uw premie voor de basisverzekering over de maanden september en oktober 2026
        nog niet ontvangen. Het openstaande bedrag is € 289,90.
        Met vriendelijke groet,
        Afdeling Debiteuren, Voorbeeld Zorgverzekeringen
        """

    @Test("A surname is not masked inside a longer word")
    func notInsideAWord() {
        let redacted = RedactionEngine.redact(Self.pdfTextLayer, countryHint: "NL").redactedText
        #expect(!redacted.contains("]haven"), "masked inside Voorbeeldhaven")
        #expect(redacted.contains("Voorbeeldhaven"))
        // The reader's own name, after the honorific, is still masked.
        #expect(!redacted.contains("heer Voorbeeld,"))
        #expect(!redacted.contains("B. Voorbeeld"))
    }

    @Test("The repeat pass spreads a name to whole words only")
    func repeatPassIsWordBounded() {
        let text = "Geachte heer Lindqvist,\nLindqvist en Lindqvistweg 4 en Lindqvists en Lindqvist."
        // Two more occurrences of the word, none inside "Lindqvistweg" or "Lindqvists".
        #expect(RedactionEngine.repeatableOccurrenceCount(of: "Lindqvist", kind: .name, in: text) == 2)
    }
}
