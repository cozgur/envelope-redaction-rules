import Foundation

/// Builds the keyword alternations the anchored rules are built on.
///
/// Every keyword match is bounded by a non-letter on both sides. Without that,
/// a two-letter preposition matches inside an ordinary word: the Spanish tax
/// office's own address, "Calle de Guzmán el Bueno 139", contains "al" inside
/// "Estatal", and the phone rule then read the house number as a phone
/// number. The Turkish "Mahallesi" does the same.
///
/// Letters rather than `\b`, because `\b` treats a digit as a word character
/// and several keywords end in punctuation.
enum KeywordPattern {
    static func alternation(_ keywords: [String]) -> String {
        let escaped = keywords
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return #"(?<!\p{L})(?:"# + escaped + #")(?!\p{L})"#
    }
}
