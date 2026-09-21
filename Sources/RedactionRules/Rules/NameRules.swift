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
