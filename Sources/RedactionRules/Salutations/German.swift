import Foundation

extension SalutationTemplate {
    /// *Sehr geehrte Frau Yilmaz,* names someone.
    /// *Sehr geehrte Damen und Herren,* does not.
    public static let german = SalutationTemplate(
        language: "de",
        personalPattern: #"(?im)^\s*Sehr geehrter?\s+(?:Frau|Herr)\s+([^,\n]+)\s*,"#,
        genericPattern: #"(?im)^\s*Sehr geehrte\s+Damen und Herren\s*,"#
    )
}
