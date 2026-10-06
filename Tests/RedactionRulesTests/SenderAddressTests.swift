import Foundation
import Testing

@testable import RedactionRules

/// L3 address precision (owner, 6 Oct 2026): the sender's PO box and an
/// organisation's own address lines are not masked by the rules; the
/// reader's own PO box, when it is in their profile, still is.
@Suite("Sender address (L3 precision)")
struct SenderAddressTests {

    @Test("A sender's PO box and its postcode line are kept; the recipient block is masked", arguments: [
        ("Belastingdienst\nPostbus 2865\n6401 DJ Heerlen", "NL", "Postbus 2865", "6401 DJ Heerlen"),
        ("Deutsche Rentenversicherung\nPostfach 10 31 20\n10827 Berlin", "DE", "Postfach 10 31 20", "10827 Berlin"),
        ("Medical Collections Inc\nPO Box 9184\nBoston, MA 02114", "US", "PO Box 9184", "Boston, MA 02114"),
        ("City Parking Services\nP.O. Box 532\nManchester M60 2LA", "GB", "P.O. Box 532", "Manchester M60 2LA"),
        ("Agencia Tributaria\nApartado de Correos 123\n28080 Madrid", "ES", "Apartado de Correos 123", "28080 Madrid"),
        ("Urząd Skarbowy\nSkrytka pocztowa 15\n00-950 Warszawa", "PL", "Skrytka pocztowa 15", "00-950 Warszawa"),
        ("Caisse d'allocations familiales\nBP 4521\n69000 Lyon", "FR", "BP 4521", "69000 Lyon"),
        ("Mutuelle Générale\nBoîte postale 12\n75009 Paris", "FR", "Boîte postale 12", "75009 Paris"),
        ("Klantenservice Energie\nAntwoordnummer 1234\n1000 VB Amsterdam", "NL", "Antwoordnummer 1234", "1000 VB Amsterdam"),
    ])
    func poBoxKept(sender: String, country: String, box: String, postcodeLine: String) {
        let recipient: String = switch country {
        case "NL": "Mevrouw A. Yilmaz\nHoofdstraat 12\n3511 AB  UTRECHT"
        case "DE": "Herrn Jonas Weber\nLindenweg 3\n50667 Köln"
        case "US": "MS ANNA GREEN\n12 MAIN ST APT 4B\nBROOKLYN NY 11201"
        case "GB": "Ms Anna Green\n12 High Street\nLondon SW1A 1AA"
        case "ES": "D. Javier Rubio\nCalle Mayor 5, 2º izq\n28013 Madrid"
        case "PL": "Pani Anna Kowalska\nul. Długa 12/4\n00-238 Warszawa"
        default: "Madame Claire Petit\n7 rue des Lilas\n69003 Lyon"
        }
        let text = "\(sender)\n\n\(recipient)\n\nObjet : votre dossier du 2 octobre 2026.\nMerci."
        let redacted = RedactionEngine.redact(text, countryHint: country).redactedText
        #expect(redacted.contains(box), "\(redacted)")
        #expect(redacted.contains(postcodeLine), "\(redacted)")
        let street = recipient.split(separator: "\n")[1]
        #expect(!redacted.contains(street), "\(redacted)")
    }

    @Test("An organisation's own street address is kept; the reader's below it is masked")
    func organisationAddressKept() {
        let text = """
            Muster Logistik GmbH
            Industriestraße 40
            50389 Wesseling

            Herrn Jonas Weber
            Lindenweg 3
            50667 Köln

            Wesseling, 1. Oktober 2026
            Sehr geehrter Herr Weber,
            Ihre Arbeitszeit ändert sich ab dem 1. November 2026.
            """
        let redacted = RedactionEngine.redact(text, countryHint: "DE").redactedText
        #expect(redacted.contains("Industriestraße 40"))
        #expect(redacted.contains("50389 Wesseling"))
        #expect(!redacted.contains("Lindenweg 3"))
        #expect(!redacted.contains("Jonas Weber"))
    }

    @Test("The same line: an organisation, a comma, its address")
    func organisationSameLine() {
        let text = "Gemeente Delft, Stadhuis 1, 2611 JR Delft\n\nDhr. P. de Vries\nKerkstraat 5\n2611 HA Delft\n\nGeachte heer De Vries,\nUw aanvraag is ontvangen."
        let redacted = RedactionEngine.redact(text, countryHint: "NL").redactedText
        #expect(redacted.contains("Stadhuis 1"))
        #expect(!redacted.contains("Kerkstraat 5"))
    }

