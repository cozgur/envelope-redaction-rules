import Foundation
import Testing

@testable import RedactionRules

/// The guard's profile values keep L1's precision guards (owner, 6 Oct 2026).
@Suite("Profile guard")
struct ProfileGuardTests {

    @Test("A reader named Bakker: \"de bakker op de hoek\" is no guard hit; \"A. Bakker\" is")
    func bakker() {
        let profile = RedactionProfile(person: .init(givenNames: "Anne", surname: "Bakker"))
        #expect(ProfileGuard.hits(in: "U kunt brood halen bij de bakker op de hoek.", profile: profile).isEmpty)
        #expect(ProfileGuard.hits(in: "Bakker is een beroep.", profile: profile).isEmpty)
        #expect(!ProfileGuard.hits(in: "De aanvraag van A. Bakker is ontvangen.", profile: profile).isEmpty)
        #expect(!ProfileGuard.hits(in: "Anne Bakker woont hier.", profile: profile).isEmpty)
    }

    @Test("A reader on Kerkstraat 5: a sender at Kerkstraat 120 (or 51) is no guard hit")
    func kerkstraat() {
        let profile = RedactionProfile(person: .init(surname: "Jansen"), street: "Kerkstraat", houseNumber: "5", postcode: "2011 XA")
        #expect(ProfileGuard.hits(in: "Gemeente Haarlem, Kerkstraat 120, 2011 KP Haarlem", profile: profile).isEmpty)
        #expect(ProfileGuard.hits(in: "ons kantoor aan de Kerkstraat 51", profile: profile).isEmpty)
        #expect(ProfileGuard.hits(in: "Wij werken in de Kerkstraat.", profile: profile).isEmpty)
        #expect(ProfileGuard.hits(in: "Uw adres Kerkstraat 5 is bekend.", profile: profile) == ["kerkstraat 5"])
    }

    @Test("Suffix forms, postcode spacing, aliases, case and diacritics")
    func forms() {
        let profile = RedactionProfile(
            person: .init(givenNames: "Ayşe", surname: "Yılmaz"),
            street: "Hoofdstraat", houseNumber: "12-II", postcode: "1011 AB",
            aliases: [.init(text: "Villa Zonnehoek", kind: .address)]
        )
        for body in ["HOOFDSTRAAT 12 II", "Hoofdstraat 12II", "postcode 1011AB", "1011 ab", "yilmaz", "Ayse Yilmaz", "in villa  zonnehoek"] {
            #expect(!ProfileGuard.hits(in: body, profile: profile).isEmpty, "\(body)")
        }
    }

    @Test("A short surname only with initials or a given name")
    func shortSurname() {
        let profile = RedactionProfile(person: .init(givenNames: "Wei", surname: "Li"))
        #expect(ProfileGuard.hits(in: "Li-Ning Sport en bijlage li", profile: profile).isEmpty)
        #expect(!ProfileGuard.hits(in: "Mw. W. Li", profile: profile).isEmpty)
    }

    @Test("Aliases are matched by L1 too, as the kind they were saved with")
    func aliasInL1() {
        let profile = RedactionProfile(person: .init(surname: "Yilmaz"), aliases: [.init(text: "Villa Zonnehoek", kind: .address)])
        let result = RedactionEngine.redact("Post voor de bewoners van Villa  Zonnehoek, Amsterdam.", countryHint: "NL", profile: profile)
        #expect(result.map["[ADDRESS_1]"] == "Villa  Zonnehoek")
    }
}
