import Foundation
import Testing

@testable import RedactionRules

/// The span record has to agree with the text it describes, in both
/// directions, or an audit built on it reports the wrong thing with
/// confidence.
@Suite("Masked spans")
struct MaskedSpanTests {

    private static let letter = """
        Gemeente Amsterdam
        Amstel 1
        1011 PN Amsterdam

        Jan de Vries
        Keizersgracht 210
        1016 DW Amsterdam

        Geachte heer de Vries,

        Uw burgerservicenummer 999998456 is bij ons bekend. Betaal EUR 240,00
        op IBAN NL91 ABNA 0417 1643 00 onder vermelding van kenmerk
        2026/AMS/44817. Vragen? Bel 020 624 1111 of mail
        contact@example-amsterdam.nl.
        """

    @Test("Each span names the placeholder that stands at its own offsets")
    func redactedOffsetsPointAtThePlaceholder() {
        let result = RedactionEngine.redact(Self.letter, countryHint: "NL")
        let redacted = Array(result.redactedText)

        #expect(!result.spans.isEmpty)
        for span in result.spans {
            let slice = String(redacted[span.redactedRange])
            #expect(slice == span.placeholder,
                    "offset \(span.redactedRange) reads \(slice), not \(span.placeholder)")
        }
    }

    @Test("Each span names the value that stood at its own offsets")
    func originalOffsetsPointAtTheValue() {
        let result = RedactionEngine.redact(Self.letter, countryHint: "NL")
        let original = Array(Self.letter)

        for span in result.spans {
            let slice = String(original[span.originalRange])
            #expect(slice == result.map[span.placeholder],
                    "offset \(span.originalRange) reads \(slice)")
        }
    }

    @Test("Spans run in order and never overlap")
    func spansAreOrderedAndDisjoint() {
        let result = RedactionEngine.redact(Self.letter, countryHint: "NL")

        for (earlier, later) in zip(result.spans, result.spans.dropFirst()) {
            #expect(earlier.originalRange.upperBound <= later.originalRange.lowerBound)
            #expect(earlier.redactedRange.upperBound <= later.redactedRange.lowerBound)
        }
    }

    @Test("A repeated value keeps one placeholder across several spans")
    func repeatedValueSharesOnePlaceholder() {
        let twice = """
            Zaaknummer 2026/AMS/44817

            Wij verwijzen naar 2026/AMS/44817 in deze brief.
            """
        let result = RedactionEngine.redact(twice, countryHint: "NL")
        let references = result.spans.filter { $0.kind == .reference }

        #expect(references.count == 2, "Both mentions should be masked")
        #expect(Set(references.map(\.placeholder)).count == 1,
                "One value is one placeholder, however often it appears")
    }

    @Test("A span can be found by an offset inside it")
    func lookupByOffset() throws {
        let result = RedactionEngine.redact(Self.letter, countryHint: "NL")
        let first = try #require(result.spans.first)
        let middle = (first.originalRange.lowerBound + first.originalRange.upperBound) / 2

        #expect(result.span(coveringOriginalOffset: middle) == first)
        #expect(result.span(coveringOriginalOffset: first.originalRange.upperBound) != first)
    }

    @Test("Nothing masked means no spans")
    func plainTextHasNoSpans() {
        let result = RedactionEngine.redact("Dit is een brief zonder gegevens.")
        #expect(result.spans.isEmpty)
        #expect(result.redactedText == "Dit is een brief zonder gegevens.")
    }
}
