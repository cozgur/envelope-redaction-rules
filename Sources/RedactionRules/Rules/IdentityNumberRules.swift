import Foundation

/// Finds identity numbers of one national format.
public struct NationalIDRule: RedactionRule {
    public let kind = PIIKind.idNumber
    public let format: NationalIDFormat

    public init(format: NationalIDFormat) {
        self.format = format
    }

    public func matches(in text: String) -> [Range<String.Index>] {
        RegexScanner.ranges(of: format.pattern, in: text).filter {
            format.isValid(String(text[$0]))
        }
    }
}
import Foundation

/// Masks any run of eight to twelve digits sitting near a word that
/// introduces an identity number, whether or not it validates.
///
/// The deliberate last resort. Country ID formats change, and one this engine
/// does not know would otherwise pass straight through to the proxy. Near an
/// identity keyword, an unrecognised digit run is far more likely to be an
/// identity number than anything the explanation needs, so it is masked.
/// Everywhere else the validated rules decide, which is what keeps invoice
/// totals and deadlines intact.
public struct DigitRunFallbackRule: RedactionRule {
    public let kind = PIIKind.idNumber

    public init() {}

    /// Words that introduce an identity number, across the launch countries.
    private static let keywords = [
        "bsn", "burgerservicenummer", "sofinummer",
        "steuer", "steuer-id", "steueridentifikationsnummer", "identifikationsnummer",
        "nir", "sécurité sociale", "securite sociale", "numéro de sécurité",
        "dni", "nie", "nif", "documento de identidad",
        "pesel", "numer pesel",
        "tc kimlik", "tckn", "kimlik no", "t.c. kimlik",
        "ssn", "social security",
        "nino", "national insurance",
        "id number", "identity number", "identification number",
    ]

    /// A keyword, then within thirty characters a standalone run of 8-12
    /// digits.
    private static var pattern: String {
        return "(?i)" + KeywordPattern.alternation(keywords)
            + #"[^\n]{0,30}?\b(\d{8,12})\b"#
    }

    public func matches(in text: String) -> [Range<String.Index>] {
        RegexScanner.ranges(of: Self.pattern, captureGroup: 1, in: text)
    }
}
