import Foundation

extension NationalIDFormat {
    /// National Insurance number. No checksum either; the prefix exclusions
    /// are the whole of the validation.
    ///
    /// `QQ` is admitted on purpose. HMRC never issues a prefix beginning with
    /// Q, which is why government test data uses QQ123456C, and which is also
    /// why the general rule would reject it. It is matched for the same reason
    /// the American advertising range is: a string shaped exactly like a NINO
    /// reads as one, and masking a prefix that can never be issued costs
    /// nothing while letting a published corpus stay safe.
    public static let unitedKingdom = NationalIDFormat(
        country: "GB",
        name: "NINO",
        pattern: #"(?i)\b(?:QQ|[ABCEGHJKLMNOPRSTWXYZ][ABCEGHJKLMNPRSTWXYZ])\s?\d{2}\s?\d{2}\s?\d{2}\s?[A-D]\b"#,
        validate: { NationalIDFormat.compacted($0).count == 9 }
    )
}
