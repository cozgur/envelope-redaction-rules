import Foundation

/// Finds case, file and assessment references.
///
/// A reference has no format worth matching -- every authority invents its own
/// -- so the label is the signal. Rather than enumerate every label in eight
/// countries, which is a list that is wrong the moment a ninth authority is
/// added, this matches the *shape* official mail uses: a field line whose
/// label ends in a reference word, followed by a colon and the value.
///
/// The value is masked and restored on device for the reply header, which is
/// the one place it has to be exact.
public struct ReferenceNumberRule: RedactionRule {
    public let kind = PIIKind.reference

    public init() {}

    /// Word endings that mark a label as introducing a reference, across the
    /// seven UI languages plus English.
    ///
    /// Matched as label *suffixes*, so `Kundennummer`, `Matrikelnummer` and
    /// `Versichertennummer` are all covered by `nummer` without being listed.
    private static let labelStems = [
        "nummer", "number", "numer", "numéro", "numero", "número",
        "numara", "numarası", "numarasi", "no",
        "ref", "reference", "referentie", "référence", "referencia", "referans",
        "zeichen", "kenmerk", "dossier", "sprawy", "sygnatura",
        "expediente", "procedimiento", "matricule", "matrikel",
        "albumu", "album", "esas", "id",
    ]

    /// Labels worth matching mid-sentence, where there is no field line to
    /// anchor to.
    private static let inlineKeywords = [
        "kenmerk", "referentie", "zaaknummer", "dossiernummer",
        "aktenzeichen", "kassenzeichen", "kundennummer", "personalnummer",
        "référence", "numéro de dossier",
        "referencia", "expediente",
        "nr sprawy", "numer sprawy", "znak sprawy",
        "referans", "dosya no",
        "case number", "our ref", "your ref", "reference number",
        "account number", "claim number", "policy number",
    ]

    /// A whole field line: label ending in a reference stem, a colon, then the
    /// value running to the end of the line.
    ///
    /// Anchoring to the line lets the value contain spaces, which court
    /// references routinely do (`12 C 714/26`), without the pattern swallowing
    /// half a sentence.
    private static var fieldLinePattern: String {
        let stems = labelStems
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return #"(?im)^[\p{L}][^\n:]{0,38}(?:"# + stems
            + #")[ \t]*:[ \t]*([\p{L}\d][\p{L}\d ./-]{2,}[\p{L}\d])[ \t]*$"#
    }

    /// The same field line, but with the stem as a whole word inside the
    /// label rather than at its end.
    ///
    /// Covers `Número de empleado:` and `Numéro de rendez-vous :`, where the
    /// reference word leads the label instead of closing it. Whole words
    /// only: matching a stem anywhere inside a label would make the Dutch
    /// `Betreft:` -- which contains "ref" -- look like a reference field and
    /// mask the letter's subject.
    private static var wordStemLinePattern: String {
        let stems = labelStems
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return #"(?im)^[^\n:]{0,20}\b(?:"# + stems
            + #")\b[^\n:]{0,24}[ \t]*:[ \t]*([\p{L}\d][\p{L}\d ./-]{2,}[\p{L}\d])[ \t]*$"#
    }

    /// A known label mid-sentence, then the token that follows it.
    private static var inlinePattern: String {
        let keywords = KeywordPattern.alternation(inlineKeywords)
        // The token must be at least four characters and contain a digit.
        //
        // The looser version -- "carries a separator or a letter" -- matched
        // any two letters under the case-insensitive flag, so the Spanish
        // "Número de expediente:" line yielded the word "de" as a reference.
        // The engine then masked every "de" in the letter. A reference always
        // has a digit in it; ordinary words do not.
        return "(?i)" + keywords
            + #"[^\n]{0,20}?[:\s]\s*((?=[A-Z0-9./-]*\d)[A-Z0-9][A-Z0-9./-]{2,}[A-Z0-9])"#
    }

    public func matches(in text: String) -> [Range<String.Index>] {
        RegexScanner.ranges(of: Self.fieldLinePattern, captureGroup: 1, in: text)
            + RegexScanner.ranges(of: Self.wordStemLinePattern, captureGroup: 1, in: text)
            + RegexScanner.ranges(of: Self.inlinePattern, captureGroup: 1, in: text)
    }
}
