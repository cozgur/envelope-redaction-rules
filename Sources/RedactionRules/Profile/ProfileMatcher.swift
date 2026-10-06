import Foundation

/// Finds the reader's own details in a letter (redaction v2 plan §1, L1).
///
/// The reader knows their name and address; a letter prints them in a dozen
/// ways and OCR adds a few more. This finds every occurrence the plan's
/// tolerance rules allow and nothing else:
///
/// - **Folding:** case, diacritics (`Yılmaz` ≡ `Yilmaz` ≡ `YILMAZ`), `ß`,
///   ligatures; for house numbers and postcodes also the OCR digit
///   confusions `O`↔`0` and `l`/`I`↔`1`.
/// - **Names:** the surname with or without initials (`A. Yilmaz`,
///   `A Yilmaz`, `A.B. Yilmaz`), with the given name, after an honorific
///   (kept outside the span), particles in either case (`de Vries`,
///   `De Vries`), the inverted form (`Vries, A. de`), each part of a double
///   surname and the whole.
/// - **Edit distance**, per token: exact under five characters; one edit
///   from five; **two** for a surname token in strong context -- right after
///   an honorific, initial(s) or a given name, or inside the address window.
/// - **Precision guards:** a surname that is also an ordinary word or a
///   common place, or one under four characters, matches only in strong
///   context. The sender's letterhead is the engine's guard, not this one's.
/// - **Addresses:** the street only together with the house number (any
///   suffix form); the postcode with any spacing; the city only on the
///   postcode's line, right after it.
public enum ProfileMatcher {

    /// Every match, as profile claims for `RedactionEngine.redact(_:countryHint:known:)`.
    /// `window` is the address window's ranges, when the app found one: a
    /// surname inside it is in strong context.
    public static func claims(
        in text: String,
        profile: RedactionProfile,
        window: [Range<String.Index>] = []
    ) -> [KnownClaim] {
        let tokens = Token.all(in: text)
        var names: [(range: Range<String.Index>, strong: Bool)] = []
        for person in [profile.person] + profile.household {
            names += nameMatches(of: person, in: text, tokens: tokens, window: window)
        }
        var addresses: [Range<String.Index>] = []
        if let street = profile.street, let number = profile.houseNumber {
            addresses += streetMatches(street: street, number: number, in: text, tokens: tokens)
        }
        if let postcode = profile.postcode {
            addresses += postcodeMatches(postcode, city: profile.city, in: text)
        }
        var claims: [KnownClaim] = []
        // Longest first, and no two claims overlap: "A. Yilmaz" before the
        // "Yilmaz" inside it.
        var taken: [Range<String.Index>] = []
        let all = names.map { (kind: PIIKind.name, range: $0.range, strong: $0.strong) }
            + addresses.map { (kind: PIIKind.address, range: $0, strong: false) }
        let length = { (range: Range<String.Index>) in text.distance(from: range.lowerBound, to: range.upperBound) }
        for candidate in all.sorted(by: { length($0.range) > length($1.range) }) {
            guard !taken.contains(where: { $0.overlaps(candidate.range) }) else { continue }
            taken.append(candidate.range)
            claims.append(KnownClaim(kind: candidate.kind, ranges: [candidate.range], source: .profile, strongContext: candidate.strong))
        }
        return claims.sorted { $0.ranges[0].lowerBound < $1.ranges[0].lowerBound }
    }

    // MARK: - Names

    /// Particles kept with the surname and compared exactly (folded).
    static let particles: Set<String> = [
        "van", "de", "der", "den", "het", "ten", "ter", "te", "t", "von", "zu", "du",
        "la", "le", "el", "al", "da", "di", "del", "dos", "des", "y",
    ]

    /// Words that, right before a surname, make it a name and nothing else.
    static let honorifics: Set<String> = [
        "dhr", "heer", "mevr", "mw", "mevrouw", "meneer", "fam", "familie", "tav", "aan",
        "herr", "herrn", "frau", "hd", "m", "mme", "mlle", "monsieur", "madame",
        "mr", "mrs", "ms", "miss", "dr", "drs", "prof", "ir", "mr.",
        "sayin", "bay", "bayan", "hanim", "bey",
        "pan", "pani", "panie", "pana", "panu", "panstwo",
        "sr", "sra", "srta", "don", "dona",
    ]

