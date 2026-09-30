import Foundation

/// Masks the name a letter's salutation addresses.
///
/// The second of the two places official mail puts a name, and the only one
/// where the name stands alone rather than inside a block. The honorific is
/// kept: *Geachte mevrouw [NAME_1],* still tells the explanation that the
/// letter is addressed to a woman, and reads as a letter rather than as a
/// redaction.
///
/// Once the name is known, the engine masks every other occurrence of it --
/// a letter that says "Mrs Yilmaz's application" later is masked there too.
/// Names of third parties elsewhere in the body are not attempted: finding
/// those needs a model, which is v1.1.
public struct SalutationNameRule: RedactionRule {
    public let kind = PIIKind.name

    public init() {}

    public func matches(in text: String) -> [Range<String.Index>] {
        let structure = LetterStructure(text)
        guard let line = structure.salutationLine else { return [] }

        for template in SalutationTemplate.all {
            guard let inLine = template.name(in: line.text) else { continue }
            // The capture is relative to the line; move it into the letter.
            let start = text.index(
                line.range.lowerBound,
                offsetBy: line.text.distance(from: line.text.startIndex, to: inLine.lowerBound)
            )
            let end = text.index(
                start,
                offsetBy: line.text.distance(from: inLine.lowerBound, to: inLine.upperBound)
            )
            return [start..<end]
        }
        return []
    }
}

/// A person named in a field line about someone other than the addressee:
/// *Inzake: mevrouw J.P. Zwart-Hendriks*, *Cliënt: de heer R. Visser*.
///
/// Guardianship firms, lawyers and insurers write about a client this way.
/// Only a name with initials is taken -- "Betreft: aanslag 2026" has none --
/// so the field's other uses are left alone.
public struct FieldLineNameRule: RedactionRule {
    public let kind = PIIKind.name

    public init() {}

    private static let pattern =
        #"(?im)^[ \t]*(?:inzake|betreft|cli[eë]nt|verzekerde|aanvrager|pati[eë]nt|namens|re)[ \t]*:[ \t]*(?:(?:de[ \t]+)?(?:heer|mevrouw|mw\.|dhr\.|mr\.|mrs\.|ms\.)[ \t]+)?("#
        + PersonName.initialsAndSurname + #")[ \t]*$"#

    public func matches(in text: String) -> [Range<String.Index>] {
        RegexScanner.ranges(of: Self.pattern, captureGroup: 1, in: text)
    }
}

/// The shape of a person's name as Dutch mail prints it: initials, then a
/// surname with its tussenvoegsels, hyphenated or double -- "J.P.
/// Zwart-Hendriks", "K.E. van Wijk-Oosterhuis", "D.C. van 't Hof".
enum PersonName {
    static let initialsAndSurname =
        #"\p{Lu}\.(?:[ ]?\p{Lu}\.)*[ \t]+(?:(?:van|de|der|den|het|ten|ter|te|el|al|'t|von|du|la|le)[ \t]+)*\p{Lu}[\p{L}'-]+(?:[ -]\p{Lu}[\p{L}'-]+)?"#

    /// The surname in a name: everything after the initials, tussenvoegsels
    /// included, with the first letter as the letter itself capitalises
    /// it mid-sentence ("van Wijk" → matched case-insensitively anyway).
    static func surname(of name: String) -> String? {
        guard let range = RegexScanner.ranges(of: #"^(?:\p{Lu}\.(?:[ ]?\p{Lu}\.)*)[ \t]+(.+)$"#, captureGroup: 1, in: name).first
        else { return nil }
        return String(name[range])
    }

    /// The name on a recipient block's first line, without the honorific
    /// and titles before it: "Mevrouw mr. S.K. Wiersma" → "S.K. Wiersma".
    static func onFirstLine(of block: String) -> String? {
        guard let first = block.split(separator: "\n", omittingEmptySubsequences: true).first else { return nil }
        let pattern = #"(?i:^\s*(?:t\.a\.v\.|attn\.?|aan:?|de heer en mevrouw|de heer|dhr\.(?:/mevr\.)?|heer|mevrouw|mevr\.|mw\.|mr\.|mrs\.|ms\.)?\s*(?:(?:mr|dr|drs|ir|ing|prof)\.\s*)*)("#
            + initialsAndSurname + #")\s*$"#
        let line = String(first)
        guard let range = RegexScanner.ranges(of: pattern, captureGroup: 1, in: line).first else { return nil }
        return String(line[range])
    }
}
