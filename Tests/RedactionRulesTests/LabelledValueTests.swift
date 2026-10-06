import Foundation
import Testing

@testable import RedactionRules

/// Gate A after set 5 (owner, 6 Oct 2026): IBANs and identity numbers at
/// 100%, labelled references at 95% -- label-driven catch-alls, and the
/// precision they must keep (dates, amounts, article numbers, years and phone
/// numbers stay readable).
@Suite("Labelled values: IBAN, identity numbers, references")
struct LabelledValueTests {

    private func masked(_ value: String, in text: String, country: String, as kind: PIIKind) -> Bool {
        let result = RedactionEngine.redact(text, countryHint: country)
        guard let found = text.range(of: value) else { return false }
        let lo = text.distance(from: text.startIndex, to: found.lowerBound)
        let hi = lo + value.count
        // Every character of the value inside spans of this kind.
        let spans = result.spans.filter { $0.kind == kind }
        return (lo..<hi).allSatisfy { offset in
            let character = text[text.index(text.startIndex, offsetBy: offset)]
            return character.isWhitespace || spans.contains { $0.originalRange.contains(offset) }
        }
    }

    private func untouched(_ value: String, in text: String, country: String) -> Bool {
        RedactionEngine.redact(text, countryHint: country).redactedText.contains(value)
    }

    // MARK: - IBAN

    @Test("After an IBAN label, an IBAN-shaped value is masked whatever its checksum", arguments: [
        ("IBAN: NL98 RABO 8261 265O 94", "NL98 RABO 8261 265O 94", "NL"),
        ("Bitte überweisen Sie auf IBAN DE89 3704 0044 0532 0130 01 (Prüfziffer falsch).", "DE89 3704 0044 0532 0130 01", "DE"),
    ])
    func labelledIBAN(text: String, value: String, country: String) {
        #expect(masked(value, in: text, country: country, as: .iban), "\(RedactionEngine.redact(text, countryHint: country).redactedText)")
    }

    @Test("Unlabelled: a country code, check digits and the country's length make it an IBAN, OCR misreads and all", arguments: [
        ("Maak het bedrag over naar NL98 RABO 8261 265O 94 o.v.v. leerlingnummer 20193344.", "NL98 RABO 8261 265O 94", "NL"),
        ("Zahlbar an DE12 5001 0517 0648 4898 9O bis zum 1. November 2026.", "DE12 5001 0517 0648 4898 9O", "DE"),
        ("Payable to GB30 NWBK 1794 42O3 8123 74 within five working days.", "GB30 NWBK 1794 42O3 8123 74", "GB"),
    ])
    func unlabelledIBANShape(text: String, value: String, country: String) {
        #expect(masked(value, in: text, country: country, as: .iban), "\(RedactionEngine.redact(text, countryHint: country).redactedText)")
    }

    @Test("Precision: not every two letters and two digits are an IBAN", arguments: [
        ("Zie artikel NL20 van de regeling, uiterlijk 12 oktober 2026.", "NL20", "NL"),
        ("Model DE12 3456 werd in 2026 geleverd.", "DE12 3456", "NL"),
    ])
    func ibanPrecision(text: String, value: String, country: String) {
        #expect(untouched(value, in: text, country: country), "\(RedactionEngine.redact(text, countryHint: country).redactedText)")
    }

    // MARK: - Identity numbers

    @Test("After an identity label, the value to the end of the field is masked", arguments: [
        ("Ihre Rentenversicherungsnummer 49 110407 S 029 wurde vergeben.", "49 110407 S 029", "DE"),
        ("een kopie van uw paspoort (nummer NW5K18P34) en een kopie van het", "NW5K18P34", "NL"),
        ("Uw verblijfsdocument (documentnummer NC4R71TK9) blijft geldig.", "NC4R71TK9", "NL"),
        ("Paspoortnummer: NX7L22R81", "NX7L22R81", "NL"),
        ("Identiteitskaart IW4K71PL2 is vermist.", "IW4K71PL2", "NL"),
        ("V-nummer: 2817739104", "2817739104", "NL"),
        ("Versichertennummer: A123456789", "A123456789", "DE"),
        ("Krankenversichertennummer T987654321 bitte angeben.", "T987654321", "DE"),
        ("Sozialversicherungsnummer 12 150885 M 042", "12 150885 M 042", "DE"),
        ("Steuer-ID: 12 345 678 901", "12 345 678 901", "DE"),
        ("NIE: X1234567L", "X1234567L", "ES"),
        ("TC Kimlik No: 12345678901", "12345678901", "TR"),
        ("N° de sécurité sociale : 1 85 05 78 006 084 36", "1 85 05 78 006 084 36", "FR"),
        ("SSN: 123-45-6789", "123-45-6789", "US"),
        ("NI number: QQ 12 34 56 C", "QQ 12 34 56 C", "GB"),
        ("National Insurance number QQ123456C", "QQ123456C", "GB"),
    ])
    func labelledIdentity(text: String, value: String, country: String) {
        #expect(masked(value, in: text, country: country, as: .idNumber), "\(RedactionEngine.redact(text, countryHint: country).spans.map { "\($0.kind) \($0.originalRange)" })")
    }

