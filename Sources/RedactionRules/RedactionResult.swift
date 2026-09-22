import Foundation

/// What the redaction engine produced for one letter.
public struct RedactionResult: Hashable, Sendable {
    /// The text with every detected value replaced by a typed placeholder.
    /// The only form of a letter permitted to leave the device (H1).
    public var redactedText: String

    /// Placeholder to original value, for example `"[IBAN_1]"` to the real
    /// IBAN. **Device only** -- it is what makes redaction reversible for the
    /// reply header and for showing the user their own reference number.
    public var map: [String: String]

    /// How many distinct values were masked, by kind. Drives the inbox's
    /// "3 IDs, 1 IBAN, 2 references masked" summary.
    public var counts: [PIIKind: Int]

    /// Every replacement the engine made, in the order they appear, each
    /// carrying where it stood before and where it stands now.
    ///
    /// The map answers "what does `[IBAN_1]` stand for"; this answers "what
    /// stands at character 412", which is the question an audit asks. A value
    /// can be masked correctly in one place and wrongly in another, and only
    /// position distinguishes the two.
    public var spans: [MaskedSpan]

    /// One replacement: which placeholder took which text, and where.
    ///
    /// Ranges are character offsets, not `String.Index`, so a span survives
    /// being written to a file and read back in a test or a receipt.
    public struct MaskedSpan: Hashable, Sendable {
        /// For example `[ID_NUMBER_2]`.
        public var placeholder: String
        /// What the engine decided this value is. A wrong kind is a masked
        /// value all the same, but the reply header resolves placeholders by
        /// kind, so it produces the wrong letter.
        public var kind: PIIKind
        /// Character offsets into the text that was redacted.
        public var originalRange: Range<Int>
        /// Character offsets into `redactedText`.
        public var redactedRange: Range<Int>

        public init(
            placeholder: String,
            kind: PIIKind,
            originalRange: Range<Int>,
            redactedRange: Range<Int>
        ) {
            self.placeholder = placeholder
            self.kind = kind
            self.originalRange = originalRange
            self.redactedRange = redactedRange
        }
    }

    public init(
        redactedText: String,
        map: [String: String],
        counts: [PIIKind: Int] = [:],
        spans: [MaskedSpan] = []
    ) {
        self.redactedText = redactedText
        self.map = map
        self.counts = counts
        self.spans = spans
    }

    /// The span covering `offset` in the original text, if anything was
    /// masked there.
    public func span(coveringOriginalOffset offset: Int) -> MaskedSpan? {
        spans.first { $0.originalRange.contains(offset) }
    }
}
