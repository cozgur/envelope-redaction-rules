import Foundation

extension NationalIDFormat {
    /// SSN. There is no checksum, so every rule the SSA publishes about which
    /// ranges are never issued lives in the pattern: no area 000, 666 or
    /// 900-999, no group 00, no serial 0000.
    public static let unitedStates = NationalIDFormat(
        country: "US",
        name: "SSN",
        pattern: #"\b(?!000|666|9\d\d)\d{3}[- ]?(?!00)\d{2}[- ]?(?!0000)\d{4}\b"#,
        validate: { NationalIDFormat.digits(of: $0).count == 9 }
    )
}
