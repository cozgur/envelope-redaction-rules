import Foundation

/// Finds phone numbers and postal addresses with `NSDataDetector`.
///
/// Apple's detector is used rather than patterns of our own because both
/// formats vary by country far more than an identity number does, and the
/// system detector already carries that knowledge.
public struct DataDetectorRule: RedactionRule {
    public let kind: PIIKind
    private let checkingType: NSTextCheckingResult.CheckingType

    public static var phone: DataDetectorRule {
        DataDetectorRule(kind: .phone, checkingType: .phoneNumber)
    }

    public static var address: DataDetectorRule {
        DataDetectorRule(kind: .address, checkingType: .address)
    }

    private init(kind: PIIKind, checkingType: NSTextCheckingResult.CheckingType) {
        self.kind = kind
        self.checkingType = checkingType
    }

    public func matches(in text: String) -> [Range<String.Index>] {
        guard let detector = try? NSDataDetector(types: checkingType.rawValue) else { return [] }
        let full = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: full).compactMap {
            Range($0.range, in: text)
        }
    }
}

/// Masks the recipient's address block whole, name line included.
///
/// This is how a name is removed without ever being recognised as one. The
/// block sits in a known place -- after the letterhead, before the date and
/// reference lines -- and everything in it belongs to the person the letter
/// was sent to: their name, their street, their postcode.
///
/// `NSDataDetector` alone cannot do this. It finds no address at all in Dutch
/// or Polish blocks, and where it does hit it returns the street and postcode
/// without the name line above them. So a hit is treated as evidence, not as
/// the answer: the block around it is what gets masked, and a block with no
/// hit is still masked when its shape says what it is.
public struct RecipientBlockRule: RedactionRule {
    public let kind = PIIKind.address

    public init() {}

    /// Lines that mark a block as an address even when the detector is silent.
    private static let postcodeShapes = [
        #"(?<![\w./-])\d{4}\s?[A-Z]{2}(?![\w./-])"#,                        // NL
        #"(?<![\w./-])\d{2}-\d{3}(?![\w./-])"#,                             // PL
        #"(?<![\w./-])\d{5}(?:-\d{4})?(?![\w./-])"#,                        // DE/ES/FR/TR/US
        #"(?i)(?<![\w./-])[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2}(?![\w./-])"#,  // UK
    ]

    public func matches(in text: String) -> [Range<String.Index>] {
        let structure = LetterStructure(text)
        let detector = DataDetectorRule.address
        let detected = detector.matches(in: text)

        return structure.recipientCandidates
            .filter { block in
                let range = block.range
                if detected.contains(where: { $0.overlaps(range) }) { return true }
                return Self.looksLikeAnAddressBlock(block)
            }
            .map(\.range)
    }

    /// Two to six lines, at least one of which carries a postcode.
    ///
    /// Deliberately not "contains a number": a reference block would pass
    /// that, and masking the reference block as an address would take the
    /// case number the reply header needs.
    static func looksLikeAnAddressBlock(_ block: LetterStructure.Block) -> Bool {
        guard (2...6).contains(block.lines.count) else { return false }
        return block.lines.contains { line in
            postcodeShapes.contains { !RegexScanner.ranges(of: $0, in: line.text).isEmpty }
        }
    }
}
