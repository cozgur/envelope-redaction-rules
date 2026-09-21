import Foundation

/// Finds pattern matches as `String` ranges.
///
/// `NSRegularExpression` is compiled once per pattern and cached, because the
/// engine runs a few dozen patterns over every letter and compiling them per
/// call dominated the cost.
public enum RegexScanner {
    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private var storage: [String: NSRegularExpression] = [:]
        private let lock = NSLock()

        func expression(for pattern: String) -> NSRegularExpression? {
            lock.lock()
            defer { lock.unlock() }
            if let cached = storage[pattern] { return cached }
            guard let created = try? NSRegularExpression(pattern: pattern) else { return nil }
            storage[pattern] = created
            return created
        }
    }

    /// Ranges matching `pattern`. An invalid pattern yields nothing rather
    /// than trapping: a broken rule must not take the whole pipeline down,
    /// and its fixtures will fail loudly instead.
    static func ranges(of pattern: String, in text: String) -> [Range<String.Index>] {
        guard let expression = cache.expression(for: pattern) else { return [] }
        let full = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: full).compactMap {
            Range($0.range, in: text)
        }
    }

    /// Ranges of a capture group, for patterns that need context around the
    /// value they claim.
    static func ranges(
        of pattern: String,
        captureGroup group: Int,
        in text: String
    ) -> [Range<String.Index>] {
        guard let expression = cache.expression(for: pattern) else { return [] }
        let full = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: full).compactMap {
            guard group < $0.numberOfRanges else { return nil }
            return Range($0.range(at: group), in: text)
        }
    }
}
