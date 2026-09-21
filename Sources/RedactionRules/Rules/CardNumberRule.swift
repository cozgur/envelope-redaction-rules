import Foundation

/// Finds payment card numbers, validated by Luhn.
public struct CardNumberRule: RedactionRule {
    public let kind = PIIKind.cardNumber

    public init() {}

    /// Thirteen to nineteen digits, optionally grouped in fours.
    private static let pattern = #"\b(?:\d[ -]?){12,18}\d\b"#

    public func matches(in text: String) -> [Range<String.Index>] {
        RegexScanner.ranges(of: Self.pattern, in: text).filter {
            let digits = text[$0].compactMap(\.wholeNumberValue)
            guard (13...19).contains(digits.count) else { return false }
            return Checksums.passesLuhn(digits)
        }
    }
}
