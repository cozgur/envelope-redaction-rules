import Foundation

/// Finds IBANs, validated by mod-97.
///
/// The checksum matters here as much as for identity numbers: without it the
/// pattern would swallow any capitalised token followed by digits, which
/// describes a great many reference numbers.
public struct IBANRule: RedactionRule {
    public let kind = PIIKind.iban

    public init() {}

    /// Two letters, two check digits, then up to thirty grouped characters.
    private static let pattern = #"\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{2,4}){2,8}\b"#

    public func matches(in text: String) -> [Range<String.Index>] {
        RegexScanner.ranges(of: Self.pattern, in: text).filter {
            Checksums.passesIBANMod97(String(text[$0]))
        }
    }
}
import Foundation

/// Masks an account-shaped token beside a word that introduces one, even when
/// its checksum fails.
///
/// The counterpart to ``DigitRunFallbackRule``. A mistyped or OCR-damaged
/// IBAN fails mod-97 but is still the user's bank account, and a letter that
/// names it beside the word "IBAN" leaves no doubt what it is. Away from such
/// a keyword the checksum decides, so ordinary numbers are left alone.
public struct AccountNumberFallbackRule: RedactionRule {
    public let kind = PIIKind.iban

    public init() {}

    private static let keywords = [
        "iban", "rekeningnummer", "bankrekening", "rekening",
        "kontonummer", "bankverbindung", "konto",
        "numéro de compte", "numero de compte", "compte bancaire", "rib",
        "número de cuenta", "numero de cuenta", "cuenta bancaria",
        "numer konta", "numer rachunku", "rachunek",
        "hesap numarası", "hesap numarasi", "hesap no", "banka hesabı",
        "account number", "bank account", "sort code",
    ]

    /// A keyword, then within thirty characters either an IBAN-shaped token
    /// or a long bare account number.
    private static var pattern: String {
        return "(?i)" + KeywordPattern.alternation(keywords)
            + #"[^\n]{0,30}?\b([A-Z]{2}\d{2}[A-Z0-9 ]{8,30}|\d{9,18})\b"#
    }

    public func matches(in text: String) -> [Range<String.Index>] {
        RegexScanner.ranges(of: Self.pattern, captureGroup: 1, in: text)
            .map { range in
                // The pattern may take trailing spaces with a grouped IBAN.
                var trimmed = range
                while trimmed.lowerBound < trimmed.upperBound,
                      text[text.index(before: trimmed.upperBound)].isWhitespace {
                    trimmed = trimmed.lowerBound..<text.index(before: trimmed.upperBound)
                }
                return trimmed
            }
    }
}

/// An IBAN by its shape when its checksum fails (owner, 6 Oct 2026): a known
/// country code, two check digits, and exactly that country's length --
/// letters an OCR misread for digits ("265O") included.
///
/// The country's length is what keeps this from taking a reference: an
/// "NL12 …" that is not eighteen characters long is left to the other rules.
public struct IBANShapeRule: RedactionRule {
    public let kind = PIIKind.iban

    public init() {}

    static let lengths: [String: Int] = [
        "NL": 18, "DE": 22, "BE": 16, "FR": 27, "ES": 24, "PL": 28, "TR": 26, "GB": 22, "IE": 22,
        "IT": 27, "PT": 25, "AT": 20, "CH": 21, "LU": 20, "DK": 18, "SE": 24, "NO": 15, "FI": 18,
        "CZ": 24, "SK": 24, "HU": 28, "RO": 24, "BG": 22, "GR": 27, "HR": 21, "SI": 19, "LT": 20,
        "LV": 21, "EE": 20, "CY": 28, "MT": 31, "IS": 26, "LI": 21, "MC": 27,
    ]

    private static let pattern = #"(?<![\p{L}\d])[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{1,4}){2,9}(?![\p{L}\d])"#

    public func matches(in text: String) -> [Range<String.Index>] {
        RegexScanner.ranges(of: Self.pattern, in: text).compactMap { range in
            let value = String(text[range])
            let compact = value.filter { !$0.isWhitespace }
            guard let length = Self.lengths[String(compact.prefix(2))] else { return nil }
            // Grouped values may run into the next word's digits: take the
            // country's length and no more, ending on a group boundary.
            guard compact.count >= length else { return nil }
            var taken = 0
            var end = range.lowerBound
            for index in value.indices {
                if !value[index].isWhitespace { taken += 1 }
                if taken == length { end = text.index(range.lowerBound, offsetBy: value.distance(from: value.startIndex, to: value.index(after: index))); break }
            }
            guard taken == length else { return nil }
            if end < range.upperBound, !text[end].isWhitespace { return nil }
            // Mostly digits once the usual misreads are read back.
            let bban = compact.dropFirst(4).prefix(length - 4)
            let digits = bban.filter { $0.isNumber || "OIlS".contains($0) }.count
            guard digits * 2 >= bban.count else { return nil }
            return range.lowerBound..<end
        }
    }
}
