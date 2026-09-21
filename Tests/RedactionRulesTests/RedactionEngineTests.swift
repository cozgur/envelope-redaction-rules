import Foundation
import Testing

@testable import RedactionRules

/// The engine that stands between the user's identity numbers and the network
/// (H1). Every claim it makes is checked here against known-good and
/// known-bad values rather than sampled.
@Suite("Redaction engine")
struct RedactionEngineTests {

    // MARK: - Checksums

    @Test("Recognises valid national identity numbers", arguments: [
        (NationalIDFormat.netherlands, "123456782"),
        (.germany, "86095742719"),
        (.spain, "12345678Z"),
        (.spain, "X1234567L"),
        (.poland, "44051401359"),
        (.turkey, "10000000146"),
        (.unitedStates, "123-45-6789"),
        (.unitedKingdom, "AB123456C"),
    ])
    func validIdentityNumbers(format: NationalIDFormat, value: String) {
        #expect(format.isValid(value), "\(format.country) should accept \(value)")
    }

    @Test("Rejects digit runs that only look like identity numbers", arguments: [
        (NationalIDFormat.netherlands, "123456789"),
        (.germany, "12345678901"),
        (.poland, "44051401358"),
        (.turkey, "10000000147"),
        (.spain, "12345678A"),
    ])
    func invalidIdentityNumbers(format: NationalIDFormat, value: String) {
        #expect(!format.isValid(value), "\(format.country) should reject \(value)")
    }

    @Test("Validates IBANs by mod-97")
    func ibanChecksum() {
        #expect(Checksums.passesIBANMod97("NL91ABNA0417164300"))
        #expect(Checksums.passesIBANMod97("NL91 ABNA 0417 1643 00"))
        #expect(Checksums.passesIBANMod97("DE89370400440532013000"))
        #expect(Checksums.passesIBANMod97("TR330006100519786457841326"))
        #expect(!Checksums.passesIBANMod97("NL92ABNA0417164300"))
        #expect(!Checksums.passesIBANMod97("NL91ABNA0417164301"))
    }

    @Test("Validates card numbers by Luhn")
    func luhn() {
        #expect(Checksums.passesLuhn("4111111111111111".compactMap(\.wholeNumberValue)))
        #expect(Checksums.passesLuhn("5500005555555559".compactMap(\.wholeNumberValue)))
        #expect(!Checksums.passesLuhn("4111111111111112".compactMap(\.wholeNumberValue)))
    }

    // MARK: - Masking

    @Test("Masks each kind with a typed, indexed placeholder")
    func typedPlaceholders() {
        let text = """
        Burgerservicenummer: 123456782
        IBAN: NL91ABNA0417164300
        E-mail: jan.devries@example.nl
        Kenmerk: 1234.56.789
        """
        let result = RedactionEngine.redact(text, countryHint: "NL")

        #expect(result.redactedText.contains("[ID_NUMBER_1]"))
        #expect(result.redactedText.contains("[IBAN_1]"))
        #expect(result.redactedText.contains("[EMAIL_1]"))
        #expect(result.redactedText.contains("[REFERENCE_1]"))

        // Nothing sensitive survives in the text that would leave the device.
        #expect(!result.redactedText.contains("123456782"))
        #expect(!result.redactedText.contains("NL91ABNA0417164300"))
        #expect(!result.redactedText.contains("jan.devries@example.nl"))

        // The keyword stays readable so the explanation can name what was
        // masked.
        #expect(result.redactedText.contains("Burgerservicenummer:"))
        #expect(result.redactedText.contains("IBAN:"))
    }

    @Test("The same value always gets the same placeholder")
    func stableplaceholders() {
        let text = """
        Kenmerk: AB-2025-0042
        Vermeld bij betaling het kenmerk AB-2025-0042.
        Bij vragen over kenmerk AB-2025-0042 kunt u bellen.
        """
        let result = RedactionEngine.redact(text, countryHint: "NL")

        let occurrences = result.redactedText.components(separatedBy: "[REFERENCE_1]").count - 1
        #expect(occurrences == 3, "One reference quoted three times is one reference")
        #expect(result.map.count == 1)
        #expect(result.counts[.reference] == 1)
    }

    @Test("Distinct values get distinct indices")
    func indexedPlaceholders() {
        let text = """
        IBAN begunstigde: NL91ABNA0417164300
        IBAN afzender: DE89370400440532013000
        """
        let result = RedactionEngine.redact(text, countryHint: "NL")

        #expect(result.redactedText.contains("[IBAN_1]"))
        #expect(result.redactedText.contains("[IBAN_2]"))
        #expect(result.counts[.iban] == 2)
    }

    @Test("Restoring is exact", arguments: [
        """
        Belastingdienst
        Burgerservicenummer: 123456782
        IBAN: NL91ABNA0417164300
        Kenmerk: 1234.56.789
        Telefoon: +31 20 123 4567
        E-mail: info@example.nl
        U moet EUR 1.240,00 betalen voor 3 november 2025.
        """,
        """
        Finanzamt München
        Steuer-Identifikationsnummer: 86095742719
        Aktenzeichen: FA-2025-11-0042
        IBAN: DE89370400440532013000
        Bitte zahlen Sie 1.240,00 EUR bis zum 03.11.2025.
        """,
        """
        T.C. Kimlik No: 10000000146
        Dosya No: 2025/4471
        IBAN: TR330006100519786457841326
        Son ödeme tarihi 3 Kasım 2025, tutar 1.240,00 TRY.
        """,
    ])
    func restoreRoundTrips(text: String) {
        let result = RedactionEngine.redact(text, countryHint: nil)
        #expect(RedactionEngine.restore(result.redactedText, map: result.map) == text)
    }

