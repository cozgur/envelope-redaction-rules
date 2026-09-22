import Foundation

/// Words that can never be a masked value, whatever a rule thinks it found.
///
/// The repeat-occurrence pass takes a value some rule recognised and masks
/// every other appearance of it in the letter. That is right for a reference
/// quoted four times and catastrophic for a false positive: a rule that once
/// returned the Spanish article "de" had the engine replace every "de" in the
/// letter, leaving prose no explanation could read.
///
/// The pattern that caused it has since been tightened, so this is defence in
/// depth rather than the fix. It is worth having because the failure is silent
/// and total: nothing about a redacted letter says which of its words used to
/// be ordinary.
///
/// Articles, prepositions and conjunctions across the seven UI languages,
/// matched case- and diacritic-insensitively. A real reference, identity
/// number or IBAN is none of these in any language.
enum Stopwords {
    /// Values shorter than this are never spread by the repeat pass.
    ///
    /// Four characters, because every identifier this engine masks is longer
    /// and almost every function word is shorter. The cost is a surname of two
    /// or three letters -- Li, Ng, Wu -- whose *recurrences* in the body are
    /// left alone; the salutation itself is still masked, because that is a
    /// direct rule match rather than a repeat. That trade is deliberate: a
    /// short name surviving in one sentence is a smaller harm than every
    /// article in the letter being replaced.
    static let minimumRepeatableLength = 4

    /// True when `value` must not be spread across the letter.
    static func blocksRepeat(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < minimumRepeatableLength { return true }
        return all.contains { candidate in
            trimmed.compare(candidate, options: [.caseInsensitive, .diacriticInsensitive])
                == .orderedSame
        }
    }

    /// Every function word, in one set. The engine knows the letter's country,
    /// not reliably its language, and a word that is a stopword anywhere is
    /// never an identifier.
    static let all: Set<String> = dutch
        .union(german).union(french).union(spanish)
        .union(polish).union(turkish).union(english)

    static let dutch: Set<String> = [
        "de", "het", "een", "en", "of", "maar", "van", "voor", "met", "aan",
        "bij", "uit", "door", "over", "tot", "naar", "in", "op", "om", "dat",
        "die", "deze", "dit", "is", "zijn", "wordt", "worden", "niet", "ook",
        "als", "wij", "ons", "onze", "uw",
    ]

    static let german: Set<String> = [
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen",
        "einem", "eines", "einer", "und", "oder", "aber", "in", "an", "auf",
        "für", "mit", "von", "vom", "zu", "zum", "zur", "bei", "nach", "über",
        "aus", "ist", "sind", "wird", "werden", "nicht", "auch", "dass", "wir",
        "sie", "ihr", "ihre", "ihrer", "ihren",
    ]

    static let french: Set<String> = [
        "le", "la", "les", "un", "une", "des", "du", "de", "et", "ou", "mais",
        "en", "dans", "sur", "pour", "avec", "par", "au", "aux", "ce", "cet",
        "cette", "ces", "il", "elle", "nous", "vous", "est", "sont", "ne",
        "pas", "que", "qui", "votre", "vos", "notre", "nos",
    ]

    static let spanish: Set<String> = [
        "el", "la", "los", "las", "un", "una", "unos", "unas", "de", "del",
        "al", "y", "o", "pero", "en", "con", "por", "para", "su", "sus", "es",
        "son", "no", "que", "se", "lo", "este", "esta", "estos", "estas",
        "como", "más",
    ]

    static let polish: Set<String> = [
        "i", "w", "we", "na", "do", "z", "ze", "od", "po", "za", "o", "u",
        "przez", "dla", "jest", "są", "nie", "to", "ten", "ta", "te", "tego",
        "oraz", "ale", "że", "się", "jako", "przy", "pod", "bez",
    ]

    static let turkish: Set<String> = [
        "ve", "veya", "ile", "için", "bir", "bu", "şu", "da", "de", "ki",
        "ama", "fakat", "gibi", "kadar", "daha", "çok", "en", "var", "yok",
        "olan", "olarak", "ise", "göre", "sonra", "önce",
    ]

    static let english: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "with", "by", "from", "of", "is", "are", "was", "were", "be", "been",
        "this", "that", "these", "those", "we", "you", "your", "our", "not",
        "as", "it", "its", "will", "may", "must",
    ]
}
