import Foundation

extension NationalIDFormat {
    /// Steuer-Identifikationsnummer: eleven digits, ISO 7064 MOD 11,10, with
    /// the repeated-digit rule that rejects runs like 12345678901.
    public static let germany = NationalIDFormat(
        country: "DE",
        name: "Steuer-IdNr",
        pattern: #"\b\d{11}\b"#,
        validate: { Checksums.passesISO7064Mod11_10(NationalIDFormat.digits(of: $0)) }
    )
}
