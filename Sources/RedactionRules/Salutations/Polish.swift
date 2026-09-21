import Foundation

extension SalutationTemplate {
    /// *Szanowna Pani Yilmaz,* names someone.
    /// *Szanowna Pani,* and *Szanowni Państwo,* do not.
    public static let polish = SalutationTemplate(
        language: "pl",
        personalPattern: #"(?im)^\s*(?:Szanowna Pani|Szanowny Panie)\s+([^,\n]+)\s*,"#,
        genericPattern: #"(?im)^\s*(?:Szanowni Państwo|Szanowna Pani|Szanowny Panie)\s*,"#
    )
}
