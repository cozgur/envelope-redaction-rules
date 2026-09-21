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
