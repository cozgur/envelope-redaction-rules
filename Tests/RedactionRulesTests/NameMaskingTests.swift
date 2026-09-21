import Foundation
import Testing

@testable import RedactionRules

/// Name masking: the recipient block, the salutation, and the two ways both
/// go wrong.
@Suite("Name masking")
struct NameMaskingTests {

    // MARK: - Fixtures

    struct GenericSalutation: Decodable, Sendable, CustomTestStringConvertible {
        var id: String
        var language: String
        var salutation: String
        var text: String
        var testDescription: String { id }
    }

    struct LetterheadCase: Decodable, Sendable, CustomTestStringConvertible {
        var id: String
        var country: String
        var letterhead: String
        var recipient: String
        var text: String
        var testDescription: String { id }
    }

    struct RecurrenceCase: Decodable, Sendable, CustomTestStringConvertible {
        var id: String
        var country: String
        var name: String
        var occurrences: Int
        var text: String
        var testDescription: String { id }
    }

    private static func load<T: Decodable>(_ type: [T].Type, from name: String) -> [T] {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([T].self, from: data)
        else { return [] }
        return decoded
    }

    private static let genericSalutations = load([GenericSalutation].self, from: "generic-salutations")
    private static let letterheadCases = load([LetterheadCase].self, from: "letterhead-blocks")
    private static let recurrenceCases = load([RecurrenceCase].self, from: "name-recurrence")

    @Test("The fixtures are present")
    func fixturesLoad() {
        #expect(Self.genericSalutations.count >= 14, "Two generic salutations per language")
        #expect(Set(Self.genericSalutations.map(\.language)).count == 7)
        #expect(Self.letterheadCases.count >= 3)
        #expect(Self.recurrenceCases.count >= 3)
    }

    // MARK: - Salutation

    @Test("A personal salutation yields the name, honorific intact", arguments: [
        ("nl", "Geachte mevrouw Yilmaz,", "Yilmaz"),
        ("nl", "Geachte heer Yilmaz,", "Yilmaz"),
        ("de", "Sehr geehrte Frau Yilmaz,", "Yilmaz"),
        ("de", "Sehr geehrter Herr Yilmaz,", "Yilmaz"),
        ("fr", "Madame Yilmaz,", "Yilmaz"),
        ("es", "Estimada señora Yilmaz:", "Yilmaz"),
        ("es", "Estimado Sr. Yilmaz:", "Yilmaz"),
        ("pl", "Szanowna Pani Yilmaz,", "Yilmaz"),
        ("tr", "Sayın Yilmaz,", "Yilmaz"),
        ("en", "Dear Ms Yilmaz,", "Yilmaz"),
        ("en", "Dear Mr. Yilmaz,", "Yilmaz"),
    ])
    func personalSalutationYieldsName(language: String, line: String, expected: String) throws {
        let template = try #require(SalutationTemplate.all.first { $0.language == language })
        let range = try #require(template.name(in: line), "\(line) should name someone")
        #expect(String(line[range]) == expected)

        // The honorific survives: an explanation reads better addressed to
        // "mevrouw [NAME_1]" than to nobody.
        let masked = line.replacingCharacters(in: range, with: "[NAME_1]")
        #expect(masked.hasPrefix(String(line.prefix(upTo: range.lowerBound))))
        #expect(masked.contains("[NAME_1]"))
    }

    @Test("A generic salutation yields nothing", arguments: genericSalutations)
    func genericSalutationYieldsNothing(fixture: GenericSalutation) throws {
        // Against every template, not just its own language: a Dutch pattern
        // must not fire on a Polish opening either.
        for template in SalutationTemplate.all {
            #expect(
                template.name(in: fixture.salutation) == nil,
                "\(fixture.id): \(template.language) read a name in \(fixture.salutation)"
            )
        }

