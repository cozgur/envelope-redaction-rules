import Foundation

extension NationalIDFormat {
    /// PESEL: eleven digits closed by a weighted check digit.
    public static let poland = NationalIDFormat(
        country: "PL",
        name: "PESEL",
        pattern: #"\b\d{11}\b"#,
        validate: { Checksums.passesPESEL(NationalIDFormat.digits(of: $0)) }
    )
}
