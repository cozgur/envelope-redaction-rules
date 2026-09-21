import Foundation

/// A category of personal data the redaction engine removes before any text
/// leaves the device (H1).
///
/// Names are caught in the two places official letters put them -- the
/// recipient address block and the salutation -- and nowhere else. A third
/// party named in the body needs a model to find, and a model that reads the
/// letter is the thing this engine exists to avoid; that is v1.1. The
/// consequence is stated plainly rather than hidden.
public enum PIIKind: String, CaseIterable, Sendable {
    /// A national identity number: BSN, Steuer-ID, NIR, DNI/NIE, PESEL,
    /// TCKN, SSN, NINO.
    case idNumber
    case iban
    case cardNumber
    case phone
    case email
    case address
    /// A case, file or assessment reference. Redacted like the rest, and
    /// restored on device for the reply header.
    case reference
    /// A person's name, from the salutation. The name inside the recipient
    /// address block is masked as part of that block instead, which is how it
    /// is removed without ever being recognised as a name.
    case name

    /// The token used inside a placeholder, for example `ID_NUMBER` in
    /// `[ID_NUMBER_1]`.
    public var placeholderToken: String {
        switch self {
        case .idNumber: "ID_NUMBER"
        case .iban: "IBAN"
        case .cardNumber: "CARD_NUMBER"
        case .phone: "PHONE"
        case .email: "EMAIL"
        case .address: "ADDRESS"
        case .reference: "REFERENCE"
        case .name: "NAME"
        }
    }

    /// The placeholder for the `index`-th distinct value of this kind, from 1.
    public func placeholder(index: Int) -> String {
        "[\(placeholderToken)_\(index)]"
    }
}
