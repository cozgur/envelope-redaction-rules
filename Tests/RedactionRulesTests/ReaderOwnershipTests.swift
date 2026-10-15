import Foundation
import Testing
@testable import RedactionRules

/// Only the reader's own phone, email and IBAN are masked (owner, 15 Oct
/// 2026): the sender's contact details and payment account stay readable.
@Suite("Reader ownership")
struct ReaderOwnershipTests {
    private func redacted(_ text: String, _ country: String = "NL") -> String {
        RedactionEngine.redact(text, countryHint: country).redactedText
    }

    @Test("The sender's phone, email and account stay; the reader's are masked", arguments: [
        ("Bel ons op 020 525 8080.", "020 525 8080", false),
        ("Mail naar info@gemeente.example.nl voor vragen.", "info@gemeente.example.nl", false),
        ("Maak het bedrag over op NL91 ABNA 0417 1643 00 t.n.v. Belastingdienst.", "NL91 ABNA 0417 1643 00", false),
        ("Wij storten het op uw rekening NL91 ABNA 0417 1643 00.", "NL91 ABNA 0417 1643 00", true),
        ("We will refund your account GB30 NWBK 1794 4203 8123 74.", "GB30 NWBK 1794 4203 8123 74", true),
        ("Ödeme TR33 0006 1005 1978 6457 8413 26 numaralı hesabınıza yapılacaktır.", "TR33 0006 1005 1978 6457 8413 26", true),
        ("Ödemenin TR33 0006 1005 1978 6457 8413 26 numaralı hesaba yapılması gerekmektedir.", "TR33 0006 1005 1978 6457 8413 26", false),
    ])
    func ownership(text: String, value: String, readers: Bool) {
        let country = value.hasPrefix("GB") ? "GB" : value.hasPrefix("TR") ? "TR" : "NL"
        let out = redacted(text, country)
        #expect(out.contains(value) == !readers, "\(out)")
    }

    @Test("Once the letter calls a value the reader's, it is masked everywhere it appears")
    func perValue() {
        let text = """
        Wij maken het bedrag over op je rekening NL85 BUNQ 9366 1071 72.
        Is NL85 BUNQ 9366 1071 72 niet meer je rekeningnummer? Pas het aan.
        """
        #expect(!redacted(text).contains("NL85 BUNQ 9366 1071 72"))
    }

    @Test("A labelled identity number or reference on phone-shaped digits stays masked")
    func labelledNumbersStay() {
        #expect(!redacted("Identifikationsnummer: 94 860 527 146", "DE").contains("94 860 527 146"))
        #expect(!redacted("Please quote INC-2026-04471 when you write to us.", "GB").contains("INC-2026-04471"))
        #expect(!redacted("Naheffingsaanslag: 7712 0934 5521").contains("7712 0934 5521"))
    }
}
