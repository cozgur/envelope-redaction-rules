import Foundation

/// Where a letter's parts are.
///
/// Official mail is laid out the same way almost everywhere: a letterhead,
/// the recipient's address, a field block of dates and references, a subject,
/// then the salutation and the body. Knowing which is which is what lets the
/// recipient block be masked whole and the sender's letterhead be left alone,
/// without either being recognised as a name.
public struct LetterStructure: Sendable {
    /// One line and where it sits in the text.
    public struct Line: Sendable {
        public let index: Int
        public let range: Range<String.Index>
        public let text: String

        var isBlank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// A run of non-blank lines between blank ones.
    public struct Block: Sendable {
        public let index: Int
        public let lines: [Line]

        public var range: Range<String.Index> {
            lines[0].range.lowerBound..<lines[lines.count - 1].range.upperBound
        }

        public var text: String {
            lines.map(\.text).joined(separator: "\n")
        }
    }

    public let lines: [Line]
    public let blocks: [Block]
    /// The first line that belongs to the letter's machinery rather than to
    /// its address blocks: a date, a reference field, or the salutation.
    /// Everything before it is letterhead and addresses.
    public let headerBoundary: Int?
    /// The salutation line, when the letter has one.
    public let salutationLine: Line?

    public init(_ text: String) {
        var offset = text.startIndex
        var built: [Line] = []
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            let end = text.index(offset, offsetBy: raw.count, limitedBy: text.endIndex) ?? text.endIndex
            built.append(Line(index: index, range: offset..<end, text: raw))
            offset = end < text.endIndex ? text.index(after: end) : text.endIndex
        }
        lines = built

        var grouped: [Block] = []
        var current: [Line] = []
        for line in built {
            if line.isBlank {
                if !current.isEmpty {
                    grouped.append(Block(index: grouped.count, lines: current))
                    current = []
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            grouped.append(Block(index: grouped.count, lines: current))
        }
        blocks = grouped

        salutationLine = built.first { line in
            SalutationTemplate.all.contains { template in
                !RegexScanner.ranges(of: template.personalPattern, in: line.text).isEmpty
                    || !RegexScanner.ranges(of: template.genericPattern, in: line.text).isEmpty
            }
        }

        // Only a date or the salutation ends the address region. A field line
        // is deliberately not enough: a Turkish street reads
        // "Atatürk Caddesi No: 12", which is a label, a colon and a value --
        // indistinguishable from "Dosya No: ..." by shape alone. Using it
        // would put the boundary inside the recipient block and leave the
        // block unmasked.
        let firstMachineLine = built.first { LetterStructure.isDateLine($0.text) }
        headerBoundary = [firstMachineLine?.index, salutationLine?.index]
            .compactMap { $0 }
            .min()
    }

    /// The blocks that sit in the recipient's window position: after the
    /// letterhead and before the letter's machinery starts.
    ///
    /// The first block is never one. A letterhead is the sender's own address
    /// and masking it would delete the one thing the explanation most needs to
    /// know -- who wrote.
    public var recipientCandidates: [Block] {
        guard let headerBoundary else { return [] }
        return blocks.filter { block in
            block.index >= 1 && block.lines.allSatisfy { $0.index < headerBoundary }
        }
    }

    /// The sender's letterhead: the first block, when it sits above the
    /// letter's machinery.
    ///
    /// Nil when the letter opens straight into a date or a salutation, which
    /// is what a portal-generated document tends to do. Nil is the safe
    /// answer -- it excludes nothing rather than excluding the wrong thing.
    public var letterheadRange: Range<String.Index>? {
        guard let headerBoundary, let first = blocks.first else { return nil }
        guard first.lines.allSatisfy({ $0.index < headerBoundary }) else { return nil }
        return first.range
    }

    /// A line that is nothing but a date, or a labelled date.
    static func isDateLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let dateSpans = ProtectedSpans.compute(in: trimmed)
        guard dateSpans.contains(where: { $0.exemptKinds.isEmpty }) else { return false }
        // A sentence that happens to mention a date is not a date line; a
        // field line or a bare date is.
        return trimmed.count < 48 || isFieldLine(trimmed)
    }

    /// `Kenmerk: 1234.56.789` and its equivalents: a short label, a colon, a
    /// value.
    static func isFieldLine(_ text: String) -> Bool {
        !RegexScanner.ranges(of: #"(?m)^[\p{L}][^\n:]{0,38}[ \t]*:[ \t]*\S"#, in: text).isEmpty
    }
}
