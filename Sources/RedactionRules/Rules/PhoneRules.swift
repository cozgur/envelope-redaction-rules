import Foundation

/// Finds phone numbers written in formats `NSDataDetector` does not recognise.
///
/// The system detector is good at numbers carrying a country code and poor at
/// the way European letters actually print them -- `069 910 10000`,
/// `030 2093 70333` -- which are the overwhelming majority in this corpus.
/// This rule fills that gap with a grouped-digit pattern, and runs after the
/// detector so the detector's better-typed matches win where it has one.
///
/// It requires at least nine digits, which is what keeps it away from
/// deadlines, amounts and short reference numbers. Service numbers shorter
/// than that are handled by the keyword rule instead, because three digits on
/// their own are indistinguishable from any other three digits.
public struct PhoneNumberPatternRule: RedactionRule {
    public let kind = PIIKind.phone

    public init() {}

    /// Two to five groups of digits separated by spaces, hyphens or dots,
    /// optionally led by a country code.
    private static let pattern =
        #"(?:\+\d{1,3}[ .-]?)?\(?\d{2,5}\)?(?:[ .-]\d{2,6}){1,4}"#

    public func matches(in text: String) -> [Range<String.Index>] {
        RegexScanner.ranges(of: Self.pattern, in: text).filter { range in
            let digits = text[range].filter(\.isNumber).count
            return (9...15).contains(digits)
        }
    }
}

/// Finds short service numbers by the word that introduces them.
///
/// `189`, `3646`, `311`: too short for any pattern to claim safely, and
/// unmistakable once a letter has written "call" in front of them.
public struct PhoneKeywordRule: RedactionRule {
    public let kind = PIIKind.phone

    public init() {}

    /// Words that introduce a number to ring.
    ///
    /// A keyword list, unlike the reference rule's stems, because contact
    /// phrasing is a genuinely small closed set per language while reference
    /// labels are invented fresh by every authority.
    ///
    /// Whole words, and inflections listed rather than stemmed. A `call`
    /// *prefix* would match the Spanish "Calle Mayor 12" and read the house
    /// number as a phone number; bare prepositions like `al` and `au` match
    /// the Polish street prefix "Al." and the inside of "Estatal" and
    /// "Mahallesi". Both cost a sender's letterhead, which must survive.
    ///
    /// Long numbers are found by ``PhoneNumberPatternRule`` regardless. This
    /// rule exists for the short service numbers -- 189, 311, 3975 -- that no
    /// pattern can claim safely on its own.
    private static let keywords = [
        // Generic
        "tel", "tel.", "telephone", "phone", "call", "calling", "called",
        "contact", "contact us on", "reached at", "contacted on", "enquiries",
        "question", "questions", "questions au",
        // Dutch
        "bel", "belt", "via", "telefoon", "telefonisch", "vragen",
        // German
        "unter", "rufen", "rückfragen", "rueckfragen", "auskünfte",
        "auskuenfte", "telefon",
        // French
        "appelez le", "appelez", "contactez le", "téléphone",
        "renseignements au", "informations au", "rendez-vous au",
        // Spanish
        "llame al", "llamar al", "en el", "información en el",
        "consultas en el", "teléfono",
        // Polish
        "numerem", "pod numerem", "pytania", "zadzwoń", "telefoniczny",
        "telefonicznie",
        // Turkish
        "için", "arayabilirsiniz", "arayarak", "arayın", "bilgi için",
    ]

    /// The number itself: either a group of three or more digits, or a
    /// two-digit group followed by a group of at least three.
    ///
    /// The second alternative exists for the Dutch municipal short numbers --
    /// `14 020`, `14 010` -- where the service prefix is two digits and the
    /// area code follows. Without it the rule claimed the `020` and left the
    /// `14` beside it, which masks a phone number into something that is
    /// still recognisably that phone number.
    ///
    /// A bare two-digit group leading a two-digit group is deliberately not
    /// matched: `bereikbaar van 09.00 tot 17.00 uur` is opening hours, and a
    /// letter that lost its opening hours to the phone rule is worse than one
    /// that kept a two-digit prefix.
    private static let numberPattern =
        #"(\d{3,8}(?:[ .-]\d{2,6}){0,3}|\d{2}[ .-]\d{3,6}(?:[ .-]\d{2,6}){0,2})"#

    private static var pattern: String {
        return "(?i)" + KeywordPattern.alternation(keywords)
            + #"[^\n]{0,24}?(?<![\w./-])"# + numberPattern + #"(?![\w/-])"#
    }

    /// Words that follow the number instead of introducing it.
    ///
    /// Turkish puts the verb last: a letter says "189 numaralı hattı
    /// arayabilir", never "call 189". A rule that only looks to the left of a
    /// number cannot see a Turkish phone number at all.
    private static let trailingKeywords = [
        "numaralı", "numarali", "numarasını", "numarasini", "numarayı",
        "numarayi", "nolu", "hattı", "hatti", "arayarak", "arayabilir",
        "arayınız", "arayiniz",
    ]

    private static var trailingPattern: String {
        return #"(?i)(?<![\w./-])"# + numberPattern + #"(?![\w/-])[^\n]{0,24}?"#
            + KeywordPattern.alternation(trailingKeywords)
    }

    public func matches(in text: String) -> [Range<String.Index>] {
        RegexScanner.ranges(of: Self.pattern, captureGroup: 1, in: text)
            + RegexScanner.ranges(of: Self.trailingPattern, captureGroup: 1, in: text)
    }
}
