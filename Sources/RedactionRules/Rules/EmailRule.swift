import Foundation

/// Finds email addresses.
public struct EmailRule: RedactionRule {
    public let kind = PIIKind.email

    public init() {}

    private static let pattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#

    public func matches(in text: String) -> [Range<String.Index>] {
        RegexScanner.ranges(of: Self.pattern, in: text)
    }
}
