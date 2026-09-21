import Foundation

/// Text the engine must never mask.
///
/// Deadlines and amounts are the product. A letter whose dates and totals have
/// been replaced by placeholders cannot be explained at all, which is a worse
/// failure than the leak over-redaction was meant to prevent. These spans are
/// computed first and every rule's claim is checked against them.
public enum ProtectedSpans {
    /// Month names across the seven UI languages, so "3 november 2025" is
    /// recognised as a date rather than read as a number beside a word.
    private static let monthNames = [
        // English
        "january", "february", "march", "april", "may", "june", "july",
        "august", "september", "october", "november", "december",
        // Dutch
        "januari", "februari", "maart", "mei", "juni", "juli", "augustus",
        "oktober",
        // German
        "januar", "februar", "märz", "maerz", "juni", "juli", "dezember",
        // French
        "janvier", "février", "fevrier", "mars", "avril", "mai", "juin",
        "juillet", "août", "aout", "septembre", "octobre", "novembre",
        "décembre", "decembre",
        // Spanish
        "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
        "agosto", "septiembre", "octubre", "noviembre", "diciembre",
        // Polish
        "stycznia", "lutego", "marca", "kwietnia", "maja", "czerwca",
        "lipca", "sierpnia", "września", "wrzesnia", "października",
        "pazdziernika", "listopada", "grudnia",
        // Turkish
        "ocak", "şubat", "subat", "mart", "nisan", "mayıs", "mayis",
        "haziran", "temmuz", "ağustos", "agustos", "eylül", "eylul",
        "ekim", "kasım", "kasim", "aralık", "aralik",
    ]

    private static var patterns: [String] {
        let months = monthNames.joined(separator: "|")
        return [
            // ISO and separator dates: 2025-11-03, 03-11-2025, 3.11.2025
            #"\b\d{4}[-/.]\d{1,2}[-/.]\d{1,2}\b"#,
            #"\b\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b"#,
            // Written dates in either order.
            #"(?i)\b\d{1,2}\.?\s*(?:"# + months + #")\s*\d{4}\b"#,
            #"(?i)\b(?:"# + months + #")\s+\d{1,2},?\s*\d{4}\b"#,
            // Money, with or without a symbol on either side.
            #"(?i)(?:EUR|USD|GBP|TRY|PLN|CHF|€|\$|£|₺|zł)\s?\d[\d.,]*"#,
            #"(?i)\d[\d.,]*\s?(?:EUR|USD|GBP|TRY|PLN|CHF|€|\$|£|₺|zł)\b"#,
            // Decimal amounts written without a symbol: 1.240,00 / 1,240.00
            #"(?<![\w/-])\d{1,3}(?:[.,]\d{3})*[.,]\d{2}(?![\w/-])"#,
            // Percentages.
            #"\b\d+(?:[.,]\d+)?\s?%"#,
        ]
    }

    /// Postcodes standing on their own.
    ///
    /// A postcode is not identifying by itself, so nothing may mistake one for
    /// an identifier -- but an address block containing one is masked whole,
    /// which is why these are exempt for `.address`.
    ///
    /// The lookarounds matter more than the patterns. `\b` alone treats the
    /// "55120" inside a reference like KYC-2026-55120 as a postcode, which
    /// protects it, and the whole reference then survives redaction. A
    /// postcode is a token, not a fragment of one, so neither side may be a
    /// word character, a hyphen or a slash.
    ///
    /// There is no bare five-digit rule for DE/ES/FR/TR/US: those postcodes
    /// are five digits and nothing else, which is also the shape of the last
    /// group of a German phone number and of a chunk of many references.
    /// Nothing masks a lone five-digit run anyway.
    private static let postcodePatterns = [
        #"(?<![\w./-])\d{4}\s?[A-Z]{2}(?![\w./-])"#,                        // NL
        #"(?<![\w./-])\d{2}-\d{3}(?![\w./-])"#,                             // PL
        #"(?i)(?<![\w./-])[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2}(?![\w./-])"#,  // UK
    ]


    /// A span, and which rules it stops.
    public struct Span: Sendable {
        public let range: Range<String.Index>
        /// Kinds this span does *not* stop.
        ///
        /// A date or an amount must survive every rule. A postcode is
        /// different: it must survive being mistaken for an identifier, but
        /// not being masked as part of a recipient address block, which is
        /// exactly where a postcode belongs. Without this distinction the
        /// block claim is vetoed by the postcode inside it, and the
        /// recipient's name survives with it.
        public let exemptKinds: Set<PIIKind>

        func vetoes(_ kind: PIIKind) -> Bool {
            !exemptKinds.contains(kind)
        }
    }

    /// Every span in `text` that must survive redaction untouched.
    public static func compute(in text: String) -> [Span] {
        patterns.flatMap { RegexScanner.ranges(of: $0, in: text) }
            .map { Span(range: $0, exemptKinds: []) }
        + postcodePatterns.flatMap { RegexScanner.ranges(of: $0, in: text) }
            .map { Span(range: $0, exemptKinds: [.address]) }
    }
}
