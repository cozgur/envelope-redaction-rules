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
            // Not when a separator runs on either side of it: 40.118.93 inside
            // 2026.40.118.93 is the tail of a reference, not an amount.
            #"(?<![\w/.,-])\d{1,3}(?:[.,]\d{3})*[.,]\d{2}(?![\w/-]|[.,]\d)"#,
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

    // MARK: - The sender's address (owner, 6 Oct 2026)

    /// A PO box: an office's mailing address, never a reader's -- the
    /// reader's own box, if they have one, is in their profile and L1 masks
    /// it (profile and window claims are not checked against these spans).
    private static let poBox =
        #"(?<![\p{L}])(?i:postbus|antwoordnummer|postfach|p\.?[ \t]?o\.?[ \t]?box|apartado de correos|apdo\.?(?:[ \t]+de[ \t]+correos)?|skrytka pocztowa|bo[iî]te postale)[ \t]*\d[\d \t]*|(?<![\p{L}])BP[ \t]+\d{1,5}(?!\d)"#

    /// Words that make a line an organisation's name.
    static let organisationWords: [String] = [
        "Gemeente", "Belastingdienst", "GmbH", "B.V.", "BV", "N.V.", "Ltd", "Limited", "LLC", "Inc", "plc",
        "Amt", "Finanzamt", "Bürgeramt", "Landesamt", "Agencia", "Ayuntamiento", "Urząd", "Tribunal", "Court",
        "Rechtbank", "Gerechtshof", "University", "Universiteit", "Universität", "Universidad", "Université",
        "Universitat", "Hochschule", "Council", "Ministerie", "Ministère", "Mairie", "Préfecture", "Caisse",
        "Krankenkasse", "Versicherung", "Stichting", "Waterschap", "Woningcorporatie", "Woonstichting",
        "Bank", "Sparkasse", "Rentenversicherung", "Belediyesi", "Müdürlüğü", "Vergi Dairesi", "Department",
        "Agency", "Service", "Services", "Dienst", "S.A.", "S.L.", "Sp. z o.o.", "A.Ş.", "Ltd. Şti.",
        "Jobcenter", "Polizei", "Politie", "Police", "Inspectie", "CJIB", "UWV", "DUO", "IND", "CAK", "SVB",
        "IRS", "HMRC", "DVLA", "CAF", "CPAM", "AEAT", "ZUS", "SGK", "Seguridad Social", "Hacienda",
        "Vastgoed", "Vastgoedbeheer", "Beheer", "Makelaardij", "Recovery", "Collections", "Bußgeldstelle",
        "Delegación", "Personalabteilung", "Verwaltung",
    ]

    private static var organisationPattern: String {
        let words = organisationWords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return #"(?<![\p{L}])(?:"# + words + #")(?![\p{L}])"#
    }

    /// A postcode-and-city line, in the shapes the rules know.
    private static let postcodeCityLine =
        #"^[ \t]*(?:(?:[1-9]\d{3}[ \t]{0,2}[A-Z]{2}|\d{5}|\d{2}-\d{3}|[A-Z]{1,2}\d[A-Z\d]?[ \t]?\d[A-Z]{2})[ \t]+\p{L}.*|\p{L}[\p{L} .'’-]*,?[ \t]+(?:[A-Z]{2}[ \t]+\d{5}(?:-\d{4})?|[A-Z]{1,2}\d[A-Z\d]?[ \t]?\d[A-Z]{2}|\d{5}))[ \t]*$"#

    /// A postcode anywhere in a line: the sender's address ends with it.
    private static let anyPostcode =
        #"(?<![\w./-])(?:[1-9]\d{3}[ \t]{0,2}[A-Z]{2}|\d{5}(?:-\d{4})?|\d{2}-\d{3}|[A-Z]{1,2}\d[A-Z\d]?[ \t]?\d[A-Z]{2})(?![\w./-])"#

    /// A line that opens with a person: an honorific or initials. Never the
    /// sender's.
    private static let opensWithPerson =
        #"^[ \t]*(?:(?i:mevrouw|mevr\.?|mw\.?|de heer|dhr\.?|heer|herrn?|frau|mr\.?|mrs\.?|ms\.?|miss|m\.|mme|monsieur|madame|sr\.?|sra\.?|d\.|dña\.?|pan|pani|sayın|t\.a\.v\.?|c/o|p/a|z\.[ \t]?hd\.?)(?![\p{L}])|\p{Lu}\.[ \t]?(?:\p{Lu}\.)*[ \t]*\p{L})"#

    /// A line that opens with an honorific. An organisation's name may start
    /// with initials ("J.M. Overbeek Vastgoedbeheer"); it never starts with
    /// "Mevrouw".
    private static let opensWithHonorific =
        #"^[ \t]*(?i:mevrouw|mevr\.?|mw\.?|de heer|dhr\.?|heer|herrn?|frau|mr\.?|mrs\.?|ms\.?|miss|m\.|mme|monsieur|madame|sr\.?|sra\.?|d\.|dña\.?|pan|pani|sayın|t\.a\.v\.?|c/o|p/a|z\.[ \t]?hd\.?)(?![\p{L}])"#

    /// The line up to a column gap: OCR reads two columns printed on the same
    /// rows as one line, and the right-hand one is the recipient's.
    private static func leftColumn(_ line: LetterStructure.Line, in text: String) -> Range<String.Index> {
        guard let gap = line.text.range(of: #"[ ]{3,}|\t"#, options: .regularExpression) else { return line.range }
        let offset = line.text.distance(from: line.text.startIndex, to: gap.lowerBound)
        return line.range.lowerBound..<text.index(line.range.lowerBound, offsetBy: offset)
    }

    /// The sender's address: a PO box line with the postcode line under it,
    /// and an organisation's name with the address lines of its own block.
    /// They stop address and phone claims from the rules (L3), nothing else.
    public static func senderAddresses(in text: String) -> [Span] {
        let lines = LetterStructure(text).lines
        var ranges: [Range<String.Index>] = []
        func isPostcodeLine(_ index: Int) -> Bool {
            index < lines.count && !RegexScanner.ranges(of: postcodeCityLine, in: lines[index].text).isEmpty
        }
        for (index, line) in lines.enumerated() {
            let boxes = RegexScanner.ranges(of: poBox, in: line.text)
            guard !boxes.isEmpty else { continue }
            // The box to the end of its line ("Postbus 287 7600 AG Almelo"),
            // and the postcode line under it.
            let offset = line.text.distance(from: line.text.startIndex, to: boxes[0].lowerBound)
            let column = leftColumn(line, in: text)
            let start = text.index(line.range.lowerBound, offsetBy: offset)
            guard start < column.upperBound else { continue }
            ranges.append(start..<column.upperBound)
            // The postcode line under it, unless the box's own line already
            // ended with one or the next line is a person's.
            if RegexScanner.ranges(of: anyPostcode, in: String(text[start..<column.upperBound])).isEmpty,
               isPostcodeLine(index + 1),
               RegexScanner.ranges(of: opensWithPerson, in: lines[index + 1].text).isEmpty {
                ranges.append(leftColumn(lines[index + 1], in: text))
            }
        }
        // An organisation's name line: near the top (the header, where
        // letterheads and blocks are), short, no house number, not a sentence.
        let top = min(LetterStructure(text).headerBoundary ?? 25, 25)
        for (index, line) in lines.enumerated()
        where index < top
            && line.text.count <= 70
            && !line.text.trimmingCharacters(in: .whitespaces).hasSuffix(".")
            && line.text.split(separator: " ").count <= 8
            && !RegexScanner.ranges(of: organisationPattern, in: String(text[leftColumn(line, in: text)])).isEmpty
            && RegexScanner.ranges(of: opensWithHonorific, in: line.text).isEmpty {
            let lineText = String(text[leftColumn(line, in: text)])
            // On the same line, after a comma: "Gemeente Delft, Stadhuis 1".
            // "Brühler Logistik GmbH · Industriestraße 40 · 50389 Wesseling":
            // the name, a separator, its address on the same line.
            let separators = #"[ \t]*(?:·|•|\||,|[ \t]-[ \t])[ \t]*"#
            if let first = lineText.range(of: separators, options: .regularExpression) {
                let name = lineText[..<first.lowerBound]
                let rest = lineText[first.lowerBound...]
                if !name.contains(where: \.isNumber), rest.contains(where: \.isNumber) {
                    let offset = lineText.distance(from: lineText.startIndex, to: first.lowerBound)
                    ranges.append(text.index(line.range.lowerBound, offsetBy: offset)..<text.index(line.range.lowerBound, offsetBy: lineText.count))
                    continue
                }
            }
            guard !lineText.contains(where: \.isNumber) else { continue }
            // The block's address lines below it: up to two department lines
            // first ("Personalabteilung"), then street and postcode lines,
            // ending at the postcode line.
            var next = index + 1
            var departments = 0
            var taken = 0
            while next < lines.count, taken < 4 {
                let column = leftColumn(lines[next], in: text)
                let candidate = String(text[column])
                if candidate.trimmingCharacters(in: .whitespaces).isEmpty { break }
                // Never a person's line: that is the recipient, run on
                // without a blank line.
                if !RegexScanner.ranges(of: opensWithPerson, in: candidate).isEmpty { break }
                if isPostcodeLine(next) || !RegexScanner.ranges(of: anyPostcode, in: candidate).isEmpty {
                    ranges.append(column)
                    break
                }
                if candidate.contains(where: \.isNumber) {
                    ranges.append(column)
                    taken += 1
                } else {
                    guard taken == 0, departments < 2 else { break }
                    departments += 1
                }
                next += 1
            }
        }
        return ranges.map { Span(range: $0, exemptKinds: Set(PIIKind.allCases).subtracting([.address, .phone])) }
    }
}
