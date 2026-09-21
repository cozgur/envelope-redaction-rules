import Foundation

/// How one language opens a letter.
///
/// A value per language rather than one regex with every honorific in it, so
/// adding a language is adding a file in `Salutations/` -- the contribution
/// shape this package is published for.
public struct SalutationTemplate: Sendable {
    /// BCP 47 primary language subtag.
    public let language: String
    /// Matches a salutation that names someone, capturing the name in group 1.
    ///
    /// Must not match a generic opening. `Geachte heer/mevrouw,` has to fall
    /// through: masking "mevrouw" as a name would be a false positive on a
    /// letter that never named anyone.
    ///
    /// Every pattern closes on a comma or colon, which is what separates a
    /// salutation from a recipient line. Turkish makes the point: the address
    /// block opens `Sayın A. Yilmaz` and the salutation reads `Sayın Yilmaz,`
    /// -- identical but for the punctuation. Without it the address line is
    /// read as the salutation, the header boundary moves above the recipient
    /// block, and the block is never masked.
    public let personalPattern: String
    /// Matches an opening that names nobody. Used to find where the letter's
    /// body begins even when there is no name to take.
    public let genericPattern: String
    /// Words that occupy a name's position without being one.
    ///
    /// Turkish needs this and the others largely do not: `Sayın X` has no
    /// honorific between the opener and the name, so `Sayın İlgili` ("Dear
    /// concerned party") looks exactly like a person.
    public let nonNameTerms: [String]

    public init(
        language: String,
        personalPattern: String,
        genericPattern: String,
        nonNameTerms: [String] = []
    ) {
        self.language = language
        self.personalPattern = personalPattern
        self.genericPattern = genericPattern
        self.nonNameTerms = nonNameTerms
    }
}

extension SalutationTemplate {
    /// Every language the package can read a salutation in.
    public static let all: [SalutationTemplate] = [
        .dutch, .german, .french, .spanish, .polish, .turkish, .english,
    ]

    /// The name this salutation line introduces, or nil when it names nobody.
    ///
    /// Returns the range within `line`, so the engine can mask exactly the
    /// name and leave the honorific readable -- an explanation that says
    /// "addressed to [NAME_1]" is clearer than one addressed to nobody.
    func name(in line: String) -> Range<String.Index>? {
        guard RegexScanner.ranges(of: genericPattern, in: line).isEmpty else { return nil }
        guard let captured = RegexScanner.ranges(
            of: personalPattern,
            captureGroup: 1,
            in: line
        ).first else { return nil }

        let trimmed = SalutationTemplate.trim(captured, in: line)
        let value = String(line[trimmed])
        guard SalutationTemplate.looksLikeAName(value) else { return nil }
        guard !nonNameTerms.contains(where: {
            value.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { return nil }

        return trimmed
    }

    /// Drops trailing punctuation and whitespace the capture swept up.
    private static func trim(_ range: Range<String.Index>, in line: String) -> Range<String.Index> {
        var end = range.upperBound
        while end > range.lowerBound {
            let previous = line.index(before: end)
            guard line[previous].isWhitespace || ":;.!".contains(line[previous]) else { break }
            end = previous
        }
        return range.lowerBound..<end
    }

    /// A conservative shape check. A name starts with a capital, is at most
    /// four words, and carries no digits.
    private static func looksLikeAName(_ value: String) -> Bool {
        guard let first = value.first, first.isUppercase else { return false }
        guard !value.contains(where: \.isNumber) else { return false }
        let words = value.split(separator: " ")
        return (1...4).contains(words.count)
    }
}
