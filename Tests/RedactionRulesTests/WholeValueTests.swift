import Foundation
import Testing

@testable import RedactionRules

/// A value is masked whole or not at all.
///
/// Every case here was found by the golden set once it started asserting the
/// *kind* of the placeholder standing at each recorded value, rather than only
/// that the value was gone. A half-masked identifier passes an absence check --
/// the whole string really is missing -- while the part left behind is still
/// recognisably the thing that was meant to be hidden.
@Suite("Whole values")
struct WholeValueTests {

    @Test("A policy number is masked whole, as a reference")
    func policyNumberKeepsItsPrefix() throws {
        // The tail of this number, 77341-2026, is a structurally valid SSN if
        // the separator is allowed to appear in one position and not the
        // other. It was masked as [ID_NUMBER_1], leaving "TK-" in the clear.
        let text = "Versichertennummer: TK-77341-2026"
        let result = RedactionEngine.redact(text, countryHint: "DE")

        let span = try #require(result.spans.first)
        #expect(span.kind == .reference)
        #expect(result.map[span.placeholder] == "TK-77341-2026")
        #expect(result.redactedText == "Versichertennummer: [REFERENCE_1]")
    }

    @Test("An SSN is recognised however it is written",
          arguments: ["987-65-4320", "987 65 4320", "987654320"])
    func ssnFormsStillMatch(number: String) {
        let result = RedactionEngine.redact("Social Security Number: \(number)", countryHint: "US")
        #expect(result.counts[.idNumber] == 1, "\(number) should still be an identity number")
    }

    @Test("A half-separated run is not an SSN", arguments: ["77341-2026", "987-654320", "12345-6789"])
    func mixedSeparatorsAreNotSSNs(number: String) {
        // Nobody writes an SSN with a separator in one gap and not the other.
        // Reading one there is how a foreign reference number acquires an
        // identity label on a letter from a country that has no SSN.
        let format = NationalIDFormat.unitedStates
        let matches = NationalIDRule(format: format).matches(in: "Reference \(number) applies")
        #expect(matches.isEmpty)
    }

    @Test("A Dutch municipal service number keeps its prefix")
    func serviceNumberKeepsItsPrefix() throws {
        // 14 020 is one number: the national 14-prefix and the area code. The
        // keyword rule used to claim the 020 and leave the 14.
        let text = "Een afspraak maakt u telefonisch via 14 020 of per e-mail."
        let result = RedactionEngine.redact(text, countryHint: "NL")

        let span = try #require(result.spans.first)
        #expect(span.kind == .phone)
        #expect(result.map[span.placeholder] == "14 020")
    }

    @Test("Opening hours after a phone word are not a phone number")
    func openingHoursSurvive() {
        // The cost of letting a two-digit group lead: times are written the
        // same way. They survive because a two-digit lead has to be followed
        // by a group of three or more.
        let text = "Wij zijn telefonisch bereikbaar van 09.00 tot 17.00 uur."
        let result = RedactionEngine.redact(text, countryHint: "NL")

        #expect(result.redactedText == text, "Redacted: \(result.redactedText)")
    }
}
