import Foundation

/// Checksum algorithms shared by the national identity rules.
///
/// Validation is what separates an identity number from a digit run that
/// merely looks like one. Without it the engine would mask deadlines, amounts
/// and invoice totals, which is the one failure mode worse than leaking: a
/// letter whose numbers are gone cannot be explained at all.
public enum Checksums {
    /// Luhn, for card numbers.
    public static func passesLuhn(_ digits: [Int]) -> Bool {
        guard digits.count >= 12 else { return false }
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum.isMultiple(of: 10)
    }

    /// The Dutch *elfproef*, for a BSN.
    ///
    /// Nine digits weighted 9…2 with the last weighted -1; the total must
    /// divide by eleven.
    public static func passesDutchElevenTest(_ digits: [Int]) -> Bool {
        guard digits.count == 9 else { return false }
        guard digits.contains(where: { $0 != 0 }) else { return false }
        var sum = 0
        for (index, digit) in digits.enumerated() {
            sum += digit * (index == 8 ? -1 : 9 - index)
        }
        return sum.isMultiple(of: 11)
    }

    /// ISO 7064 MOD 11,10, for a German Steuer-Identifikationsnummer.
    public static func passesISO7064Mod11_10(_ digits: [Int]) -> Bool {
        guard digits.count == 11, digits[0] != 0 else { return false }

        // In the first ten digits exactly one digit repeats, and it repeats
        // at most three times. This is what rejects runs like 12345678901.
        var occurrences: [Int: Int] = [:]
        for digit in digits.prefix(10) {
            occurrences[digit, default: 0] += 1
        }
        let repeated = occurrences.filter { $0.value > 1 }
        guard repeated.count == 1, let count = repeated.first?.value, count <= 3 else {
            return false
        }

        var product = 10
        for digit in digits.prefix(10) {
            var sum = (digit + product) % 10
            if sum == 0 { sum = 10 }
            product = (sum * 2) % 11
        }
        let check = (11 - product) % 10
        return check == digits[10]
    }

    /// The French NIR key: the first thirteen digits, checked by the last two.
    public static func passesFrenchNIRKey(number: String, key: Int) -> Bool {
        // Corsica writes its department as 2A or 2B, which the key treats as
        // 19 and 18.
        let normalised = number
            .replacingOccurrences(of: "2A", with: "19")
            .replacingOccurrences(of: "2B", with: "18")
        guard let value = Int(normalised) else { return false }
        return key == 97 - (value % 97)
    }

    /// The Polish PESEL check digit.
    public static func passesPESEL(_ digits: [Int]) -> Bool {
        guard digits.count == 11 else { return false }
        let weights = [1, 3, 7, 9, 1, 3, 7, 9, 1, 3]
        let sum = zip(digits.prefix(10), weights).reduce(0) { $0 + $1.0 * $1.1 }
        return (10 - sum % 10) % 10 == digits[10]
    }

    /// The Turkish TC Kimlik No check digits.
    public static func passesTCKN(_ digits: [Int]) -> Bool {
        guard digits.count == 11, digits[0] != 0 else { return false }
        let odd = [0, 2, 4, 6, 8].reduce(0) { $0 + digits[$1] }
        let even = [1, 3, 5, 7].reduce(0) { $0 + digits[$1] }
        guard (odd * 7 - even) % 10 == digits[9] else { return false }
        return digits.prefix(10).reduce(0, +) % 10 == digits[10]
    }

    /// IBAN mod-97, per ISO 13616.
    public static func passesIBANMod97(_ iban: String) -> Bool {
        let compact = iban.replacingOccurrences(of: " ", with: "").uppercased()
        guard (15...34).contains(compact.count) else { return false }
        guard compact.prefix(2).allSatisfy(\.isLetter),
              compact.dropFirst(2).prefix(2).allSatisfy(\.isNumber) else { return false }

        let rearranged = compact.dropFirst(4) + compact.prefix(4)
        var remainder = 0
        for character in rearranged {
            let chunk: String
            if let digit = character.wholeNumberValue, character.isNumber {
                chunk = String(digit)
            } else if character.isLetter, let ascii = character.asciiValue {
                chunk = String(Int(ascii - 65) + 10)
            } else {
                return false
            }
            for scalar in chunk {
                guard let value = scalar.wholeNumberValue else { return false }
                remainder = (remainder * 10 + value) % 97
            }
        }
        return remainder == 1
    }

    /// The Spanish DNI/NIE control letter.
    public static func passesSpanishControlLetter(number: String, letter: Character) -> Bool {
        let table = Array("TRWAGMYFPDXBNJZSQVHLCKE")
        var digits = number.uppercased()
        // NIE prefixes stand in for a leading digit.
        if let first = digits.first, "XYZ".contains(first) {
            let replacement = String("XYZ".distance(from: "XYZ".startIndex,
                                                    to: "XYZ".firstIndex(of: first)!))
            digits = replacement + digits.dropFirst()
        }
        guard let value = Int(digits) else { return false }
        return table[value % 23] == Character(letter.uppercased())
    }
}
