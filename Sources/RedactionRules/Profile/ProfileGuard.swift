import Foundation

/// The boundary check's half for the reader's own details (redaction v2 plan
/// §1, "MaskLeakGuard and L1").
///
/// The app's guard refuses a body that still holds any original from the
/// redaction map. With a profile it must also refuse a body that holds the
/// reader's own details -- L1 missed a spelling that is exactly theirs -- but
/// under the same precision guards as L1, because the guard is an exact
/// match and an exact match on "Bakker" would stop "de bakker op de hoek":
///
/// - the street only with its house number, in each suffix form;
/// - a surname that is an ordinary word or place, or under four letters,
///   only with initials or a given name; other surnames alone too;
/// - the postcode with and without its space;
/// - the reader's aliases.
///
/// Folded as L1 folds, and matched on word and digit boundaries, so
/// "Kerkstraat 5" is not found in "Kerkstraat 51" or "Kerkstraat 120".
public enum ProfileGuard {

    /// The values a body must not contain, folded.
    public static func values(for profile: RedactionProfile) -> [String] {
        var values: Set<String> = []
        for person in [profile.person] + profile.household {
            let surname = ProfileMatcher.fold(person.surname).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard !surname.isEmpty else { continue }
            let given = (person.givenNames ?? "").split(whereSeparator: { $0.isWhitespace }).map { ProfileMatcher.fold(String($0)) }
            let initials = given.compactMap(\.first).map(String.init)
            if !initials.isEmpty {
                values.insert(initials.map { $0 + "." }.joined() + " " + surname)
                values.insert(initials.map { $0 + "." }.joined(separator: " ") + " " + surname)
                values.insert(initials.joined(separator: " ") + " " + surname)
                values.insert("\(initials[0]). \(surname)")
                values.insert("\(initials[0]) \(surname)")
            }
            for name in given { values.insert("\(name) \(surname)") }
            if !given.isEmpty { values.insert(given.joined(separator: " ") + " " + surname) }
            if !ProfileMatcher.isAmbiguousAlone(person.surname) {
                values.insert(surname)
                for core in surname.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
                where core.count >= 4 && !ProfileMatcher.particles.contains(core) && !ProfileMatcher.isAmbiguousAlone(core) {
                    values.insert(core)
                }
            }
        }
        if let street = profile.street, let number = profile.houseNumber {
            let street = ProfileMatcher.fold(street)
            let digits = String(number.prefix { $0.isNumber })
            let suffix = ProfileMatcher.fold(String(number.dropFirst(digits.count))).trimmingCharacters(in: CharacterSet(charactersIn: " -"))
            if !digits.isEmpty {
                values.insert("\(street) \(digits)")
                if !suffix.isEmpty {
                    for joiner in ["-", " ", ""] { values.insert("\(street) \(digits)\(joiner)\(suffix)") }
                }
            }
        }
        if let postcode = profile.postcode {
            let folded = ProfileMatcher.fold(postcode)
            values.insert(folded)
            values.insert(folded.filter { !$0.isWhitespace })
        }
        for alias in profile.aliases where alias.text.count >= 3 {
            values.insert(ProfileMatcher.fold(alias.text).split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))
        }
        return values.filter { $0.count >= 3 }.sorted()
    }

    /// The profile values `body` still holds, on word and digit boundaries.
    public static func hits(in body: String, profile: RedactionProfile) -> [String] {
        let folded = ProfileMatcher.fold(body).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return values(for: profile).filter { value in
            let pattern = #"(?<![\p{L}\d])"# + NSRegularExpression.escapedPattern(for: value) + #"(?![\p{L}\d])"#
            return folded.range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// Where in `body` the hits are, in its own characters: what the app
    /// masks before taking the reader to the preview (plan §1, a profile hit
    /// is not an error screen). Longest first where two overlap.
    public static func ranges(in body: String, profile: RedactionProfile) -> [Range<String.Index>] {
        // The body folded one character at a time, whitespace runs collapsed,
        // with each folded character's origin kept.
        var folded = ""
        var origins: [String.Index] = []
        var lastWasSpace = false
        for index in body.indices {
            let character = body[index]
            if character.isWhitespace {
                if !lastWasSpace { folded.append(" "); origins.append(index) }
                lastWasSpace = true
                continue
            }
            lastWasSpace = false
            for piece in ProfileMatcher.fold(String(character)) {
                folded.append(piece)
                origins.append(index)
            }
        }
        let characters = Array(folded)
        var found: [Range<String.Index>] = []
        for value in hits(in: body, profile: profile).sorted(by: { $0.count > $1.count }) {
            let pattern = #"(?<![\p{L}\d])"# + NSRegularExpression.escapedPattern(for: value) + #"(?![\p{L}\d])"#
            var search = folded.startIndex
            while let match = folded.range(of: pattern, options: .regularExpression, range: search..<folded.endIndex) {
                let lower = folded.distance(from: folded.startIndex, to: match.lowerBound)
                let upper = folded.distance(from: folded.startIndex, to: match.upperBound)
                search = match.upperBound
                guard upper > lower, upper <= characters.count else { continue }
                let range = origins[lower]..<body.index(after: origins[upper - 1])
                if !found.contains(where: { $0.overlaps(range) }) { found.append(range) }
            }
        }
        return found.sorted { $0.lowerBound < $1.lowerBound }
    }
}
