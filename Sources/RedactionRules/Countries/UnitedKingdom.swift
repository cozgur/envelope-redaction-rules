import Foundation

extension NationalIDFormat {
    /// National Insurance number. No checksum either; the prefix exclusions in
    /// the pattern are the whole of the validation.
    public static let unitedKingdom = NationalIDFormat(
        country: "GB",
        name: "NINO",
        pattern: #"(?i)\b[ABCEGHJKLMNOPRSTWXYZ][ABCEGHJKLMNPRSTWXYZ]\s?\d{2}\s?\d{2}\s?\d{2}\s?[A-D]\b"#,
        validate: { NationalIDFormat.compacted($0).count == 9 }
    )
}
