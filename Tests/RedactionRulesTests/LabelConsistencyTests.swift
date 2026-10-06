import Foundation
import Testing

@testable import RedactionRules

/// One value, one label, across the whole letter; and the whole token.
///
/// Redaction v2 plan §1 L3 (owner, 2 October 2026). The golden set's school
/// letters label the student number `[REFERENCE_1]` on its field line and
/// `STU-[PHONE_1]` in the payment sentence: the field-line rule recognises the
/// whole value, the phone rule then claims the digits inside the sentence's
/// copy of it, and the repeat pass finds that copy already overlapped and
/// leaves it. The result is a prefix in the clear, a second label for the
/// same secret, and a phone number in the summary that is not a phone number.
/// The same shape was in forty of the ninety-six golden letters.
@Suite("Label consistency")
struct LabelConsistencyTests {

    @Test("The NL student number is one REFERENCE everywhere, whole")
    func dutchStudentNumber() throws {
        let text = """
        Studentnummer: STU-2026-11842
        Burgerservicenummer: 999088300

        U kunt in één keer betalen vóór 27 oktober 2026 op rekeningnummer NL91ABNA0417164300 onder
        vermelding van studentnummer STU-2026-11842, of een digitale machtiging afgeven voor
        betaling in termijnen via Studielink.
        """
        let result = RedactionEngine.redact(text, countryHint: "NL")

        #expect(!result.redactedText.contains("STU-"))
        #expect(result.redactedText.components(separatedBy: "[REFERENCE_1]").count - 1 == 2)
        #expect(result.map["[REFERENCE_1]"] == "STU-2026-11842")
        #expect(result.counts[.phone] == nil, "no phone number was in this text")
        #expect(!result.map.values.contains("2026-11842"))
    }

    @Test("The PL student number is one REFERENCE everywhere, whole")
    func polishStudentNumber() throws {
        let text = """
        Numer albumu: STU-2026-11842
        PESEL: 22712124351

        Wpłaty należy dokonać do dnia 27 października 2026 na rachunek PL61109010140000071219812874, podając w tytule
        wyłącznie numer albumu STU-2026-11842, albo złożyć wniosek o rozłożenie opłaty na raty
        w dziekanacie.
        """
        let result = RedactionEngine.redact(text, countryHint: "PL")

        #expect(!result.redactedText.contains("STU-"))
        #expect(result.redactedText.components(separatedBy: "[REFERENCE_1]").count - 1 == 2)
        #expect(result.map["[REFERENCE_1]"] == "STU-2026-11842")
        #expect(result.counts[.phone] == nil)
    }

    @Test("A notice number with a letter prefix and no separator is masked whole")
    func prefixWithoutSeparator() {
        // us-tax: "CP" directly against the digits, so the phone rule's claim
        // started one character inside the token.
        let text = """
        Notice number: CP14-2026-11-0042

        You can pay by electronic transfer, quoting notice number CP14-2026-11-0042. Interest
        continues to accrue.
        """
        let result = RedactionEngine.redact(text, countryHint: "US")

        #expect(!result.redactedText.contains("CP["))
        #expect(result.redactedText.components(separatedBy: "[REFERENCE_1]").count - 1 == 2)
        #expect(result.counts[.phone] == nil)
    }

    @Test("A prefixed number the letter never labels is still masked whole, as a reference")
    func unlabelledPrefixedNumber() {
        // No field line names it, so nothing recognised the whole value first.
        // The digits look like a phone number to the phone rule; the token
        // they sit in has a letter prefix, which is what a reference looks
        // like and a phone number never does.
        let text = "Please quote INC-2026-04471 when you write to us."
        let result = RedactionEngine.redact(text, countryHint: "GB")

        #expect(result.redactedText == "Please quote [REFERENCE_1] when you write to us.")
        #expect(result.map["[REFERENCE_1]"] == "INC-2026-04471")
    }

    @Test("A real phone number is left a phone number")
    func phoneStaysPhone() {
        let text = "Bel 020 525 8080 of mail ons."
        let result = RedactionEngine.redact(text, countryHint: "NL")
        #expect(result.counts[.phone] == 1)
        #expect(result.counts[.reference] == nil)
    }
}