    /// Surnames that are also ordinary words or common places, by folded
    /// form. Matched only in strong context. A seed list, grown with the
    /// "ordinary words kept" fixtures rather than guessed at.
    static let ambiguousSurnames: Set<String> = [
        // nl
        "bakker", "visser", "smit", "mulder", "jong", "groot", "bos", "berg", "vos", "kok",
        "koster", "schipper", "smid", "brouwer", "timmer", "timmerman", "dekker", "molenaar",
        "boer", "wit", "zwart", "klein", "lange", "haan", "kuiper", "schaap", "visscher",
        "zwolle", "breda", "delft", "gouda", "hoorn", "assen", "emmen", "venlo", "kampen",
        // de
        "muller", "mueller", "schmidt", "schneider", "fischer", "weber", "meyer", "wagner",
        "becker", "koch", "richter", "wolf", "schwarz", "braun", "kruger", "lange", "krause",
        "berger", "frank", "kaiser", "fuchs", "vogel", "jager", "keller", "winter", "sommer",
        "stein", "busch", "roth", "beck", "haas", "graf", "koenig", "konig", "baumann",
        // en
        "smith", "baker", "miller", "taylor", "cook", "carter", "turner", "cooper", "walker",
        "wright", "hill", "wood", "green", "white", "black", "brown", "young", "king", "may",
        "hall", "mason", "fisher", "shepherd", "rose", "bush", "field", "brook", "lane",
        "street", "march", "april", "june", "bishop", "page", "price", "rich", "long",
        // fr
        "boulanger", "petit", "blanc", "roux", "lebrun", "legrand", "grand", "boucher",
        "mercier", "meunier", "charpentier", "marchand", "fontaine", "riviere", "roche",
        // es
        "herrero", "pastor", "molina", "castillo", "rubio", "moreno", "blanco", "delgado",
        "prieto", "calvo", "cruz", "rey", "leon", "santos", "iglesias", "campos", "vega",
        "rios", "torres", "prado", "sierra", "cordero", "mayor",
        // tr
        "demir", "kaya", "aydin", "arslan", "kurt", "koc", "kilic", "kara", "polat", "yavuz",
        "bulut", "deniz", "toprak", "gunes", "yildirim", "ates", "tas", "acar", "erdem",
        // pl
        "kowal", "lis", "wilk", "kot", "sowa", "mazur", "baran", "sikora", "zajac", "kruk",
        "kozak", "nowak",
    ]

    /// Whether `name` is one surname that matches only in strong context:
    /// an ordinary word or place, or under four letters. Particles do not
    /// count ("de Groot" is "groot").
    static func isAmbiguousAlone(_ name: String) -> Bool {
        let cores = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map { fold(String($0)) }
            .filter { !particles.contains($0) }
        guard cores.count == 1, let core = cores.first else { return false }
        return ambiguousSurnames.contains(core) || core.count < 4
    }

    private struct Part {
        /// Folded tokens, particles included, in order.
        var tokens: [String]
        var core: [String] { tokens.filter { !ProfileMatcher.particles.contains($0) } }
    }

    private static func parts(of surname: String) -> [Part] {
        surname.split(separator: "-").map { segment in
            Part(tokens: segment.split(whereSeparator: { $0.isWhitespace }).map { fold(String($0)) }.filter { !$0.isEmpty })
        }.filter { !$0.tokens.isEmpty }
    }