    @Test("Patterns without a label: a German health-insurance number and a Dutch document number", arguments: [
        ("Mitglied A123456789, Familienversicherung ab 1. Oktober 2026.", "A123456789", "DE"),
        ("Documenten: NW5K18P34, geldig tot 2031.", "NW5K18P34", "NL"),
    ])
    func identityPatterns(text: String, value: String, country: String) {
        #expect(masked(value, in: text, country: country, as: .idNumber))
    }

    @Test("Precision: a word after an identity label stays; a date stays", arguments: [
        ("Rentenversicherungsnummer 49 110407 S 029 vergeben.", "vergeben", "DE"),
        ("Uw paspoort verloopt op 12 maart 2027.", "12 maart 2027", "NL"),
        ("Documentnummer en geboortedatum zijn verplicht.", "geboortedatum", "NL"),
    ])
    func identityPrecision(text: String, value: String, country: String) {
        #expect(untouched(value, in: text, country: country))
    }

    // MARK: - References

    @Test("After a reference label, the value to the end of the field is masked, spaces and slashes included", arguments: [
        ("Ons kenmerk: 2026/HR/04471", "2026/HR/04471", "NL"),
        ("Uw kenmerk AB-7781 C", "AB-7781 C", "NL"),
        ("Dossiernummer 2026 4471 0098", "2026 4471 0098", "NL"),
        ("Zaaknummer: C/13/71128 / HA ZA 26-114", "C/13/71128 / HA ZA 26-114", "NL"),
        ("Klantnummer 7710 4402 19", "7710 4402 19", "NL"),
        ("Aktenzeichen: 3 K 112/26", "3 K 112/26", "DE"),
        ("Az.: 12 C 714/26", "12 C 714/26", "DE"),
        ("Geschäftszeichen IV/2-4471", "IV/2-4471", "DE"),
        ("Kundennummer 0412-07-02.", "0412-07-02", "DE"),
        ("Mieternummer 0412-07-02.", "0412-07-02", "DE"),
        ("Objekt-Nr. 0412 / WE 07", "0412 / WE 07", "DE"),
        ("Vorgangsnummer: V-2026-118", "V-2026-118", "DE"),
        ("Réf. : 26/CAF/88412", "26/CAF/88412", "FR"),
        ("N° de dossier 4471023 R", "4471023 R", "FR"),
        ("N° allocataire : 4471023 R", "4471023 R", "FR"),
        ("Expediente: 202546118342", "202546118342", "ES"),
        ("Boletín de denuncia: 0041882", "0041882", "ES"),
        ("Referencia: 2026GRC4417038Q", "2026GRC4417038Q", "ES"),
        ("Sygn. akt I C 1442/26", "I C 1442/26", "PL"),
        ("prosimy podać sygnaturę akt I C 1442/26.", "I C 1442/26", "PL"),
        ("Znak sprawy: SM/CZ/1442/2026", "SM/CZ/1442/2026", "PL"),
        ("L.dz. SM/CZ/1442/2026", "SM/CZ/1442/2026", "PL"),
        ("Dosya No: 2026/18442 E.", "2026/18442 E.", "TR"),
        ("Sayı: 84212345-105[VUK]-2026/18442", "84212345-105[VUK]-2026/18442", "TR"),
        ("Our ref: DRS-26-0448812", "DRS-26-0448812", "GB"),
        ("Your ref 120/AB45678", "120/AB45678", "GB"),
        ("Employer PAYE reference 120/AB45678", "120/AB45678", "GB"),
        ("Case no. 2026-CV-1144", "2026-CV-1144", "US"),
        ("Claim no 88-1123-4", "88-1123-4", "US"),
        ("Policy no: HX 4471 220", "HX 4471 220", "GB"),
        ("Account no. 7710 4402", "7710 4402", "US"),
    ])
    func labelledReference(text: String, value: String, country: String) {
        #expect(masked(value, in: text, country: country, as: .reference), "\(RedactionEngine.redact(text, countryHint: country).redactedText)")
    }

    @Test("Precision: dates, amounts, articles, sections, years and phone numbers stay readable", arguments: [
        ("Datum: 14 oktober 2026", "14 oktober 2026", "NL"),
        ("Bedrag: € 284,00", "€ 284,00", "NL"),
        ("Bezwaar op grond van art. 6:5 Awb is mogelijk.", "art. 6:5 Awb", "NL"),
        ("Gemäß § 7 Abs. 2 BetrKV.", "§ 7 Abs. 2", "DE"),
        ("Kenmerk: zie boven, aanslagjaar 2026.", "aanslagjaar 2026", "NL"),
        ("Ons kenmerk: 2026/HR/04471, datum 3 november 2026", "3 november 2026", "NL"),
    ])
    func referencePrecision(text: String, value: String, country: String) {
        #expect(untouched(value, in: text, country: country), "\(RedactionEngine.redact(text, countryHint: country).redactedText)")
    }

    @Test("A phone number after a phone label is never a reference")
    func phoneIsNotReference() {
        let text = "Telefoonnummer: 020 123 4567\nKlantnummer 7710 4402 19"
        let result = RedactionEngine.redact(text, countryHint: "NL")
        let phone = text.distance(from: text.startIndex, to: text.range(of: "020 123 4567")!.lowerBound)
        #expect(!result.spans.contains { $0.kind == .reference && $0.originalRange.contains(phone) })
    }
}
