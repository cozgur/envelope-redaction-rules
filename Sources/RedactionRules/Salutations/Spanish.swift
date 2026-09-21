import Foundation

extension SalutationTemplate {
    /// *Estimada señora Yilmaz:* names someone.
    /// *Estimados señores:* and *Muy señores míos:* do not.
    public static let spanish = SalutationTemplate(
        language: "es",
        personalPattern: #"(?im)^\s*Estimad[oa]\s+(?:Sr\.|Sra\.|Señor|Señora)\s+([^,:\n]+)\s*[,:]"#,
        genericPattern: #"(?im)^\s*(?:Estimados?\s+(?:señores|señores|Sres\.)|Muy señores míos|A quien corresponda)\s*[:,]"#
    )
}