    private static func nameMatches(
        of person: RedactionProfile.Person,
        in text: String,
        tokens: [Token],
        window: [Range<String.Index>]
    ) -> [(range: Range<String.Index>, strong: Bool)] {
        let surnameParts = parts(of: person.surname)
        guard !surnameParts.isEmpty else { return [] }
        let given = (person.givenNames ?? "").split(whereSeparator: { $0.isWhitespace || $0 == "-" }).map { fold(String($0)) }
        // The whole surname as one sequence, then each part on its own.
        var sequences: [[String]] = [surnameParts.flatMap(\.tokens)]
        if surnameParts.count > 1 { sequences += surnameParts.map(\.tokens) }

        var found: [(range: Range<String.Index>, strong: Bool)] = []
        for sequence in sequences {
            let cores = sequence.filter { !particles.contains($0) }
            guard !cores.isEmpty else { continue }
            var index = 0
            while index < tokens.count {
                defer { index += 1 }
                guard let match = matchSurname(sequence, at: index, tokens: tokens, text: text, given: given, window: window) else { continue }
                found.append(match)
            }
            // The sequence without its leading particles, for a letter that
            // drops them ("R.A. Meulen") -- a core-only form of the same part.
            let leading = sequence.prefix { particles.contains($0) }.count
            if leading > 0 {
                let coreOnly = Array(sequence.dropFirst(leading))
                for start in tokens.indices {
                    if let match = matchSurname(coreOnly, at: start, tokens: tokens, text: text, given: given, window: window) {
                        found.append(match)
                    }
                }
            }
        }
        return found
    }

    /// The name span when the surname `sequence` starts at token `index`, or
    /// nil. The span takes in preceding initials and given names, and an
    /// inverted form's trailing initials and particles; never an honorific.
    private static func matchSurname(
        _ sequence: [String],
        at index: Int,
        tokens: [Token],
        text: String,
        given: [String],
        window: [Range<String.Index>]
    ) -> (range: Range<String.Index>, strong: Bool)? {
        guard index + sequence.count <= tokens.count else { return nil }
        // Tokens must be consecutive words: only spaces between them, or a
        // hyphen inside a double surname.
        for offset in 1..<max(1, sequence.count) {
            guard Token.adjacent(tokens[index + offset - 1], tokens[index + offset], in: text, allowing: " -\t") else { return nil }
        }

        // Context before the surname: initials, given names, an honorific.
        var start = index
        var strong = false
        var cursor = index - 1
        while cursor >= 0, Token.adjacent(tokens[cursor], tokens[cursor + 1], in: text, allowing: " .\t\n") {
            let token = tokens[cursor]
            if token.isInitial || (!given.isEmpty && given.contains { within(token.folded, $0, maxEdits: tolerance($0.count, strong: false)) }) {
                start = cursor
                strong = true
                cursor -= 1
            } else {
                break
            }
        }
        if cursor >= 0, honorifics.contains(tokens[cursor].folded),
           Token.adjacent(tokens[cursor], tokens[cursor + 1], in: text, allowing: " .\t\n") {
            strong = true
        }
        let first = tokens[index]
        if window.contains(where: { $0.contains(first.range.lowerBound) }) { strong = true }

        // The surname itself.
        for (offset, wanted) in sequence.enumerated() {
            let token = tokens[index + offset]
            if particles.contains(wanted) {
                guard token.folded == wanted else { return nil }
            } else {
                guard within(token.folded, wanted, maxEdits: tolerance(wanted.count, strong: strong)) else { return nil }
            }
        }
        let cores = sequence.filter { !particles.contains($0) }
        let ambiguous = cores.count == 1 && (ambiguousSurnames.contains(cores[0]) || cores[0].count < 4)
        // The inverted form: "Vries, A. de".
        var end = tokens[index + sequence.count - 1].range.upperBound
        var after = index + sequence.count
        if after < tokens.count, text[end..<tokens[after].range.lowerBound].trimmingCharacters(in: .whitespaces) == "," {
            var cursor = after
            var sawInitial = false
            while cursor < tokens.count, tokens[cursor].isInitial || (!given.isEmpty && given.contains(tokens[cursor].folded)) {
                guard Token.adjacent(tokens[cursor - 1], tokens[cursor], in: text, allowing: " .,\t") else { break }
                sawInitial = true
                cursor += 1
            }
            if sawInitial {
                strong = true
                while cursor < tokens.count, particles.contains(tokens[cursor].folded),
                      Token.adjacent(tokens[cursor - 1], tokens[cursor], in: text, allowing: " .\t") {
                    cursor += 1
                }
                after = cursor
                end = tokens[cursor - 1].range.upperBound
                if text[end...].first == "." , tokens[cursor - 1].isInitial { end = text.index(after: end) }
            }
        }
        if ambiguous && !strong { return nil }
        if !strong {
            // Out of context the surname must still be a word on its own and
            // look like a name: capitalised.
            guard first.text.first?.isUppercase == true else { return nil }
        }
        // A strong-context match with more than one edit is accepted only
        // in strong context, which `tolerance` already enforced.
        return (tokens[start].range.lowerBound..<end, strong)
    }

