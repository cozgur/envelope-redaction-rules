import Foundation

extension NationalIDFormat {
    /// NIR: thirteen digits and a two-digit key. Corsica writes its department
    /// as 2A or 2B, which the key arithmetic treats as 19 and 18.
    public static let france = NationalIDFormat(
        country: "FR",
        name: "NIR",
        pattern: #"\b[12]\d{4}(?:\d{2}|2[AB])\d{6}\s?\d{2}\b"#,
        validate: { candidate in
            let compact = NationalIDFormat.compacted(candidate)
            guard compact.count == 15 else { return false }
            guard let key = Int(compact.suffix(2)) else { return false }
            return Checksums.passesFrenchNIRKey(
                number: String(compact.prefix(13)).uppercased(),
                key: key
            )
        }
    )
}