        let result = RedactionEngine.redact(fixture.text, countryHint: nil)
        #expect(
            result.counts[.name] == nil,
            "\(fixture.id): masked \(result.counts[.name] ?? 0) names in a letter that named nobody"
        )
        #expect(!result.redactedText.contains("[NAME"))
    }

    // MARK: - Recipient block

    @Test("The recipient block is masked whole and the letterhead is not",
          arguments: letterheadCases)
    func letterheadSurvivesRecipientMasking(fixture: LetterheadCase) {
        let result = RedactionEngine.redact(fixture.text, countryHint: fixture.country)

        // The whole recipient block goes, name line included.
        for line in fixture.recipient.components(separatedBy: "\n") {
            #expect(
                !result.redactedText.contains(line),
                "\(fixture.id): recipient line survived: \(line)"
            )
        }
        #expect(result.map.values.contains(fixture.recipient),
                "\(fixture.id): the block should be masked as one value")

        // The sender's letterhead stays readable. Masking it would delete the
        // one thing the explanation most needs to know: who wrote.
        for line in fixture.letterhead.components(separatedBy: "\n") {
            #expect(
                result.redactedText.contains(line),
                "\(fixture.id): letterhead line was masked: \(line)"
            )
        }
    }

    @Test("A masked block restores with its newlines", arguments: letterheadCases)
    func blockRestoresExactly(fixture: LetterheadCase) {
        let result = RedactionEngine.redact(fixture.text, countryHint: fixture.country)
        #expect(RedactionEngine.restore(result.redactedText, map: result.map) == fixture.text)

        #expect(
            result.map.values.contains { $0 == fixture.recipient && $0.contains("\n") },
            "\(fixture.id): the block should be masked as one multi-line value"
        )
    }

    // MARK: - Recurrence

    @Test("A name found once is masked everywhere", arguments: recurrenceCases)
    func recurringNameIsMaskedEverywhere(fixture: RecurrenceCase) {
        let result = RedactionEngine.redact(fixture.text, countryHint: fixture.country)

        #expect(
            !result.redactedText.contains(fixture.name),
            "\(fixture.id): \(fixture.name) survived somewhere in the body"
        )

        // Every occurrence carries the same placeholder: one person, one mask.
        let placeholder = PIIKind.name.placeholder(index: 1)
        let count = result.redactedText.components(separatedBy: placeholder).count - 1
        #expect(
            count >= fixture.occurrences,
            "\(fixture.id): \(count) masked occurrences, expected at least \(fixture.occurrences)"
        )
        #expect(result.counts[.name] == 1, "One name, not several")
    }

    @Test("Recurrence fixtures restore exactly", arguments: recurrenceCases)
    func recurrenceRestores(fixture: RecurrenceCase) {
        let result = RedactionEngine.redact(fixture.text, countryHint: fixture.country)
        #expect(RedactionEngine.restore(result.redactedText, map: result.map) == fixture.text)
    }

    // MARK: - Structure

    @Test("The letterhead is the first block and the recipient the next")
    func structureFindsBothBlocks() throws {
        let fixture = try #require(Self.letterheadCases.first)
        let structure = LetterStructure(fixture.text)

        #expect(structure.blocks.count >= 3)
        #expect(structure.blocks[0].text == fixture.letterhead)
        #expect(structure.recipientCandidates.map(\.text) == [fixture.recipient])
        #expect(structure.letterheadRange != nil)
        #expect(structure.salutationLine != nil)
    }

    @Test("A letter with no recipient block masks no block")
    func noRecipientBlock() {
        // A portal download opens straight into the machinery. Nothing here
        // is a recipient block, and inventing one would mask the letterhead.
        let text = """
        Belastingdienst

        Datum: 1 oktober 2026
        Kenmerk: 1234.56.789

        Geachte heer/mevrouw,

        U moet EUR 1.240,00 betalen voor 3 november 2026.
        """
        let structure = LetterStructure(text)
        #expect(structure.recipientCandidates.isEmpty)

        let result = RedactionEngine.redact(text, countryHint: "NL")
        #expect(result.counts[.address] == nil)
        #expect(result.counts[.name] == nil)
        #expect(result.redactedText.contains("Belastingdienst"))
    }
}
