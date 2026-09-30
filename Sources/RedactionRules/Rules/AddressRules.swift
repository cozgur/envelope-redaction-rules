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
        #"(?<![\w./-])[1-9]\d{3}\s?(?!SA|SD|SS)[A-Z]{2}(?![\w./-])"#,       // NL
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
            + Self.postcodeAnchoredBlocks(in: structure)
    }

    // MARK: - A block found from its postcode line

    /// A Dutch postcode, and the city after it, as a whole line -- or at the
    /// end of a line that carries the rest of the address before a comma.
    ///
    /// `1000 AA` to `9999 ZZ`: no leading zero, and never SA, SD or SS, which
    /// PostNL does not issue.
    private static let postcodeCityLine =
        #"^\s*(?:(\S.*?),\s*)?[1-9][0-9]{3} ?(?!SA|SD|SS)[A-Z]{2}\s+['\p{L}][\p{L} .'-]*\s*$"#

    /// A mailing address that belongs to an office, never to a person.
    private static let officeMailbox = #"(?i)(?<!\p{L})(?:postbus|antwoordnummer|postfach|bo[iî]te postale)(?!\p{L})"#

    /// How far down page one a recipient block can sit.
    private static let addressWindow = 20

    /// Recipient blocks found from the postcode up rather than from blank
    /// lines.
    ///
    /// OCR routinely returns the top of a letter with no blank lines at all,
    /// and then there are no blocks to choose from: letterhead, recipient and
    /// reference lines are one run. The postcode-and-city line is the anchor
    /// instead. Above it sit one to three lines of name and street, and the
    /// walk up stops at anything that is not part of an address -- a blank
    /// line, a field line, an office mailbox, another postcode line. A walk
    /// that reaches the letter's first line has found the sender's own
    /// letterhead, which is never masked.
    ///
    /// A postcode line with the rest of the address before a comma
    /// (`A. Yilmaz, Voorbeeldstraat 00, 1011 AB Amsterdam`) is the whole
    /// block on one line.
    static func postcodeAnchoredBlocks(in structure: LetterStructure) -> [Range<String.Index>] {
        let limit = min(structure.headerBoundary ?? addressWindow, addressWindow)
        let window = structure.lines.prefix(while: { $0.index < limit })
        var found: [Range<String.Index>] = []

        for line in window where line.index >= 1 {
            guard let match = RegexScanner.firstMatch(of: postcodeCityLine, in: line.text) else { continue }
            if isOfficeMailbox(line.text) { continue }

            if let prefix = match.prefix, !prefix.isEmpty {
                // The whole address on one line. It needs a street -- a word
                // and a number -- before the postcode, or it is a sentence.
                guard prefix.contains(where: \.isNumber) else { continue }
                found.append(line.range)
                continue
            }

            var top = line.index
            var reachedLetterhead = false
            for candidate in stride(from: line.index - 1, through: max(0, line.index - 3), by: -1) {
                let above = structure.lines[candidate]
                if above.isBlank || LetterStructure.isFieldLine(above.text) || isOfficeMailbox(above.text)
                    || LetterStructure.isDateLine(above.text)
                    || RegexScanner.firstMatch(of: postcodeCityLine, in: above.text) != nil {
                    break
                }
                if candidate == 0 {
                    reachedLetterhead = true
                    break
                }
                top = candidate
            }
            // Nothing above it, or the sender's letterhead: not a recipient.
            guard top < line.index, !reachedLetterhead else { continue }
            // The line directly above the postcode is the street, and a
            // street has a house number.
            guard structure.lines[line.index - 1].text.contains(where: \.isNumber) else { continue }
            found.append(structure.lines[top].range.lowerBound..<line.range.upperBound)
        }
        return found
    }

    private static func isOfficeMailbox(_ text: String) -> Bool {
        !RegexScanner.ranges(of: officeMailbox, in: text).isEmpty
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
