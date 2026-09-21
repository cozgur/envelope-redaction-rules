import Foundation

/// One country's national identity number: how to spot a candidate, and how to
/// tell a real one from a digit run that merely looks like one.
///
/// A value rather than an enum case, so adding a country is adding a file in
/// `Countries/` rather than editing a switch that every other country shares.
/// That matters because this package is public and new formats are expected to
/// arrive as contributions.
public struct NationalIDFormat: Sendable {
    /// ISO 3166-1 alpha-2, used to order the rules against a country hint.
    public let country: String
    /// What the number is called where it is issued, for documentation and
    /// failure messages.
    public let name: String
    /// Loose enough to find candidates; `validate` is what makes it precise.
    public let pattern: String
    /// Whether a candidate really is a number of this format.
    public let validate: @Sendable (String) -> Bool

    public init(
        country: String,
        name: String,
        pattern: String,
        validate: @escaping @Sendable (String) -> Bool
    ) {
        self.country = country
        self.name = name
        self.pattern = pattern
        self.validate = validate
    }

    public func isValid(_ candidate: String) -> Bool {
        validate(candidate)
    }

    /// Digits only, with the separators a letter might print.
    static func digits(of candidate: String) -> [Int] {
        compacted(candidate).compactMap(\.wholeNumberValue)
    }

    static func compacted(_ candidate: String) -> String {
        candidate
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}

extension NationalIDFormat {
    /// Every format the package knows, in no particular order. The engine
    /// orders them against the country hint.
    public static let all: [NationalIDFormat] = [
        .netherlands, .germany, .france, .spain,
        .poland, .turkey, .unitedStates, .unitedKingdom,
    ]

    /// The format for a country, if there is one.
    public static func format(for country: String) -> NationalIDFormat? {
        all.first { $0.country == country.uppercased() }
    }
}
