import Foundation

extension NationalIDFormat {
    /// Burgerservicenummer: nine digits, validated by the *elfproef*.
    ///
    /// Roughly one random nine-digit run in eleven passes, so the checksum
    /// narrows the field without being decisive on its own. That is why phone
    /// detection runs first and why a keyword-anchored fallback exists.
    public static let netherlands = NationalIDFormat(
        country: "NL",
        name: "BSN",
        pattern: #"\b\d{9}\b"#,
        validate: { Checksums.passesDutchElevenTest(NationalIDFormat.digits(of: $0)) }
    )
}
