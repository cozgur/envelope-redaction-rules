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

    public init(redactedText: String, map: [String: String], counts: [PIIKind: Int] = [:]) {
        self.redactedText = redactedText
        self.map = map
        self.counts = counts
    }
}