    private static func tolerance(_ length: Int, strong: Bool) -> Int {
        if length < 5 { return 0 }
        return strong ? 2 : 1
    }

    // MARK: - Addresses

    private static func streetMatches(street: String, number: String, in text: String, tokens: [Token]) -> [Range<String.Index>] {
        let wanted = street.split(whereSeparator: { $0.isWhitespace }).map { fold(String($0)) }
        let digits = String(number.prefix { $0.isNumber })
        guard !wanted.isEmpty, !digits.isEmpty else { return [] }
        let numberCore = digitPattern(digits) + #"(?![\dOolI])"#
        let suffix = #"(?:(?:[ \t]?-[ \t]?|[ \t])?(?:[IVX]{1,4}|\d{1,2}|hs|bis|zw|bg|[A-Za-z])(?![\p{L}\d]))?"#
        // "Hoofdstraat 12-II", "Atatürk Caddesi No: 12", "Hauptstraße Nr. 12".
        guard let after = try? NSRegularExpression(
            pattern: #"^[ \t,]{1,3}(?:(?:No|Nr|Nº|n°)[.:]?[ \t]*)?"# + numberCore + suffix,
            options: [.caseInsensitive]
        ),
        // "12 High Street", "12 rue de la Paix", "12, Main Street".
        let before = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\d])"# + numberCore.replacingOccurrences(of: #"(?![\dOolI])"#, with: "") + #"[A-Za-z]?,?[ \t]{1,3}$"#
        )
        else { return [] }

        var found: [Range<String.Index>] = []
        for index in tokens.indices where index + wanted.count <= tokens.count {
            var ok = true
            for (offset, word) in wanted.enumerated() {
                let token = tokens[index + offset]
                if offset > 0, !Token.adjacent(tokens[index + offset - 1], token, in: text, allowing: " \t") { ok = false; break }
                if !within(token.folded, word, maxEdits: tolerance(word.count, strong: false)) { ok = false; break }
            }
            guard ok else { continue }
            let streetStart = tokens[index].range.lowerBound
            let streetEnd = tokens[index + wanted.count - 1].range.upperBound

            let rest = String(text[streetEnd...].prefix(40))
            if let match = after.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
               let whole = Range(match.range, in: rest) {
                found.append(streetStart..<text.index(streetEnd, offsetBy: rest.distance(from: rest.startIndex, to: whole.upperBound)))
                continue
            }
            let lineStart = text[..<streetStart].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            let head = String(text[lineStart..<streetStart])
            if let match = before.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
               let whole = Range(match.range, in: head) {
                let offset = head.distance(from: head.startIndex, to: whole.lowerBound)
                found.append(text.index(lineStart, offsetBy: offset)..<streetEnd)
            }
        }
        return found
    }

    private static func postcodeMatches(_ postcode: String, city: String?, in text: String) -> [Range<String.Index>] {
        let compact = postcode.filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return [] }
        var pattern = #"(?<![\p{L}\d])"#
        for (position, character) in compact.enumerated() {
            if position > 0 { pattern += #"[ \t]{0,2}"# }
            pattern += character.isNumber ? digitPattern(String(character)) : NSRegularExpression.escapedPattern(for: String(character))
        }
        pattern += #"(?![\p{L}\d])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        var found: [Range<String.Index>] = []
        let digitsOnly = compact.allSatisfy(\.isNumber)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            var end = range.upperBound
            let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            let atLineStart = text[lineStart..<range.lowerBound].allSatisfy { $0 == " " || $0 == "\t" }
            if let city {
                // The city right after the postcode on the same line.
                let lineEnd = text[end...].firstIndex(of: "\n") ?? text.endIndex
                let rest = text[end..<lineEnd]
                let words = city.split(whereSeparator: { $0.isWhitespace }).map { fold(String($0)) }
                let restTokens = Token.all(in: String(rest))
                if restTokens.count >= words.count,
                   String(rest).prefix(through: restTokens[0].range.lowerBound).dropLast().allSatisfy({ $0 == " " || $0 == "\t" || $0 == "," }),
                   zip(restTokens, words).allSatisfy({ within($0.folded, $1, maxEdits: tolerance($1.count, strong: false)) }) {
                    let last = restTokens[words.count - 1].range.upperBound
                    end = text.index(end, offsetBy: String(rest).distance(from: String(rest).startIndex, to: last))
                }
            }
            // A postcode of digits alone is also a piece of a phone number,
            // an amount or a reference. It counts only with the city right
            // after it, or, with no city in the profile, at the start of a
            // line as an address prints it.
            if digitsOnly {
                let withCity = end != range.upperBound
                guard withCity || (city == nil && atLineStart) else { continue }
            }
            found.append(range.lowerBound..<end)
        }
        return found
    }

    /// A digit, or the letters OCR reads for it.
    private static func digitPattern(_ digits: String) -> String {
        digits.map { character -> String in
            switch character {
            case "0": "[0Oo]"
            case "1": "[1lI]"
            default: String(character)
            }
        }.joined()
    }

    // MARK: - Folding and distance

    /// Case, diacritics, `ı`, `ß`, ligatures.
    static func fold(_ value: String) -> String {
        value
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ł", with: "l")
            .replacingOccurrences(of: "Ł", with: "l")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "ﬁ", with: "fi")
            .replacingOccurrences(of: "ﬂ", with: "fl")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .lowercased()
    }

    static func within(_ a: String, _ b: String, maxEdits: Int) -> Bool {
        if a == b { return true }
        if maxEdits == 0 || abs(a.count - b.count) > maxEdits { return false }
        return levenshtein(Array(a), Array(b), limit: maxEdits) <= maxEdits
    }

    private static func levenshtein(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        var previous = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            var best = current[0]
            for (j, cb) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (ca == cb ? 0 : 1))
                best = min(best, current[j + 1])
            }
            if best > limit { return limit + 1 }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: - Tokens

    struct Token {
        var range: Range<String.Index>
        var text: Substring
        var folded: String

        /// "A", "A.", or one capital letter: an initial.
        var isInitial: Bool { text.count == 1 && text.first?.isUppercase == true }

        static func all(in text: String) -> [Token] {
            var tokens: [Token] = []
            var index = text.startIndex
            while index < text.endIndex {
                guard isWordCharacter(text[index]) else { index = text.index(after: index); continue }
                var end = index
                while end < text.endIndex, isWordCharacter(text[end]) || isInnerApostrophe(at: end, in: text) {
                    end = text.index(after: end)
                }
                let piece = text[index..<end]
                tokens.append(Token(range: index..<end, text: piece, folded: ProfileMatcher.fold(String(piece))))
                index = end
            }
            return tokens
        }

        private static func isWordCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber
        }

        private static func isInnerApostrophe(at index: String.Index, in text: String) -> Bool {
            guard text[index] == "'" || text[index] == "’" else { return false }
            let next = text.index(after: index)
            return next < text.endIndex && text[next].isLetter && index > text.startIndex
        }

        /// Whether only the characters in `allowing` stand between two tokens.
        static func adjacent(_ left: Token, _ right: Token, in text: String, allowing: String) -> Bool {
            let between = text[left.range.upperBound..<right.range.lowerBound]
            return between.count <= 4 && between.allSatisfy { allowing.contains($0) }
        }
    }
}
