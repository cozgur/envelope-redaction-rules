import Foundation

extension NationalIDFormat {
    /// DNI (eight digits) or NIE (X, Y or Z then seven), each closed by a
    /// control letter drawn from the number modulo 23.
    public static let spain = NationalIDFormat(
        country: "ES",
        name: "DNI/NIE",
        pattern: #"\b(?:[XYZxyz][- ]?\d{7}|\d{8})[- ]?[A-Za-z]\b"#,
        validate: { candidate in
            let compact = NationalIDFormat.compacted(candidate)
            guard let letter = compact.last, letter.isLetter else { return false }
            return Checksums.passesSpanishControlLetter(
                number: String(compact.dropLast()),
                letter: letter
            )
        }
    )
}
