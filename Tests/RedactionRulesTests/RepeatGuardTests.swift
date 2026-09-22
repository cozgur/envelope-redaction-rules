import Foundation
import Testing

@testable import RedactionRules

/// The guard on the repeat-occurrence pass.
///
/// That pass takes a value some rule recognised and masks every other
/// appearance of it. Right for a reference quoted four times; catastrophic for
/// a false positive, because a two-letter "reference" is also a word the
/// letter uses thirty times.
@Suite("Repeat guard")
struct RepeatGuardTests {

    /// A rule that claims whatever it is told to, so the guard can be tested
    /// without waiting for a real rule to misfire.
    private struct SeedRule: RedactionRule {
        let kind: PIIKind
        let needle: String

        func matches(in text: String) -> [Range<String.Index>] {
            guard let first = text.range(of: needle) else { return [] }
            return [first]
        }
    }

    private let dutchLetter = """
        Belastingdienst
        Postbus 2508
        6401 DA Heerlen

        Datum: 1 oktober 2026

        Geachte heer/mevrouw,

        De aanslag van de Belastingdienst is vastgesteld. U moet het bedrag
        van EUR 1.240,00 voldoen voor 3 november 2026. De betaling van de
        aanslag kan via de bank.
        """

    // MARK: - The seeded false positive

    @Test("A two-character value is masked once and never spread")
    func shortValueIsNotSpread() {
        // "de" appears eight times in the letter. Claiming it once must not
        // take the other seven with it.
        // Counted as words, not substrings: line wrapping puts a newline
        // after one of them, which a naive substring search misses.
        let occurrences = dutchLetter
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.lowercased() == "de" }
            .count
        #expect(occurrences >= 3, "The fixture needs the word to recur")

        #expect(Stopwords.blocksRepeat("de"))
        #expect(Stopwords.blocksRepeat("De"))
    }

    @Test("Seeding a two-character reference masks no body word")
    func seededShortReferenceMasksNothingElse() {
        let claimed = RedactionEngine.repeatableOccurrenceCount(
            of: "de",
            kind: .reference,
            in: dutchLetter
        )
        #expect(claimed == 0, "A two-character value must not be spread at all")

        // And the prose survives intact: the sentence still reads.
        let result = RedactionEngine.redact(dutchLetter, countryHint: "NL")
        #expect(result.redactedText.contains("De aanslag van de Belastingdienst"))
        #expect(result.redactedText.contains("De betaling van de"))
        #expect(!result.redactedText.contains("[REFERENCE"))
    }

    @Test("Function words are blocked even when long enough", arguments: [
        ("nl", "deze"), ("de", "eines"), ("fr", "cette"), ("es", "estos"),
        ("pl", "przez"), ("tr", "kadar"), ("en", "these"),
    ])
    func stopwordsAreBlockedRegardlessOfLength(language: String, word: String) {
        #expect(word.count >= Stopwords.minimumRepeatableLength,
                "\(word) should be testing the stopword list, not the length rule")
        #expect(Stopwords.blocksRepeat(word), "\(language): \(word) should be blocked")
    }

    @Test("Diacritics and case do not smuggle a stopword past the guard")
    func stopwordMatchingIsInsensitive() {
        #expect(Stopwords.blocksRepeat("FÜR"))
        #expect(Stopwords.blocksRepeat("fur"))
        #expect(Stopwords.blocksRepeat("Icin"))
        #expect(Stopwords.blocksRepeat("için"))
    }

    // MARK: - What the guard must not break

    @Test("Real identifiers are still spread", arguments: [
        "AB-2026-0042", "1234.56.789", "NL91ABNA0417164300", "Yilmaz", "STU-2026-11842",
    ])
    func realValuesAreStillRepeated(value: String) {
        #expect(!Stopwords.blocksRepeat(value), "\(value) must still be spread")
    }

    @Test("A reference quoted three times is masked three times")
    func referenceStillSpreads() {
        let letter = """
            Belastingdienst
            Postbus 2508
            6401 DA Heerlen

            Datum: 1 oktober 2026
            Kenmerk: AB-2026-0042

            Geachte heer/mevrouw,

            Vermeld bij betaling het kenmerk AB-2026-0042. Vragen over
            AB-2026-0042 kunt u stellen via de website.
            """
        let result = RedactionEngine.redact(letter, countryHint: "NL")
        let masked = result.redactedText.components(separatedBy: "[REFERENCE_1]").count - 1

        #expect(masked == 3, "Every occurrence should carry the same placeholder")
        #expect(result.counts[.reference] == 1, "One reference, not three")
    }

    @Test("The guard is exactly four characters wide")
    func boundaryIsWhereItSays() {
        #expect(Stopwords.blocksRepeat("AB1"))
        #expect(!Stopwords.blocksRepeat("AB12"))
    }
}
