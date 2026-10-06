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
    /// A profile name matched in a form only a person's name takes: with
    /// initials or a given name, or after an honorific. Such a claim is not
    /// held back by the letterhead guard, which exists for the sender's
    /// details: when OCR misses the sender's block, the recipient's block is
    /// the first one, and the guard would otherwise keep the reader's own
    /// name in the clear. Addresses and a surname alone are still held back.
    public var strongContext: Bool

    public init(kind: PIIKind, ranges: [Range<String.Index>], source: Source, strongContext: Bool = false) {
        self.kind = kind
        self.ranges = ranges
        self.source = source
        self.strongContext = strongContext
    }
}