    @Test("The reader's own PO box, in their profile, is masked")
    func readerPOBoxMasked() {
        let text = "Belastingdienst\nPostbus 2865\n6401 DJ Heerlen\n\nDe heer J. Jansen\nPostbus 4412\n1000 AB  AMSTERDAM\n\nGeachte heer Jansen,\nUw aangifte is ontvangen. Wij sturen de beschikking naar Postbus 4412."
        let profile = RedactionProfile(
            person: .init(givenNames: "Jan", surname: "Jansen"),
            street: "Postbus", houseNumber: "4412", postcode: "1000 AB", city: "Amsterdam"
        )
        let redacted = RedactionEngine.redact(text, countryHint: "NL", profile: profile).redactedText
        #expect(!redacted.contains("4412"), "\(redacted)")
        #expect(!redacted.contains("1000 AB"))
        #expect(redacted.contains("Postbus 2865"), "the sender's box stays")
    }

    @Test("A PO box is never read as a phone number")
    func poBoxNotPhone() {
        let text = "Finanzamt Heidelberg\nPostfach 10 31 20\n69021 Heidelberg\n\nRückfragen: 06221 59 0"
        let result = RedactionEngine.redact(text, countryHint: "DE")
        #expect(result.redactedText.contains("Postfach 10 31 20"))
    }

    /// The shapes independent set 4 printed: no blank line between the
    /// letterhead and the recipient, a department line under the
    /// organisation, a return line with "·" between its parts.
    @Test("Set 4's shapes: a department line, no blank lines, a dotted return line", arguments: [
        ("Muster Logistik GmbH\nPersonalabteilung\nIndustriestraße 40\n50389 Wesseling\nMuster Logistik GmbH · Industriestraße 40 · 50389 Wesseling\nHerrn\nThomas Weber\nLindenweg 3\n50667 Köln\nSehr geehrter Herr Weber,", "DE", ["Industriestraße 40", "50389 Wesseling"], ["Lindenweg 3", "50667 Köln"]),
        ("Zentrale Bußgeldstelle\nBayerisches Polizeiverwaltungsamt\nPostfach 1201\n94612 Viechtach\nZBS · Postfach 1201 · 94612 Viechtach\nHerrn\nSebastian Weber\nAhornweg 7\n81369 München\nSehr geehrter Herr Weber,", "DE", ["Postfach 1201", "94612 Viechtach"], ["Ahornweg 7", "81369 München"]),
        ("Bay State Recovery Services, Inc.\nPO Box 9184\nBoston, MA 02114\nROSA MARTIN\n35 ELM ST APT 2\nWORCESTER MA 01608\nDear Ms. Martin,", "US", ["PO Box 9184", "Boston, MA 02114"], ["35 ELM ST APT 2", "WORCESTER MA 01608"]),
        ("Agencia Tributaria\nDelegación Especial de Madrid\nC/ Guzmán el Bueno, 139\n28003 Madrid\nGARCIA LOPEZ ANA\nC/ MAYOR 5, 3º B\n28013 MADRID\nEstimada señora:", "ES", ["C/ Guzmán el Bueno, 139", "28003 Madrid"], ["C/ MAYOR 5, 3º B"]),
        ("Caisse d'allocations familiales du Rhône\n67 boulevard Vivier Merle\n69409 Lyon Cedex 03\nM. ou Mme DURAND\n12 rue des Lilas\n69003 LYON\nMadame, Monsieur,", "FR", ["67 boulevard Vivier Merle"], ["12 rue des Lilas"]),
        ("J.M. Overbeek Vastgoedbeheer\nKerkbuurt 3\n1121 AL Landsmeer\nMw. F. Janssen\nDorpsstraat 8\n1121 AB  LANDSMEER\nBeste mevrouw Janssen,", "NL", ["Kerkbuurt 3", "1121 AL Landsmeer"], ["Dorpsstraat 8"]),
    ])
    func setFourShapes(text: String, country: String, kept: [String], masked: [String]) {
        let redacted = RedactionEngine.redact(text, countryHint: country).redactedText
        for value in kept { #expect(redacted.contains(value), "kept \(value):\n\(redacted)") }
        for value in masked { #expect(!redacted.contains(value), "masked \(value):\n\(redacted)") }
    }
}
