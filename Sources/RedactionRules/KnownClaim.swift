import Foundation

/// A claim made outside the rules, handed to `RedactionEngine.redact(_:countryHint:known:)`.
///
/// Redaction v2 (plan §1): the app's address window (L2, from the page's
/// geometry) and the reader's own details (L1, from the profile on the
/// device). The engine does not find these; it merges them with what its
/// rules find, window first.
public struct KnownClaim: Sendable {
    public enum Source: Sendable, Hashable {
        /// The recipient's address window on page 1. One claim, one
        /// `[ADDRESS_n]`, however many lines; wins every overlap.
        case window
        /// A match of the reader's own details. Each range is its own claim
        /// of `kind`; outside the window it wins over the rules.
        case profile
    }

    public var kind: PIIKind
    /// For a window: its lines in reading order, which may not be text order.
    public var ranges: [Range<String.Index>]
    public var source: Source

    public init(kind: PIIKind, ranges: [Range<String.Index>], source: Source) {
        self.kind = kind
        self.ranges = ranges
        self.source = source
    }
}
