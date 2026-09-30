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
        "albumu", "album", "esas", "id", "werkorder",
        "polis", "contract", "zaak",
    ]

    /// Labels worth matching mid-sentence, where there is no field line to
    /// anchor to.
    private static let inlineKeywords = [
        "kenmerk", "referentie", "zaaknummer", "dossiernummer",
        "aanslagnummer", "betalingskenmerk",
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

    /// A one-word label ending in a reference stem, no colon, then the value
    /// to the end of the line: `Contractnummer WN-7781-2024`,
    /// `Klantnummer 7710 4402 19`.
    ///
    /// One word, so a sentence cannot pass for a label; never a telephone
    /// or fax label, whose number is the phone rule's to claim.
    private static var bareLabelLinePattern: String {
        let stems = labelStems
            .filter { $0.count > 2 }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        // The value runs to the end of the line, so it may be spaced groups
        // with a short last group or a letter prefix (NL-ZN 0098 1123 45):
        // nothing follows it for the groups to swallow.
        return #"(?im)^[ \t]*(?!\S*(?:telefoon|telefon|phone|fax|antwoordnummer))(?=\p{L})[\p{L}-]{0,39}(?:"# + stems
            + #")[ \t]+("# + spacedLineValue
            + #"|(?=[\p{L}\d./-]*\d)[\p{L}\d][\p{L}\d./-]{2,}[\p{L}\d])[ \t]*$"#
    }

    /// Spaced digit groups at the end of a line, with an optional capital
    /// prefix: `2026 4471 0098 55`, `AB 2026 3141 59`, `ZK-NL 4410 2208 17`.
    private static var spacedLineValue: String {
        #"(?:\p{Lu}{1,4}(?:-\p{Lu}{1,4})?[ -])?\d{2,6}(?: \d{2,6}){1,5}"#
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
        //
        // Or digit groups separated by single spaces -- `5021 8834 1107`, the
        // way Dutch municipalities print an assessment number. Taken as one
        // value: stopping at the first space masked `5021` and sent the rest.
        // Groups of three digits or more, so a date or an amount that follows
        // the reference (`… 1107 14 oktober`, `… 1107 € 284,00`) is not
        // swallowed into it.
        return "(?i)" + keywords
            + #"[^\n]{0,20}?[:\s]\s*(\d{3,6}(?: \d{3,6}){1,4}(?!\d|[,.]\d)|(?=[A-Z0-9./-]*\d)[A-Z0-9][A-Z0-9./-]{2,}[A-Z0-9])"#
    }

    public func matches(in text: String) -> [Range<String.Index>] {
        let found = RegexScanner.ranges(of: Self.fieldLinePattern, captureGroup: 1, in: text)
            + RegexScanner.ranges(of: Self.wordStemLinePattern, captureGroup: 1, in: text)
            + RegexScanner.ranges(of: Self.inlinePattern, captureGroup: 1, in: text)
            + RegexScanner.ranges(of: Self.bareLabelLinePattern, captureGroup: 1, in: text)
        return Self.merged(found)
    }

    /// Overlapping claims on one reference, as the one span they cover.
    ///
    /// Two patterns can read the same line differently -- the inline one
    /// takes `2026 3141` from `Dossiernummer AB 2026 3141 59`, the line one
    /// takes all of it -- and the engine keeps whichever claim comes first.
    /// Keeping the shorter would send the rest of the number.
    static func merged(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, last.overlaps(range) {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
