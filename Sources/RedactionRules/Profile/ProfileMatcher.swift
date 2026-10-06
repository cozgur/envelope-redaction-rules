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
        window: [Range<String.Index>] = [],
        countryHint: String? = nil
    ) -> [KnownClaim] {
        let tokens = Token.all(in: text)
        // Polish case forms of names and streets are matched in a Polish
        // letter: the country is PL, or a Polish honorific is in the text.
        let polish = countryHint?.uppercased() == "PL"
            || tokens.contains { polishHonorifics.contains($0.folded) }
        var names: [(range: Range<String.Index>, strong: Bool)] = []
        var readerStrong = false
        for (position, person) in ([profile.person] + profile.household).enumerated() {
            let matches = nameMatches(of: person, in: text, tokens: tokens, window: window, polish: polish)
            if position == 0, matches.contains(where: \.strong) { readerStrong = true }
            names += matches.map { ($0.range, $0.strong) }
            names += givenNameAlone(
                of: person, in: text, tokens: tokens,
                fullNameInLetter: matches.contains(where: \.withGivenName), polish: polish
            ).map { ($0, true) }
        }
        // Set 4 (owner, 6 Oct 2026): a second surname joined to the
        // profile's by a hyphen -- "Schouten-Brink", "Brink-Schouten" -- is
        // part of the same name and is masked with it.
        names = names.map { (withHyphenatedSurname($0.range, in: text), $0.strong) }
        // Spanish names carry two surnames and a reader may type one
        // ("Castillo" for "Castillo García"; owner, 6 Oct 2026): in a Spanish
        // letter a match ending on the profile's surname takes the
        // capitalised surname printed after it, with its particles.
        if countryHint?.uppercased() == "ES" {
            let surnames = ([profile.person] + profile.household).compactMap { person -> String? in
                let parts = person.surname.split(whereSeparator: { $0.isWhitespace })
                return parts.count == 1 ? fold(String(parts[0])) : nil
            }
            names = names.map { (withSecondSurname($0.range, surnames: surnames, in: text), $0.strong) }
        }
        var addresses: [Range<String.Index>] = []
        if let street = profile.street, let number = profile.houseNumber {
            let dutch = countryHint == nil || countryHint?.uppercased() == "NL"
            addresses += streetMatches(street: street, number: number, in: text, tokens: tokens, polish: polish, dutch: dutch)
        }
        if let postcode = profile.postcode {
            addresses += postcodeMatches(postcode, city: profile.city, in: text)
        }
        // The reader's aliases: their words, whole, in any case, with any
        // spacing between them. Exact otherwise -- the reader chose this
        // text, so it is not stretched.
        var aliases: [(kind: PIIKind, range: Range<String.Index>)] = []
        for alias in profile.aliases {
            let words = alias.text.split(whereSeparator: { $0.isWhitespace }).map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !words.isEmpty, alias.text.count >= 3 else { continue }
            let pattern = #"(?<![\p{L}\d])"# + words.joined(separator: #"\s+"#) + #"(?![\p{L}\d])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text) { aliases.append((alias.kind, range)) }
            }
        }
        var claims: [KnownClaim] = []
        // Longest first, and no two claims overlap: "A. Yilmaz" before the
        // "Yilmaz" inside it.
        var taken: [Range<String.Index>] = []
        // An address match passes the letterhead guard when the letter names
        // the reader in a strong form: it is then this reader's letter, and a
        // recipient block printed in the same rows as the sender's column is
        // read into the letterhead (deviation 4, plan §1).
        let all = names.map { (kind: PIIKind.name, range: $0.range, strong: $0.strong) }
            + addresses.map { (kind: PIIKind.address, range: $0, strong: readerStrong) }
            + aliases.map { (kind: $0.kind, range: $0.range, strong: true) }
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
        "van", "de", "der", "den", "het", "ten", "ter", "te", "t", "in", "von", "zu", "du",
        "la", "le", "el", "al", "da", "di", "del", "dos", "des",
    ]

    /// Words that join two surnames and may be printed or left out: Catalan
    /// "Martí i Soler", Spanish "García y López", Portuguese "Silva e Costa".
    static let connectors: Set<String> = ["i", "y", "e"]

    /// Words that, right before a surname, make it a name and nothing else.
    static let honorifics: Set<String> = [
        "dhr", "heer", "mevr", "mw", "mevrouw", "meneer", "fam", "familie", "tav", "aan",
        "herr", "herrn", "frau", "hd", "eheleute", "ehepaar", "ehel", "m", "mme", "mlle", "monsieur", "madame",
        "mr", "mrs", "ms", "miss", "dr", "drs", "prof", "ir", "mr.",
        "sayin", "bay", "bayan", "hanim", "bey",
        "pan", "pani", "panie", "pana", "panu", "pania", "panem", "panstwo",
        "sr", "sra", "srta", "don", "dona", "dna",
    ]

    /// The Polish honorifics in their case forms (folded: "Panią" is "pania").
    static let polishHonorifics: Set<String> = ["pan", "pani", "panu", "pania", "pana", "panem", "panie", "panstwo"]

    /// Polish case endings for names and street names, folded ("-ą" is "-a",
    /// "-ę" is "-e"); masculine and feminine, the owner's list plus the
    /// instrumental "-im"/"-iem" and the vocative "-o".
    private static let polishEndings = ["", "a", "owi", "em", "iem", "u", "ego", "iego", "emu", "iemu", "iej", "ej", "im", "y", "ie", "e", "o", "i"]

    /// The stem a case ending attaches to: "kowalski" and "kowalska" to
    /// "kowalsk", "anna" to "ann", "jan" stays "jan".
    private static func polishStem(_ word: String) -> String {
        for suffix in ["ski", "cki", "dzki", "ska", "cka", "dzka"] where word.hasSuffix(suffix) {
            return String(word.dropLast())
        }
        if let last = word.last, "ayi".contains(last), word.count > 3 { return String(word.dropLast()) }
        return word
    }

    /// Whether `token` is `word` in a Polish case form.
    static func polishForm(_ token: String, of word: String) -> Bool {
        let stem = polishStem(word)
        guard stem.count >= 3, token.hasPrefix(stem) else { return false }
        return polishEndings.contains(String(token.dropFirst(stem.count)))
    }

    /// Words that open a salutation, at the start of a line (owner, 6 Oct
    /// 2026): a given name alone is the reader's there.
    static let salutations: Set<String> = [
        "beste", "lieve", "geachte", "hallo", "hoi", "dear", "hello", "hi", "hey",
        "sehr", "liebe", "lieber", "cher", "chere", "chers", "bonjour",
        "sayin", "sevgili", "merhaba", "szanowny", "szanowna", "drogi", "droga",
        "estimado", "estimada", "querido", "querida", "hola",
    ]

    /// Words a salutation may carry between its opening and the name.
    private static let salutationFillers: Set<String> = ["geehrte", "geehrter", "geehrt"]

    /// Surnames that are also ordinary words or common places, by folded
    /// form. Matched only in strong context. A seed list, grown with the
    /// "ordinary words kept" fixtures rather than guessed at.
    static let ambiguousSurnames: Set<String> = [
        // nl
        "bakker", "visser", "smit", "mulder", "jong", "groot", "bos", "berg", "vos", "kok",
        "koster", "schipper", "smid", "brouwer", "timmer", "timmerman", "dekker", "molenaar",
        "boer", "wit", "zwart", "klein", "lange", "haan", "kuiper", "schaap", "visscher",
        "zwolle", "breda", "delft", "gouda", "hoorn", "assen", "emmen", "venlo", "kampen",
        "hoek", "dijk",
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

    /// Given names that are also ordinary words or places: alone, only in a
    /// salutation (owner, 6 Oct 2026).
    static let ambiguousGivenNames: Set<String> = [
        "leon", "noor", "roos", "mark", "fleur", "merel", "jet", "linde", "sterre", "bas",
        "rose", "may", "june", "iris", "lily", "daisy", "hope", "joy", "grace", "faith",
        "bill", "pat", "will", "art", "frank", "rob", "sky", "ray", "dawn", "summer",
        "pierre", "claire", "blanche", "aime", "rosa", "luz", "paz", "dolores", "consuelo",
        "pilar", "rocio", "soledad", "mercedes", "amparo", "esperanza", "cruz",
        "deniz", "umut", "baris", "can", "ay", "gunes", "bahar", "yagmur", "ozgur", "erdem",
        "sevgi", "dogan", "kaya", "aslan", "kartal", "roza",
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
    }

    private static func parts(of surname: String) -> [Part] {
        surname.split(separator: "-").map { segment in
            Part(tokens: segment.split(whereSeparator: { $0.isWhitespace }).map { fold(String($0)) }.filter { !$0.isEmpty })
        }.filter { !$0.tokens.isEmpty }
    }

    struct NameMatch {
        var range: Range<String.Index>
        var strong: Bool
        /// A given name stood with the surname, before or after it.
        var withGivenName: Bool
    }

    private static func givenTokens(of person: RedactionProfile.Person) -> [String] {
        (person.givenNames ?? "").split(whereSeparator: { $0.isWhitespace || $0 == "-" }).map { fold(String($0)) }
    }

    private static func nameMatches(
        of person: RedactionProfile.Person,
        in text: String,
        tokens: [Token],
        window: [Range<String.Index>],
        polish: Bool
    ) -> [NameMatch] {
        let surnameParts = parts(of: person.surname)
        guard !surnameParts.isEmpty else { return [] }
        let given = givenTokens(of: person)
        // The whole surname as one sequence, then each part on its own; a
        // space-separated double surname ("García López") is split too.
        var sequences: [[String]] = [surnameParts.flatMap(\.tokens)]
        if surnameParts.count > 1 { sequences += surnameParts.map(\.tokens) }
        for part in surnameParts {
            let cores = part.tokens.filter { !particles.contains($0) }
            if cores.count > 1 { sequences += cores.map { [$0] } }
        }

        var found: [NameMatch] = []
        for sequence in sequences {
            guard sequence.contains(where: { !particles.contains($0) }) else { continue }
            for index in tokens.indices {
                if let match = matchSurname(sequence, at: index, tokens: tokens, text: text, given: given, window: window, polish: polish) {
                    found.append(match)
                }
            }
            // The sequence without its leading particles, for a letter that
            // drops them ("R.A. Meulen").
            let leading = sequence.prefix { particles.contains($0) }.count
            if leading > 0 {
                let coreOnly = Array(sequence.dropFirst(leading))
                for start in tokens.indices {
                    if let match = matchSurname(coreOnly, at: start, tokens: tokens, text: text, given: given, window: window, polish: polish) {
                        found.append(match)
                    }
                }
            }
        }
        return found
    }

    /// Whether a token is one of the person's given names.
    private static func isGiven(_ token: Token, _ given: [String], polish: Bool = false) -> Bool {
        !given.isEmpty && token.text.first?.isUppercase == true
            && given.contains { word in
                within(token.folded, word, maxEdits: tolerance(word.count, strong: false))
                    || (polish && (polishForm(token.folded, of: word) || polishGivenForm(token.folded, of: word)))
            }
    }

    /// A Polish feminine given name in its dative or locative, where the
    /// stem's last consonant changes (owner, 6 Oct 2026): Agnieszka →
    /// Agnieszce, Olga → Oldze, Marta → Marcie, Anna → Annie, Maria → Marii.
    /// Folded, so "ł" is "l".
    static func polishGivenForm(_ token: String, of word: String) -> Bool {
        let changes: [(String, String)] = [
            ("cha", "sze"), ("ka", "ce"), ("ga", "dze"), ("ta", "cie"), ("da", "dzie"), ("ra", "rze"),
            ("la", "le"), ("na", "nie"), ("ma", "mie"), ("wa", "wie"), ("sa", "sie"), ("za", "zie"),
            ("ba", "bie"), ("pa", "pie"), ("fa", "fie"), ("ia", "ii"),
        ]
        for (ending, form) in changes where word.count > ending.count + 1 && word.hasSuffix(ending) {
            if token == String(word.dropLast(ending.count)) + form { return true }
        }
        // A masculine name with a mobile e: Marek → Marka, Markowi, Markiem,
        // Marku; Paweł → Pawła (owner, 6 Oct 2026).
        for ending in ["ek", "el", "ec"] where word.count > 3 && word.hasSuffix(ending) {
            let stem = String(word.dropLast(2)) + String(ending.last!)
            if ["a", "owi", "iem", "em", "u", "ie"].contains(where: { token == stem + $0 }) { return true }
        }
        return false
    }

    /// The name span when the surname `sequence` starts at token `index`, or
    /// nil. The span takes in initials and given names before the surname,
    /// and after it (the surname-first forms, with or without a comma:
    /// "OKAFOR Ngozi", "GARCIA LOPEZ JOSE LUIS", "Vries, A. de"); never an
    /// honorific.
    private static func matchSurname(
        _ sequence: [String],
        at index: Int,
        tokens: [Token],
        text: String,
        given: [String],
        window: [Range<String.Index>],
        polish: Bool
    ) -> NameMatch? {
        // The surname's words without connectors; in the text a connector may
        // stand between two of them ("Martí i Soler" for "Martí Soler").
        let sequence = sequence.filter { !connectors.contains($0) }
        guard !sequence.isEmpty, index < tokens.count else { return nil }
        var positions = [index]
        for _ in 1..<max(1, sequence.count) {
            let previous = positions[positions.count - 1]
            var next = previous + 1
            if next + 1 < tokens.count, connectors.contains(tokens[next].folded),
               Token.adjacent(tokens[previous], tokens[next], in: text, allowing: " \t") {
                next += 1
            }
            guard next < tokens.count,
                  // "In 't Veld": the apostrophe of "'t" stands between particles.
                  Token.adjacent(tokens[next - 1], tokens[next], in: text, allowing: " -\t'’")
            else { return nil }
            positions.append(next)
        }
        let last = positions[positions.count - 1]

        // Before the surname: initials and given names -- "Anna-Lena" is two
        // given-name tokens joined by a hyphen -- then perhaps an honorific.
        var start = index
        var strong = false
        var givenBefore = false
        var cursor = index - 1
        while cursor >= 0, Token.adjacent(tokens[cursor], tokens[cursor + 1], in: text, allowing: " .\t\n-") {
            let token = tokens[cursor]
            if isGiven(token, given, polish: polish) {
                givenBefore = true
            } else if particles.contains(token.folded), given.contains(token.folded) {
                // A particle inside the given names the reader typed: "María
                // del Carmen" (owner, 6 Oct 2026).
            } else if !token.isInitial {
                break
            }
            start = cursor
            strong = true
            cursor -= 1
        }
        if cursor >= 0, honorifics.contains(tokens[cursor].folded),
           Token.adjacent(tokens[cursor], tokens[cursor + 1], in: text, allowing: " .\t\n") {
            strong = true
        }
        let first = tokens[index]
        if window.contains(where: { $0.contains(first.range.lowerBound) }) { strong = true }

        // The surname itself. The tolerance of a strong context is decided
        // before the trailing forms are read, so a trailing given name cannot
        // lend two edits to a surname it does not stand next to.
        let strongBefore = strong
        var trailingGivenStrong = false
        // Peek: a surname-first form makes the context strong too.
        let peekEnd = last + 1
        if peekEnd < tokens.count {
            let gap = text[tokens[peekEnd - 1].range.upperBound..<tokens[peekEnd].range.lowerBound]
            if gap.count <= 3, gap.allSatisfy({ $0 == " " || $0 == "\t" || $0 == "," }),
               isGiven(tokens[peekEnd], given, polish: polish) {
                trailingGivenStrong = true
            }
        }
        for (offset, wanted) in sequence.enumerated() {
            let token = tokens[positions[offset]]
            // An honorific or a salutation word is never the surname, however
            // close it is: "Sayın" is two edits from "Aydın".
            if honorifics.contains(token.folded) || salutations.contains(token.folded) { return nil }
            if particles.contains(wanted) {
                guard token.folded == wanted else { return nil }
            } else {
                guard within(token.folded, wanted, maxEdits: tolerance(wanted.count, strong: strongBefore || trailingGivenStrong))
                    || (polish && polishForm(token.folded, of: wanted))
                else { return nil }
            }
        }
        let cores = sequence.filter { !particles.contains($0) }
        let ambiguous = cores.count == 1 && (ambiguousSurnames.contains(cores[0]) || cores[0].count < 4)

        // After the surname: given names and initials, with or without a
        // comma. An initial after a surname counts only when it is one of the
        // reader's own initials (when the profile has given names), so a
        // company's "Visser B.V." is not read as a person.
        var end = tokens[last].range.upperBound
        var givenAfter = false
        var after = last + 1
        if after < tokens.count {
            let gap = text[end..<tokens[after].range.lowerBound]
            let comma = gap.trimmingCharacters(in: .whitespaces) == ","
            if gap.count <= 3, comma || gap.allSatisfy({ $0 == " " || $0 == "\t" }) {
                let initials = Set(given.compactMap(\.first))
                var cursor = after
                while cursor < tokens.count {
                    if cursor > after, !Token.adjacent(tokens[cursor - 1], tokens[cursor], in: text, allowing: " .\t-") { break }
                    let token = tokens[cursor]
                    if isGiven(token, given, polish: polish) {
                        givenAfter = true
                    } else if token.isInitial, initials.isEmpty || initials.contains(token.folded.first ?? " ") {
                        // an initial
                    } else {
                        break
                    }
                    cursor += 1
                }
                if cursor > after {
                    strong = true
                    if comma {
                        while cursor < tokens.count, particles.contains(tokens[cursor].folded),
                              Token.adjacent(tokens[cursor - 1], tokens[cursor], in: text, allowing: " .\t") {
                            cursor += 1
                        }
                    }
                    after = cursor
                    end = tokens[cursor - 1].range.upperBound
                    if end < text.endIndex, text[end] == ".", tokens[cursor - 1].isInitial { end = text.index(after: end) }
                }
            }
        }

        // A second surname the reader did not enter, printed after a given
        // name and the first surname at the end of a name line ("Sr. Pablo
        // Ortega Sanz"): Spanish, and other two-surname naming.
        if givenBefore, !givenAfter {
            let lineEnd = text[end...].firstIndex(of: "\n") ?? text.endIndex
            let rest = text[end..<lineEnd]
            let word = rest.trimmingCharacters(in: .whitespaces)
            if rest.first == " ", word.range(of: #"^\p{Lu}[\p{L}'’-]{2,}$"#, options: .regularExpression) != nil,
               !honorifics.contains(fold(word)), let found = text.range(of: word, range: end..<lineEnd) {
                end = found.upperBound
            }
        }

        if ambiguous && !strong { return nil }
        if !strong {
            // Out of context the surname must still look like a name:
            // capitalised.
            guard first.text.first?.isUppercase == true else { return nil }
        }
        return NameMatch(range: tokens[start].range.lowerBound..<end, strong: strong, withGivenName: givenBefore || givenAfter)
    }

    /// A given name standing alone (owner, 6 Oct 2026): (a) in a salutation
    /// at the start of a line, or (b) anywhere when the letter also names the
    /// person in full -- unless the given name is an ordinary word or place
    /// (Leon, Noor), which only (a) allows. Never inside a longer word: a
    /// token is a whole word, so "Noordwijk" is not "Noor".
    private static func givenNameAlone(
        of person: RedactionProfile.Person,
        in text: String,
        tokens: [Token],
        fullNameInLetter: Bool,
        polish: Bool
    ) -> [Range<String.Index>] {
        let names = (person.givenNames ?? "").split(whereSeparator: { $0.isWhitespace })
            .map { $0.split(separator: "-").map { fold(String($0)) } }
        var found: [Range<String.Index>] = []
        for parts in names where !parts.isEmpty {
            let ambiguous = parts.count == 1 && ambiguousGivenNames.contains(parts[0])
            for index in tokens.indices where index + parts.count <= tokens.count {
                // "d'Inès", "l'Anne": an elided article joined to the name.
                let firstToken = tokens[index].elided ?? tokens[index]
                var ok = firstToken.text.first?.isUppercase == true
                for (offset, part) in parts.enumerated() where ok {
                    let token = offset == 0 ? firstToken : tokens[index + offset]
                    if offset > 0, !Token.adjacent(tokens[index + offset - 1], token, in: text, allowing: "-") { ok = false }
                    if !within(token.folded, part, maxEdits: tolerance(part.count, strong: false))
                        && !(polish && polishForm(token.folded, of: part)) { ok = false }
                }
                guard ok else { continue }
                let range = firstToken.range.lowerBound..<tokens[index + parts.count - 1].range.upperBound
                if inSalutation(tokenAt: index, tokens: tokens, text: text)
                    || (fullNameInLetter && !ambiguous) {
                    found.append(range)
                }
            }
        }
        return found
    }

    /// Whether the token opens no line of its own but follows a salutation
    /// that does: "Beste Ruud", "Sehr geehrte Frau Anna-Lena", "Szanowna Pani
    /// Agnieszko".
    private static func inSalutation(tokenAt index: Int, tokens: [Token], text: String) -> Bool {
        var cursor = index - 1
        while cursor >= 0, Token.adjacent(tokens[cursor], tokens[cursor + 1], in: text, allowing: " .\t"),
              honorifics.contains(tokens[cursor].folded) || salutationFillers.contains(tokens[cursor].folded) {
            cursor -= 1
        }
        guard cursor >= 0, salutations.contains(tokens[cursor].folded),
              Token.adjacent(tokens[cursor], tokens[cursor + 1], in: text, allowing: " .\t") || cursor + 1 == index
        else { return false }
        let lineStart = text[..<tokens[cursor].range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        return text[lineStart..<tokens[cursor].range.lowerBound].allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func tolerance(_ length: Int, strong: Bool) -> Int {
        if length < 5 { return 0 }
        return strong ? 2 : 1
    }

    /// A name match that ends on one of `surnames`, widened over the next
    /// capitalised surname on the same line ("Castillo García", "MORENO DE
    /// LA FUENTE").
    private static func withSecondSurname(_ range: Range<String.Index>, surnames: [String], in text: String) -> Range<String.Index> {
        let matched = String(text[range])
        guard let last = matched.split(whereSeparator: { !$0.isLetter }).last,
              surnames.contains(fold(String(last)))
        else { return range }
        let rest = String(text[range.upperBound...].prefix(60))
        let pattern = #"^[ ](?:(?i:de|del|de la|de las|de los|y)[ ])?\p{Lu}[\p{L}'’]{2,}"#
        guard let found = rest.range(of: pattern, options: .regularExpression) else { return range }
        let word = rest[found].split(separator: " ").last.map(String.init) ?? ""
        // Not a word that starts the next field or sentence.
        let stop: Set<String> = ["dni", "nif", "nie", "calle", "avenida", "avda", "plaza", "expediente", "con", "en", "domicilio"]
        guard !stop.contains(fold(word)) else { return range }
        return range.lowerBound..<text.index(range.upperBound, offsetBy: rest.distance(from: rest.startIndex, to: found.upperBound))
    }

    /// A name match widened over capitalised words hyphenated onto it.
    private static func withHyphenatedSurname(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        var lower = range.lowerBound
        var upper = range.upperBound
        // Forwards: "-Brink".
        while upper < text.endIndex, text[upper] == "-" {
            let next = text.index(after: upper)
            guard next < text.endIndex, text[next].isUppercase else { break }
            var end = next
            while end < text.endIndex, text[end].isLetter { end = text.index(after: end) }
            upper = end
        }
        // Backwards: "Brink-".
        while lower > text.startIndex, text[text.index(before: lower)] == "-" {
            let hyphen = text.index(before: lower)
            var start = hyphen
            while start > text.startIndex, text[text.index(before: start)].isLetter { start = text.index(before: start) }
            guard start < hyphen, text[start].isUppercase else { break }
            lower = start
        }
        return lower..<upper
    }

    // MARK: - Addresses

    /// Street-type words and their abbreviations, folded, to one spelling.
    static let streetTypes: [String: String] = [
        "calle": "calle", "cl": "calle", "c": "calle", "carrer": "calle", "cr": "calle",
        "avenida": "avenue", "avda": "avenue", "av": "avenue", "avenue": "avenue", "ave": "avenue",
        "ulica": "ulica", "ul": "ulica", "osiedle": "osiedle", "os": "osiedle",
        "aleja": "aleja", "al": "aleja", "aleje": "aleja", "plac": "plac", "pl": "plac",
        "cadde": "cadde", "caddesi": "cadde", "cad": "cadde", "cd": "cadde",
        "sokak": "sokak", "sokagi": "sokak", "sok": "sokak", "sk": "sokak",
        "mahalle": "mahalle", "mahallesi": "mahalle", "mah": "mahalle", "mh": "mahalle",
        "bulvar": "bulvar", "bulvari": "bulvar", "blv": "bulvar",
        "street": "street", "st": "street", "road": "road", "rd": "road",
        "lane": "lane", "ln": "lane", "drive": "drive", "dr": "drive",
        "boulevard": "boulevard", "blvd": "boulevard", "bd": "boulevard",
        "rue": "rue", "allee": "allee", "place": "place", "chemin": "chemin", "ch": "chemin",
        "strasse": "str", "str": "str", "straat": "str",
    ]

    private static let polishStreetTypes: Set<String> = ["ulica", "aleja", "osiedle", "plac"]

    /// Street types that may stand in front of a street the reader typed
    /// without them ("ul. Długa" for "Długa"), and are masked with it.
    private static let prefixTypes: Set<String> = [
        "ulica", "osiedle", "aleja", "plac", "calle", "avenue", "rue", "allee", "chemin", "boulevard",
    ]

    /// One spelling for comparing street words: types to their class, and a
    /// compound's "-straße"/"-straat" to "str" ("Bahnhofstr." is
    /// "Bahnhofstraße").
    private static func canonicalStreet(_ token: String) -> String {
        if let type = streetTypes[token] { return type }
        for suffix in ["strasse", "straat"] where token.count > suffix.count && token.hasSuffix(suffix) {
            return String(token.dropLast(suffix.count)) + "str"
        }
        return token
    }

    private static func streetWordMatches(_ found: String, _ wanted: String) -> Bool {
        let a = canonicalStreet(found)
        let b = canonicalStreet(wanted)
        if within(a, b, maxEdits: tolerance(b.count, strong: false)) { return true }
        // An inflected street name ("Piotrkowskiej" for "Piotrkowska"): long
        // words sharing all but their last three letters.
        let common = zip(a, b).prefix { $0 == $1 }.count
        return common >= 6 && common >= max(a.count, b.count) - 3
    }

    private static func streetMatches(street: String, number: String, in text: String, tokens: [Token], polish: Bool, dutch: Bool = false) -> [Range<String.Index>] {
        let wanted = street.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "/" || $0 == "-" }).map { fold(String($0)) }.filter { !$0.isEmpty }
        let digits = String(number.prefix { $0.isNumber })
        guard !wanted.isEmpty, !digits.isEmpty else { return [] }
        let numberCore = digitPattern(digits) + #"(?![\dOolI])"#
        // NL suffix words after a hyphen, a space or nothing: "14-boven",
        // "14 bov.", "14bv", "14 hs", "14-III" (owner, 6 Oct 2026). A lone
        // letter after a space is a suffix only in capitals or before
        // punctuation -- "os. Słoneczne 4 w Kowalach" is a preposition. An
        // apartment number after a space ("3 401", owner 6 Oct 2026), never
        // the digits of a postcode that follows.
        let suffix = #"(?:(?:[ \t]?-[ \t]?|[ \t])?(?:boven|beneden|bov\.|ben\.|bov|ben|bv|bg|hs|huis|zw|rood|bis|ter|[IVX]{1,4}|(?<=[ \t])\d{3,4}(?![ \t]{0,2}[A-Za-z]{2}(?![\p{L}\d]))|\d{1,2}|[A-Za-z]\d{1,3}|(?<=[\d-])[A-Za-z]|(?<=[ \t])(?:(?-i:[A-Z])|[a-z](?=[ \t]*(?:[,.;)\n]|$)|[ \t]{2,}|\t)))(?![\p{L}\d]))"#
        // Flat, floor and door parts: "12/4", "m. 4", "lok. 7", "D: 2",
        // "3º B", "PISO 3 PTA B", "pta. 9", "APT 4B", "Flat 4".
        let unit = #"(?:[ \t]?/[ \t]?\d+[A-Za-z]?(?![\p{L}\d])|,?[ \t]*\d{1,2}\.[ \t]?(?:OG|Etage|Stock|EG|DG|UG)(?:[ \t]+(?:links|rechts|mitte|li\.|re\.))?(?![\p{L}\d])|,?[ \t]*(?:EG|DG|UG|Hochparterre)(?:[ \t]+(?:links|rechts|mitte))?(?![\p{L}\d])|,?[ \t]*(?:Bât\.?|Bâtiment|Appt\.?|Appart\.?|Escalier|Porte|Étage|Logement)[ \t]*[\p{L}\d]{1,4}(?![\p{L}\d])|,?[ \t]*(?:esc\.?|escalera)[ \t]*(?:izquierda|derecha|izq\.?|dcha\.?|dch\.?|[A-Za-z\d]{1,3})(?![\p{L}\d])|,?[ \t]*(?:m\.|lok\.|mieszk\.|d[ \t]?:|daire|kat|apt\.?|apartment|unit|ste\.?|suite|flat|piso|planta|pta\.?|puerta|bajo)[.:]?[ \t]*\d*[ \t]?[ºª°]?(?:[ \t]?[A-Za-z](?![\p{L}\d:]))?(?![\p{L}\d])|,?[ \t]*\d{1,2}\.?[ \t]?[ºª°][ \t]?[A-Za-z]?(?![\p{L}\d])|,?[ \t]*\d{1,2}(?:r|n|t|er|on|a)(?:[ \t]+\d{1,2}(?:a|ª|n|r))?(?![\p{L}\d]))"#
        guard let after = try? NSRegularExpression(
            // A unit is tried before a one-letter suffix, so the "m" of
            // "5 m. 2" and the "D" of "No: 5 D: 2" open their unit rather
            // than end the number.
            pattern: #"^\.?[ \t,]{1,3}(?:(?:No|Nr|Nº|n°)[.:]?[ \t]*)?"# + numberCore + "(?:" + unit + "|" + suffix + "){0,4}",
            options: [.caseInsensitive]
        ),
        let before = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\d])"# + numberCore.replacingOccurrences(of: #"(?![\dOolI])"#, with: "") + #"[A-Za-z]?,?[ \t]{1,3}$"#
        ),
        let trailingUnits = try? NSRegularExpression(pattern: "^(?:" + unit + "){1,3}", options: [.caseInsensitive])
        else { return [] }

        var found: [Range<String.Index>] = []
        // The whole street, or -- after a street type -- its last words
        // ("ul. Chrobrego" for "Bolesława Chrobrego").
        // "Avenida de Carlos III" printed "AVDA. CARLOS III": the street's
        // particles may be left out, so the words are also tried without them.
        let withoutParticles = wanted.filter { !particles.contains($0) }
        let forms = withoutParticles.count < wanted.count && !withoutParticles.isEmpty ? [wanted, withoutParticles] : [wanted]
        for wanted in forms {
        for skip in 0..<wanted.count {
            let sub = Array(wanted[skip...])
            if skip > 0, sub[0].count < 5 { break }
            for index in tokens.indices where index + sub.count <= tokens.count {
                // After a Polish street type, a street word may be in a case
                // form ("ul. Długiej" for "Długa").
                let afterPolishType = polish && index > 0
                    && polishStreetTypes.contains(canonicalStreet(tokens[index - 1].folded))
                var ok = true
                for (offset, word) in sub.enumerated() {
                    let token = tokens[index + offset]
                    if offset > 0, !Token.adjacent(tokens[index + offset - 1], token, in: text, allowing: " \t./-'’") { ok = false; break }
                    // "Pr. Irenelaan" for "Prinses Irenelaan", "Laan v.
                    // Meerdervoort": a street word cut to one to three
                    // letters and a dot.
                    let abbreviated = token.folded.count <= 3 && token.folded.count < word.count
                        && word.hasPrefix(token.folded)
                        && token.range.upperBound < text.endIndex && text[token.range.upperBound] == "."
                    if !(streetWordMatches(token.folded, word) || abbreviated
                         || (afterPolishType && polishForm(token.folded, of: word))) { ok = false; break }
                }
                // Set 4 (owner, 6 Oct 2026): a Dutch street printed with its
                // title or ordinal abbreviated, or its type shortened, where
                // the profile spells it out -- or the other way round.
                var length = sub.count
                if !ok, dutch, skip == 0, let joined = dutchJoinedLength(at: index, wanted: wanted, tokens: tokens, text: text) {
                    ok = true
                    length = joined
                }
                guard ok else { continue }
                var streetStart = tokens[index].range.lowerBound
                let previousIsType = index > 0
                    && prefixTypes.contains(canonicalStreet(tokens[index - 1].folded))
                    && Token.adjacent(tokens[index - 1], tokens[index], in: text, allowing: " ./\t")
                if skip > 0, !previousIsType { continue }
                if previousIsType { streetStart = tokens[index - 1].range.lowerBound }
                var streetEnd = tokens[index + length - 1].range.upperBound

                let rest = String(text[streetEnd...].prefix(60))
                if let match = after.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
                   let whole = Range(match.range, in: rest) {
                    found.append(contentsOf: withBuildingLines(streetStart..<text.index(streetEnd, offsetBy: rest.distance(from: rest.startIndex, to: whole.upperBound)), in: text))
                    continue
                }
                let lineStart = text[..<streetStart].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
                let head = String(text[lineStart..<streetStart])
                if let match = before.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
                   let whole = Range(match.range, in: head) {
                    var offset = head.distance(from: head.startIndex, to: whole.lowerBound)
                    // A building part before the number on the same line:
                    // "Résidence Les Pins, esc. 2, 7 boulevard Victor Hugo".
                    let building = #"(?<![\p{L}])(?:(?:Résidence|Rés\.|Bât\.?|Bâtiment|Immeuble)(?![\p{L}])[^,\n]{0,30}(?:,[ \t]*(?:esc\.?|escalier|bât\.?|appt\.?|porte)[ \t]*[\p{L}\d]{1,4})*|(?<![\p{L}])(?:Apartment|Flat|Apt\.?|Unit|Suite)[ \t]*[\p{L}\d]{1,4}(?:,[ \t]*[\p{L}][\p{L} '’-]{1,40})?),[ \t]*$"#
                    let beforeNumber = String(head[..<whole.lowerBound])
                    if let found = beforeNumber.range(of: building, options: [.regularExpression, .caseInsensitive]) {
                        offset = beforeNumber.distance(from: beforeNumber.startIndex, to: found.lowerBound)
                    }
                    if let units = trailingUnits.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
                       let tail = Range(units.range, in: rest) {
                        streetEnd = text.index(streetEnd, offsetBy: rest.distance(from: rest.startIndex, to: tail.upperBound))
                    }
                    found.append(contentsOf: withBuildingLines(text.index(lineStart, offsetBy: offset)..<streetEnd, in: text))
                }
            }
        }
        }
        // A Turkish neighbourhood printed before the street ("Caferağa Mah.
        // Bahariye Sok. No: 12") belongs to the same address.
        return found.map { withNeighbourhood($0, in: text) }
    }

    /// Dutch street titles, ordinals and particles as letters print them
    /// (owner, 6 Oct 2026), folded, to the words a reader types.
    static let dutchStreetAbbreviations: [String: [String]] = [
        "ds": ["dominee"], "burg": ["burgemeester"], "past": ["pastoor"], "prof": ["professor"],
        "mr": ["meester"], "dr": ["doctor"], "gen": ["generaal"], "kon": ["koning", "koningin"],
        "pres": ["president"], "st": ["sint"], "wethr": ["wethouder"], "weth": ["wethouder"],
        "1e": ["eerste"], "2e": ["tweede"], "3e": ["derde"],
        "v": ["van"], "vd": ["vande", "vander"], "d": ["de", "der"],
    ]

    /// A Dutch street word's type ending, shortened as letters print it:
    /// "-straat" "-str", "-laan" "-ln", "-plein" "-pl", "-gracht" "-gr",
    /// "-kade" "-kd".
    private static func dutchShortType(_ word: String) -> String {
        for (long, short) in [("straat", "str"), ("laan", "ln"), ("plein", "pl"), ("gracht", "gr"), ("kade", "kd")]
        where word.count > long.count && word.hasSuffix(long) {
            return String(word.dropLast(long.count)) + short
        }
        return word
    }

    /// Every spelling of a run of street words, joined without spaces.
    private static func dutchJoined(_ words: [String]) -> Set<String> {
        var joined: Set<String> = [""]
        for word in words {
            let forms = Set(([word] + (dutchStreetAbbreviations[word] ?? [])).map(dutchShortType))
            joined = Set(joined.flatMap { head in forms.map { head + $0 } })
            if joined.count > 64 { break }
        }
        return joined
    }

    /// How many tokens from `index` spell the wanted street, comparing both
    /// sides joined and with abbreviations expanded. Exact: an abbreviation
    /// is not also stretched by edit distance.
    private static func dutchJoinedLength(at index: Int, wanted: [String], tokens: [Token], text: String) -> Int? {
        let target = dutchJoined(wanted)
        for length in 1...(wanted.count + 2) where index + length <= tokens.count {
            if length > 1, !Token.adjacent(tokens[index + length - 2], tokens[index + length - 1], in: text, allowing: " \t./-'’") { return nil }
            // A word cut to one to three letters and a dot stands for the
            // wanted word it begins: "Th." for "Theodor" (owner, 6 Oct 2026).
            let found = dutchJoined(tokens[index..<(index + length)].map { token in
                let dotted = token.range.upperBound < text.endIndex && text[token.range.upperBound] == "."
                guard dotted, token.folded.count <= 3, dutchStreetAbbreviations[token.folded] == nil,
                      let word = wanted.first(where: { $0.count > token.folded.count && $0.hasPrefix(token.folded) })
                else { return token.folded }
                return word
            })
            if !found.isDisjoint(with: target) { return length }
        }
        return nil
    }

    private static func withNeighbourhood(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let head = String(text[lineStart..<range.lowerBound])
        guard let found = head.range(of: #"(?:\p{L}[\p{L}'’-]*[ \t]){1,2}(?:Mah\.|Mahallesi|Mh\.)[ \t]*$"#, options: .regularExpression)
        else { return range }
        return text.index(lineStart, offsetBy: head.distance(from: head.startIndex, to: found.lowerBound))..<range.upperBound
    }

    /// A line of building, staircase or flat parts right above or below the
    /// street line ("Résidence Les Pins, esc. 2", "Bât. C Appt 112") is part
    /// of the same address.
    private static func withBuildingLines(_ range: Range<String.Index>, in text: String) -> [Range<String.Index>] {
        var found = [range]
        // A line that opens with a building word, or one that ends with a
        // flat or room number ("Woonzorgcentrum De Linde, app. 12", "EHPAD
        // Les Glycines, appartement 3", "Flat 12, Granary House").
        let pattern = #"^[ \t]*(?:(?:Résidence|Rés\.|Bât\.?|Bâtiment|Appt\.?|Appartement|Esc\.?|Escalier|Porte|Étage|Entrée|Immeuble|Bloc|Apartment|Flat|Apt\.?|Unit|Suite)(?![\p{L}])[^\n\d]{0,40}(?:\d{1,4}[^\n\d]{0,30}){0,3}|[^\n\d]{2,50}(?:app\.?|appartement|kamer|apt\.?|appt\.?|flat|unit|apartment)[ \t]*\d{1,4}[A-Za-z]?[ \t]*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return found }
        let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[range.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        // Below.
        if lineEnd < text.endIndex {
            let next = text.index(after: lineEnd)
            let nextEnd = text[next...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[next..<nextEnd])
            if regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil, !line.isEmpty {
                found.append(next..<nextEnd)
            }
        }
        // Above.
        if lineStart > text.startIndex {
            let previousEnd = text.index(before: lineStart)
            let previousStart = text[..<previousEnd].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            let line = String(text[previousStart..<previousEnd])
            if regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil, !line.isEmpty {
                found.append(previousStart..<previousEnd)
            } else if let tail = line.range(of: #"(?<![\p{L}])(?i:Flat|Apartment|Apt\.?|Unit|Suite)[ \t]+[\p{L}\d]{1,4},?[ \t]*$"#, options: .regularExpression) {
                // "…for the tenancy at Flat B,\n118 Hyde Park Rd": the flat
                // ends the line above the street (owner, 6 Oct 2026).
                let offset = line.distance(from: line.startIndex, to: tail.lowerBound)
                found.append(text.index(previousStart, offsetBy: offset)..<previousEnd)
            }
        }
        return found
    }

    /// Places with an official second name, either of which a letter may
    /// print on the postcode line (owner, 6 Oct 2026: a short fixed list).
    /// The Frisian municipalities' names are official beside the Dutch ones.
    static let cityAliases: [[String]] = [
        ["Den Haag", "'s-Gravenhage"],
        ["Den Bosch", "'s-Hertogenbosch"],
        ["Leeuwarden", "Ljouwert"],
        ["Sneek", "Snits"],
        ["Harlingen", "Harns"],
        ["Franeker", "Frjentsjer"],
        ["Bolsward", "Boalsert"],
        ["Heerenveen", "It Hearrenfean"],
        ["Joure", "De Jouwer"],
        ["Workum", "Warkum"],
        ["Grou", "Grouw"],
        ["Burgum", "Bergum"],
    ]

    private static func postcodeMatches(_ postcode: String, city: String?, in text: String) -> [Range<String.Index>] {
        let compact = postcode.filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return [] }
        var pattern = #"(?<![\p{L}\d])"#
        for (position, character) in compact.enumerated() {
            if position > 0 { pattern += #"[ \t]{0,2}"# }
            pattern += postcodeCharacter(character)
        }
        pattern += #"(?:-\d{4})?(?![\p{L}\d])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        // The city's words, split on spaces and hyphens ("Beneden-Leeuwen",
        // "'s-Hertogenbosch"), and the same for each official alias.
        let split = { (name: String) in name.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).map { fold(String($0)) }.filter { !$0.isEmpty } }
        let words = city.map(split) ?? []
        let variants: [[String]] = words.isEmpty ? [] : [words] + (cityAliases.first { group in
            group.contains { split($0) == words }
        } ?? []).map(split).filter { $0 != words }
        let digitsOnly = compact.allSatisfy(\.isNumber)

        var confirmed: [Range<String.Index>] = []
        var pending: [Range<String.Index>] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            var start = range.lowerBound
            var end = range.upperBound
            let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            let lineEnd = text[end...].firstIndex(of: "\n") ?? text.endIndex
            let atLineStart = text[lineStart..<range.lowerBound].allSatisfy { $0 == " " || $0 == "\t" }
            var withCity = false
            for words in variants where !withCity {
                // The city right after the postcode on the same line, or
                // after a district and a slash ("06420 Çankaya/ANKARA").
                let rest = String(text[end..<lineEnd])
                let restTokens = Token.all(in: rest)
                let cityAt: Int? = {
                    guard let first = restTokens.first,
                          rest[..<first.range.lowerBound].allSatisfy({ $0 == " " || $0 == "\t" || $0 == "," || $0 == "'" || $0 == "’" })
                    else { return nil }
                    if restTokens.count >= words.count,
                       zip(restTokens, words).allSatisfy({ within($0.folded, $1, maxEdits: tolerance($1.count, strong: false)) }) {
                        return 0
                    }
                    if restTokens.count >= 1 + words.count,
                       rest[restTokens[0].range.upperBound..<restTokens[1].range.lowerBound].trimmingCharacters(in: .whitespaces) == "/",
                       zip(restTokens.dropFirst(), words).allSatisfy({ within($0.folded, $1, maxEdits: tolerance($1.count, strong: false)) }) {
                        return 1
                    }
                    return nil
                }()
                if let cityAt {
                    end = text.index(end, offsetBy: rest.distance(from: rest.startIndex, to: restTokens[cityAt + words.count - 1].range.upperBound))
                    withCity = true
                    // A province or il in brackets after the city ("46500
                    // SAGUNTO (VALENCIA)", "34728 Kadıköy (İstanbul)"; owner,
                    // 6 Oct 2026).
                    let after = String(text[end..<lineEnd])
                    if let bracket = after.range(of: #"^[ \t]*\([^()\n]{1,30}\)"#, options: .regularExpression) {
                        end = text.index(end, offsetBy: after.distance(from: after.startIndex, to: bracket.upperBound))
                    }
                }
                // Or right before it, perhaps with a state ("SPRINGFIELD IL
                // 62704-1234", "London SW1A 1AA").
                let head = String(text[lineStart..<range.lowerBound])
                var headTokens = Token.all(in: head)
                if let last = headTokens.last, last.text.count == 2, last.text.allSatisfy(\.isUppercase), words.count > 0,
                   fold(String(last.text)) != words.last {
                    headTokens.removeLast()
                }
                if headTokens.count >= words.count {
                    let tail = Array(headTokens.suffix(words.count))
                    let between = head[tail.last!.range.upperBound...]
                    if zip(tail, words).allSatisfy({ within($0.folded, $1, maxEdits: tolerance($1.count, strong: false)) }),
                       between.allSatisfy({ $0 == " " || $0 == "\t" || $0 == "," || $0.isUppercase }) {
                        start = text.index(lineStart, offsetBy: head.distance(from: head.startIndex, to: tail[0].range.lowerBound))
                        withCity = true
                    }
                }
            }
            // A postcode of digits alone is also a piece of a phone number,
            // an amount or a reference. It counts with the city beside it,
            // or, with no city in the profile, at the start of a line; and
            // elsewhere only once the letter has shown it with its city, and
            // never between other digit groups.
            if digitsOnly, !(withCity || (words.isEmpty && atLineStart)) {
                pending.append(range)
                continue
            }
            confirmed.append(start..<end)
        }
        if digitsOnly, !confirmed.isEmpty {
            for range in pending where !beside(digitsAround: range, in: text) {
                confirmed.append(range)
            }
        }
        return confirmed
    }

    /// Whether another digit stands within one space of either end.
    private static func beside(digitsAround range: Range<String.Index>, in text: String) -> Bool {
        var before = range.lowerBound
        for _ in 0..<2 where before > text.startIndex {
            before = text.index(before: before)
            if text[before].isNumber { return true }
            if text[before] != " " { break }
        }
        var after = range.upperBound
        for _ in 0..<2 where after < text.endIndex {
            if text[after].isNumber { return true }
            if text[after] != " " { break }
            after = text.index(after: after)
        }
        return false
    }

    /// A postcode character, or what OCR reads for it -- both ways (owner, 6
    /// Oct 2026): 8↔B, 0↔O/D, 5↔S, 1↔I/l, 2↔Z. Only on the postcode pattern.
    private static func postcodeCharacter(_ character: Character) -> String {
        switch character.uppercased().first ?? character {
        case "0": "[0OoD]"
        case "1": "[1lI]"
        case "2": "[2Z]"
        case "5": "[5S]"
        case "8": "[8B]"
        case "B": "[B8]"
        case "O": "[O0]"
        case "D": "[D0]"
        case "S": "[S5]"
        case "I": "[I1l]"
        case "Z": "[Z2]"
        default: NSRegularExpression.escapedPattern(for: String(character))
        }
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

        /// The name inside an elided article, "Inès" of "d'Inès" (French
        /// d', l'). Only those two: "O'Neill" is a surname, not an elision.
        var elided: Token? {
            guard text.count > 2, let first = text.first, "dDlL".contains(first),
                  let apostrophe = text.dropFirst().first, apostrophe == "'" || apostrophe == "’",
                  let rest = Optional(text.dropFirst(2)), rest.first?.isLetter == true
            else { return nil }
            let start = text.index(text.startIndex, offsetBy: 2)
            return Token(range: start..<range.upperBound, text: rest, folded: ProfileMatcher.fold(String(rest)))
        }

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
