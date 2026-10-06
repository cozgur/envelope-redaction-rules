import Foundation

/// The reader's own details, as they would enter them (redaction v2, L1).
///
/// On the device only: the app keeps it in the Keychain and hands it to the
/// engine for each letter. Nothing here is sent, logged or stored by the
/// package. No identity number and no IBAN -- their patterns already find
/// them, and asking for them would put the most sensitive values into a form
/// for no gain.
public struct RedactionProfile: Sendable, Hashable, Codable {
    /// One person: the reader, or someone in their household.
    public struct Person: Sendable, Hashable, Codable {
        /// Given name(s), "Ayşe" or "Ayşe Nur". Optional: initials are
        /// derived from it when present, and any initials match otherwise.
        public var givenNames: String?
        /// Surname(s) with any particles: "Yılmaz", "van der Meulen",
        /// "Yılmaz-de Vries".
        public var surname: String

        public init(givenNames: String? = nil, surname: String) {
            self.givenNames = givenNames
            self.surname = surname
        }
    }

    /// A span the reader chose to always hide ("Always hide this" after
    /// "Mask this"): matched wherever its words appear, as the kind it was
    /// saved with.
    public struct Alias: Sendable, Hashable, Codable {
        public var text: String
        public var kind: PIIKind

        public init(text: String, kind: PIIKind) {
            self.text = text
            self.kind = kind
        }
    }

    public var person: Person
    /// Up to five people the reader also wants hidden; names only.
    public var household: [Person]
    /// The street name without the number: "Hoofdstraat".
    public var street: String?
    /// The house number with any suffix as the reader writes it: "12-II".
    public var houseNumber: String?
    public var postcode: String?
    /// Matched only on the postcode's line, never alone.
    public var city: String?
    /// The reader's saved aliases.
    public var aliases: [Alias]

    public init(
        person: Person,
        household: [Person] = [],
        street: String? = nil,
        houseNumber: String? = nil,
        postcode: String? = nil,
        city: String? = nil,
        aliases: [Alias] = []
    ) {
        self.person = person
        self.household = household
        self.street = street
        self.houseNumber = houseNumber
        self.postcode = postcode
        self.city = city
        self.aliases = aliases
    }

    enum CodingKeys: String, CodingKey { case person, household, street, houseNumber, postcode, city, aliases }

    /// Every field but the person may be absent: a profile saved before
    /// aliases existed, or a test fixture, decodes with none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        person = try container.decode(Person.self, forKey: .person)
        household = try container.decodeIfPresent([Person].self, forKey: .household) ?? []
        street = try container.decodeIfPresent(String.self, forKey: .street)
        houseNumber = try container.decodeIfPresent(String.self, forKey: .houseNumber)
        postcode = try container.decodeIfPresent(String.self, forKey: .postcode)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        aliases = try container.decodeIfPresent([Alias].self, forKey: .aliases) ?? []
    }
}
