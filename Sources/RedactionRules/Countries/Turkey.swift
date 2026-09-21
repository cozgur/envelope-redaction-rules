import Foundation

extension NationalIDFormat {
    /// T.C. Kimlik No: eleven digits, first non-zero, closed by two check
    /// digits derived from the other nine.
    public static let turkey = NationalIDFormat(
        country: "TR",
        name: "TCKN",
        pattern: #"\b[1-9]\d{10}\b"#,
        validate: { Checksums.passesTCKN(NationalIDFormat.digits(of: $0)) }
    )
}
