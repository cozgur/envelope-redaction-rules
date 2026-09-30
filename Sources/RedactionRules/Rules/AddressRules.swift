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
            + Self.postcodeAnchoredBlocks(in: structure, text: text)
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
    static func postcodeAnchoredBlocks(in structure: LetterStructure, text: String) -> [Range<String.Index>] {
        let limit = min(structure.headerBoundary ?? addressWindow, addressWindow)
        let window = structure.lines.prefix(while: { $0.index < limit })
        let lines: [Cell?] = window.map { Cell(text: $0.text, range: $0.range) }

        var found: [Range<String.Index>] = []
        let (interleaved, paired) = interleavedColumns(lines)
        found += interleaved
        found += walk(lines, firstLineIsLetterhead: true, skipping: paired)
        // A window printed on the same rows as the letterhead: the right-hand
        // column, read on its own. Its first line is the recipient's, not the
        // sender's -- the letterhead is the other column.
        found += walk(window.map { rightColumn($0, in: text) }, firstLineIsLetterhead: false, skipping: [])
        return found
    }

    /// One line of a column: all of a line, or the part of it right of a wide
    /// gap.
    struct Cell {
        let text: String
        let range: Range<String.Index>

        var isBlank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The text right of the last run of three or more spaces, when the line
    /// has text on both sides of one. Its range is in the letter's own text,
    /// counted from where the line starts.
    private static func rightColumn(_ line: LetterStructure.Line, in text: String) -> Cell? {
        guard let gap = RegexScanner.firstMatch(of: #"^.*\S {3,}(\S.*)$"#, in: line.text),
              let right = gap.prefix, let found = line.text.range(of: right, options: .backwards)
        else { return nil }
        let offset = line.text.distance(from: line.text.startIndex, to: found.lowerBound)
        guard let start = text.index(line.range.lowerBound, offsetBy: offset, limitedBy: line.range.upperBound)
        else { return nil }
        return Cell(text: right, range: start..<line.range.upperBound)
    }

    private static func isPostcodeLine(_ cell: Cell?) -> RegexScanner.Match? {
        guard let cell else { return nil }
        return RegexScanner.firstMatch(of: postcodeCityLine, in: cell.text)
    }

    /// A line above a postcode that cannot be part of the same address.
    private static func endsAnAddress(_ cell: Cell?) -> Bool {
        guard let cell else { return true }
        return cell.isBlank || LetterStructure.isFieldLine(cell.text) || isOfficeMailbox(cell.text)
            || LetterStructure.isDateLine(cell.text) || isPostcodeLine(cell) != nil
    }

    /// The postcode walk, over one column.
    private static func walk(_ column: [Cell?], firstLineIsLetterhead: Bool, skipping: Set<Int>) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for (position, cell) in column.enumerated() where position >= 1 && !skipping.contains(position) {
            guard let cell, let match = isPostcodeLine(cell), !isOfficeMailbox(cell.text) else { continue }

            if let prefix = match.prefix, !prefix.isEmpty {
                // The whole address on one line. It needs a street -- a word
                // and a number -- before the postcode, or it is a sentence.
                guard prefix.contains(where: \.isNumber) else { continue }
                found.append(cell.range)
                continue
            }

            var top = position
            var reachedLetterhead = false
            for candidate in stride(from: position - 1, through: max(0, position - 3), by: -1) {
                if endsAnAddress(column[candidate]) { break }
                if candidate == 0 && firstLineIsLetterhead {
                    reachedLetterhead = true
                    break
                }
                top = candidate
            }
            // Nothing above it, or the sender's letterhead: not a recipient.
            guard top < position, !reachedLetterhead else { continue }
            // The line directly above the postcode is the street, and a
            // street has a house number.
            guard column[position - 1]?.text.contains(where: \.isNumber) == true else { continue }
            if firstLineIsLetterhead, let first = column[top], let last = column[position] {
                found.append(first.range.lowerBound..<last.range.upperBound)
            } else {
                found += (top...position).compactMap { column[$0]?.range }
            }
        }
        return found
    }

    /// Two columns that OCR has read line by line in turn: sender name,
    /// recipient name, sender mailbox, recipient street, sender postcode,
    /// recipient postcode.
    ///
    /// The tell is two postcode lines one above the other. Each is the foot
    /// of a column that runs up every other line; the column holding an
    /// office mailbox or the letter's first line is the sender's and is left
    /// alone, and the other is masked line by line. When neither or both
    /// look like the sender, nothing is claimed here and the plain walk has
    /// its turn.
    private static func interleavedColumns(_ lines: [Cell?]) -> ([Range<String.Index>], Set<Int>) {
        var found: [Range<String.Index>] = []
        var paired: Set<Int> = []
        for position in lines.indices.dropLast() {
            guard let upper = isPostcodeLine(lines[position]), upper.prefix == nil,
                  let lower = isPostcodeLine(lines[position + 1]), lower.prefix == nil
            else { continue }
            let columnA = stride(from: position, through: max(0, position - 4), by: -2).map { $0 }
            let columnB = stride(from: position + 1, through: max(0, position - 3), by: -2).map { $0 }
            func isSender(_ column: [Int]) -> Bool {
                column.dropFirst().contains { $0 == 0 || lines[$0].map { isOfficeMailbox($0.text) } == true }
            }
            let recipient: [Int]
            switch (isSender(columnA), isSender(columnB)) {
            case (true, false): recipient = columnB
            case (false, true): recipient = columnA
            default: continue
            }
            var masked = [recipient[0]]
            for candidate in recipient.dropFirst() {
                if endsAnAddress(lines[candidate]) { break }
                masked.append(candidate)
            }
            guard masked.count > 1,
                  lines[masked[1]]?.text.contains(where: \.isNumber) == true
            else { continue }
            found += masked.compactMap { lines[$0]?.range }
            paired.formUnion([position, position + 1])
        }
        return (found, paired)
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
