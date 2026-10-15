import Foundation

/// Whether a phone number, an email address or an IBAN in a letter is the
/// reader's, read from the words around it.
///
/// A letter's contact details and payment account are the sender's: "call
/// us on", "pay into account", "write to". The reader's appear with a
/// possessive -- "your account NL91...", "uw telefoonnummer", "Ihre IBAN",
/// "votre compte", "TR... numaralı hesabınıza". Only those are masked by the
/// rules; the reader's own values are also caught by the profile (L1)
/// whatever the sentence says.
public enum ReaderOwnership {
    /// The kinds this decides for. Names, addresses, ID numbers and
    /// references are the rules' to decide as before.
    public static let kinds: Set<PIIKind> = [.phone, .email, .iban]

    /// How far either side of the value the possessive may sit, in
    /// characters, within the same line.
    static let before = 48
    static let after = 28

    /// Possessives and second-person forms, lowercased, matched as whole
    /// words before the value.
    static let cuesBefore: [String] = [
        // EN
        "your",
        // NL
        "uw", "je", "jouw",
        // DE
        "ihr", "ihre", "ihrem", "ihren", "ihrer", "ihres", "dein", "deine", "deinem", "deinen",
        // FR
        "votre", "vos", "ton", "ta", "tes",
        // ES
        "su", "sus", "tu", "tus",
        // IT
        "suo", "sua", "vostro", "vostra",
        // PL
        "pana", "pani", "państwa", "twój", "twoje", "twojego", "twojej",
        // TR
        "sizin", "senin",
    ]

    /// Turkish (and similar) put the possessive after the value as a
    /// suffix: "TR... numaralı hesabınıza". Matched as word prefixes after.
    static let cuesAfter: [String] = [
        "hesabınız", "hesabın", "numaranız", "numaran", "telefonunuz", "telefonun",
        "adresiniz", "adresin", "e-posta adresiniz",
    ]

    /// Words that say a number on the line is a telephone number.
    static let phoneCues: [String] = [
        "tel", "telefoon", "telefoonnummer", "telefonisch", "telefonische", "bereikbaar", "bel", "bellen", "phone", "telephone", "call", "ring",
        "telefon", "telefonnummer", "rufnummer", "anrufen", "téléphone", "tél", "appelez", "appeler",
        "teléfono", "llame", "telefono", "chiami", "telefonu", "arayın", "arayabilirsiniz", "ara",
        "infolijn", "klantenservice", "helpdesk", "hotline", "fax", "whatsapp", "gsm", "mobiel",
    ]

    /// Whether the number reads as a telephone number: a cue on its line, or
    /// a leading "+" or "00".
    public static func saysPhone(_ range: Range<String.Index>, in text: String) -> Bool {
        let value = text[range]
        if value.hasPrefix("+") || value.hasPrefix("00") { return true }
        let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[range.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        let line = words(text[lineStart..<lineEnd])
        return line.contains { word in phoneCues.contains(word) }
    }

    /// Words just before a number that make it a reference or an identity
    /// number, whatever its shape: "Identifikationsnummer", "N° d'avis",
    /// "vermeld daarbij", "número de afiliación".
    static let referenceLabels: [String] = [
        "number", "no", "nr", "n°", "nº", "número", "numéro", "reference", "ref", "control", "case",
        "dossier", "expediente", "afiliación", "avis", "rg", "sygn", "dosya", "kenmerk", "referentie",
        "vermeld", "vermelding", "daarbij", "quote", "quoting", "indicando", "rappelant", "betalingskenmerk",
    ]
    static let referenceStems: [String] = ["nummer", "aanslag", "kenmerk", "zeichen", "nummern"]

    /// Contact words on a line that make an unlabelled number a telephone
    /// number: "rufen Sie uns unter", "en el", "au", "pod numerem", "bilgi için".
    static let contactCues: [String] = [
        "unter", "erreichen", "rufen", "auskünfte", "rückfragen", "fragen", "en", "el", "al", "información",
        "consultas", "cita", "au", "renseignements", "contactez", "questions", "greffe", "on", "at", "calling",
        "contacted", "reached", "directed", "via", "met", "contact", "vragen", "pod", "numerem", "kontakt",
        "informacje", "pytania", "informacji", "bilgi", "için", "numarasını", "hattı", "arayarak", "randevu",
        "sorularınız", "talebiniz", "numarasını",
    ]

    /// Whether a number the phone rule found is a reference after all.
    public static func labelledAsReference(_ range: Range<String.Index>, in text: String) -> Bool {
        let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let start = text.index(range.lowerBound, offsetBy: -before, limitedBy: lineStart) ?? lineStart
        let preceding = words(text[start..<range.lowerBound])
        // The nearest label decides: "Telefoonnummer: 020 …" is a phone even
        // though it ends in -nummer.
        for word in preceding.reversed() {
            if phoneCues.contains(word) || word.hasPrefix("telefon") || word.hasPrefix("telefoon") || word.hasPrefix("phone") { return false }
            if referenceLabels.contains(word) || referenceStems.contains(where: { word.hasSuffix($0) }) { return true }
        }
        return false
    }

    /// Whether a number the phone rule found reads as the sender's telephone
    /// number: a leading 0, + or 00, a short service number (four digits or
    /// fewer), or a phone or contact word on its line.
    public static func readsAsPhone(_ range: Range<String.Index>, in text: String) -> Bool {
        let value = text[range]
        let digits = value.filter(\.isNumber)
        if value.hasPrefix("0") || value.hasPrefix("+") || digits.count <= 4 { return true }
        if saysPhone(range, in: text) { return true }
        let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[range.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        return words(text[lineStart..<lineEnd]).contains { contactCues.contains($0) }
    }

    public static func isReaders(_ range: Range<String.Index>, in text: String) -> Bool {
        let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[range.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        let beforeStart = text.index(range.lowerBound, offsetBy: -before, limitedBy: lineStart) ?? lineStart
        let afterEnd = text.index(range.upperBound, offsetBy: after, limitedBy: lineEnd) ?? lineEnd

        let preceding = words(text[beforeStart..<range.lowerBound])
        if preceding.contains(where: { cuesBefore.contains($0) }) { return true }
        let following = text[range.upperBound..<afterEnd].lowercased()
        let followingWords = words(Substring(following))
        return followingWords.contains { word in cuesAfter.contains { word.hasPrefix($0) } }
    }

    private static func words(_ text: Substring) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted.subtracting(CharacterSet(charactersIn: "-")))
            .filter { !$0.isEmpty }
    }
}