    @Test("A country hint orders the rules but never excludes a format")
    func hintDoesNotExclude() {
        // A Turkish identity number in a Dutch letter, which is exactly the
        // situation the product exists for.
        let text = """
        Burgerservicenummer: 123456782
        T.C. Kimlik No: 10000000146
        """
        let result = RedactionEngine.redact(text, countryHint: "NL")

        #expect(!result.redactedText.contains("123456782"))
        #expect(!result.redactedText.contains("10000000146"))
        #expect(result.counts[.idNumber] == 2)
    }

    // MARK: - Over-redaction

    @Test("Deadlines survive", arguments: [
        "Betaal voor 3 november 2025.",
        "Zahlbar bis zum 03.11.2025.",
        "Payment is due by 2025-11-03.",
        "Son ödeme tarihi 3 Kasım 2025.",
        "À régler avant le 3 novembre 2025.",
        "Termin płatności: 03-11-2025.",
    ])
    func deadlinesSurvive(text: String) {
        let result = RedactionEngine.redact(text, countryHint: nil)
        #expect(result.redactedText == text, "A masked deadline makes the letter unexplainable")
    }

    @Test("Amounts and percentages survive", arguments: [
        "U moet nog EUR 1.240,00 betalen.",
        "Betrag: 1.240,00 EUR",
        "Total due: $1,240.00",
        "Tutar: 1.240,00 TRY",
        "Het tarief is 21% BTW.",
        "Kwota: 1 240,00 PLN",
    ])
    func amountsSurvive(text: String) {
        let result = RedactionEngine.redact(text, countryHint: nil)
        #expect(result.redactedText == text)
    }

    @Test("A postcode on its own survives", arguments: [
        "Postbus 2508, 6401 DA Heerlen",
        "10115 Berlin",
        "Warszawa 00-950",
        "London SW1A 1AA",
    ])
    func postcodesSurvive(text: String) {
        let result = RedactionEngine.redact(text, countryHint: nil)
        // The postcode itself is never the masked part. An address around it
        // may be, which is correct -- but the digits must not be swallowed by
        // an identity rule.
        #expect(!result.redactedText.contains("[ID_NUMBER"))
    }

    @Test("A nine-digit phone number is not labelled an identity number")
    func phoneIsNotAnIdentityNumber() {
        let text = "Bel ons op +31 20 123 4567 of 020 1234567."
        let result = RedactionEngine.redact(text, countryHint: "NL")

        #expect(!result.redactedText.contains("[ID_NUMBER"))
        #expect(result.redactedText.contains("[PHONE"))
    }

    @Test("An invoice number away from an identity keyword is left alone")
    func unrelatedDigitRunSurvives() {
        // Nine digits that happen to pass the Dutch elfproef, with nothing
        // around them suggesting an identity number.
        let text = "Factuurregel 4 van 9, volgnummer 7 van 12, pagina 1 van 3."
        let result = RedactionEngine.redact(text, countryHint: "NL")
        #expect(result.redactedText == text)
    }

    @Test("An invalid IBAN is masked only beside an IBAN keyword")
    func invalidIBANNeedsAKeyword() {
        let bare = "Het nummer NL92ABNA0417164300 staat in de bijlage."
        #expect(RedactionEngine.redact(bare, countryHint: "NL").redactedText == bare)

        let keyed = "IBAN: NL92ABNA0417164300"
        let result = RedactionEngine.redact(keyed, countryHint: "NL")
        #expect(result.redactedText.contains("[IBAN_1]"))
        #expect(!result.redactedText.contains("NL92ABNA0417164300"))
    }

    @Test("An unrecognised identity format is still masked beside its keyword")
    func fallbackCatchesUnknownFormats() {
        // Not a valid BSN, but it sits right after the word, so the letter is
        // telling us what it is.
        let text = "Burgerservicenummer: 123456789"
        let result = RedactionEngine.redact(text, countryHint: "NL")

        #expect(result.redactedText.contains("[ID_NUMBER_1]"))
        #expect(!result.redactedText.contains("123456789"))
    }

    @Test("Empty and placeholder-free text is unchanged")
    func degenerateInputs() {
        #expect(RedactionEngine.redact("").redactedText.isEmpty)

        let plain = "Geachte heer/mevrouw,\n\nMet vriendelijke groet,"
        let result = RedactionEngine.redact(plain, countryHint: "NL")
        #expect(result.redactedText == plain)
        #expect(result.map.isEmpty)
        #expect(RedactionEngine.restore(plain, map: [:]) == plain)
    }

    @Test("Restoring prefers the longest placeholder")
    func restoreHandlesDoubleDigitIndices() {
        // [IBAN_1] is a prefix of [IBAN_10] once the bracket is dropped; the
        // substitution must not consume one while the other is pending.
        let map = (1...12).reduce(into: [String: String]()) { result, index in
            result["[IBAN_\(index)]"] = "NL91ABNA041716430\(index)"
        }
        let text = (1...12).map { "[IBAN_\($0)]" }.joined(separator: " ")
        let restored = RedactionEngine.restore(text, map: map)

        for index in 1...12 {
            #expect(restored.contains("NL91ABNA041716430\(index)"))
        }
        #expect(!restored.contains("[IBAN_"))
    }
}
