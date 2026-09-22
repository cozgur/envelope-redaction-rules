import Foundation

extension NationalIDFormat {
    /// SSN. There is no checksum, so every rule the SSA publishes about which
    /// ranges are never issued lives in the pattern: no area 000, 666 or
    /// 900-999, no group 00, no serial 0000.
    ///
    /// The one exception is deliberate. The SSA reserves 987-65-4320 through
    /// 987-65-4329 for use in advertising, and those fall inside the 9xx range
    /// the rule otherwise refuses. They are matched anyway, because redaction
    /// asks what *looks* identifying, not what the SSA actually issued: a
    /// letter printing "Social Security Number: 987-65-4320" is printing
    /// something every reader and every scraper reads as an SSN. Masking a
    /// number that can never belong to anyone costs nothing, and it lets a
    /// published test corpus use the range the SSA set aside for exactly this.
    ///
    /// The separator is captured and back-referenced so it has to be the same
    /// in both positions. An SSN is written `987-65-4320`, `987 65 4320` or
    /// `987654320`, never half-separated -- and without the back-reference
    /// the pattern read `77341-2026`, the tail of a German insurance policy
    /// number, as `773`+`41`+`2026`. It masked those ten characters and left
    /// the `TK-` in front of them in the clear, under an identity label.
    public static let unitedStates = NationalIDFormat(
        country: "US",
        name: "SSN",
        pattern: #"\b(?:987([- ]?)65\1432\d|(?!000|666|9\d\d)\d{3}([- ]?)(?!00)\d{2}\2(?!0000)\d{4})\b"#,
        validate: { NationalIDFormat.digits(of: $0).count == 9 }
    )
}
