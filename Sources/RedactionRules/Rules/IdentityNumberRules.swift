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

/// The value after an identity label, to the end of its field (owner, 6 Oct
/// 2026): "Rentenversicherungsnummer 49 110407 S 029", "paspoort (nummer
/// NW5K18P34)", "N° de sécurité sociale : 1 85 05 78 006 084 36".
///
/// The label is the signal, so no format has to be known. The value is
/// capital letters and digits in groups of one space, at least four digits;
/// it ends at the first word in lower case, a bracket, a comma or the line's
/// end, so the sentence around it stays.
public struct LabelledIdentityRule: RedactionRule {
    public let kind = PIIKind.idNumber

    public init() {}

    static let labels = [
        "paspoortnummer", "paspoort", "documentnummer", "identiteitskaart", "identiteitsbewijs",
        "id-kaart", "v-nummer", "verblijfsdocument", "verblijfsvergunning", "bsn", "burgerservicenummer",
        "versichertennummer", "krankenversichertennummer", "rentenversicherungsnummer",
        "sozialversicherungsnummer", "steuer-id", "steuer-identifikationsnummer",
        "steueridentifikationsnummer", "identifikationsnummer", "personalausweisnummer",
        "reisepassnummer", "ausweisnummer", "pesel", "numer dowodu", "numer paszportu", "nie", "dni",
        "nif", "número de pasaporte", "numero de pasaporte", "tc kimlik no", "t.c. kimlik no",
        "kimlik no", "pasaport no", "nir", "n° de sécurité sociale", "numéro de sécurité sociale",
        "sécurité sociale", "numéro de passeport", "ssn", "social security number", "ni number",
        "national insurance number", "national insurance", "passport number", "passport no",
        "document number",
    ]

    private static var pattern: String {
        "(?i:" + KeywordPattern.alternation(labels) + ")"
            // The value may start on the next line: "Rentenversicherungsnummer\n49 120378 N 513".
            + #"[ \t]*(?:\(|:|-)?[ \t]*(?:(?i:nummer|nr\.?|no\.?|n°|number|numéro|número|numer)[ \t]*:?[ \t]*)?\n?[ \t]*"#
            + #"((?=[A-Z0-9 ./-]*\d)[A-Z0-9](?:[A-Z0-9./-]|[ ](?=[A-Z0-9]))*[A-Z0-9])"#
    }

    public func matches(in text: String) -> [Range<String.Index>] {
        RegexScanner.ranges(of: Self.pattern, captureGroup: 1, in: text).compactMap { range in
            // Drop trailing groups that are capital words with no digit
            // ("… 029 VERGEBEN").
            var tokens = text[range].split(separator: " ", omittingEmptySubsequences: false)
            while let last = tokens.last, last.count > 3, !last.contains(where: \.isNumber) { tokens.removeLast() }
            let value = tokens.joined(separator: " ")
            guard value.filter(\.isNumber).count >= 4 else { return nil }
            return range.lowerBound..<text.index(range.lowerBound, offsetBy: value.count)
        }
    }
}

/// Identity numbers recognised by shape alone (owner, 6 Oct 2026): the German
/// health-insurance number (a capital and nine digits) and the Dutch passport
/// and identity-card document number (two capitals, six capitals or digits,
/// a digit; never the letter O).
public struct IdentityPatternRule: RedactionRule {
    public let kind = PIIKind.idNumber

    public init() {}

    private static let patterns = [
        #"(?<![\p{L}\d])[A-Z]\d{9}(?![\p{L}\d])"#,
        #"(?<![\p{L}\d])(?=(?:[A-Z]*\d){3})[A-NP-Z]{2}[A-NP-Z0-9]{6}\d(?![\p{L}\d])"#,
    ]

    public func matches(in text: String) -> [Range<String.Index>] {
        Self.patterns.flatMap { RegexScanner.ranges(of: $0, in: text) }
    }
}
