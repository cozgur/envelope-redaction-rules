import Foundation

extension SalutationTemplate {
    /// *Sayın Yilmaz,* names someone.
    /// *Sayın İlgili,* and *Sayın Yetkili,* do not.
    ///
    /// Turkish has no honorific between the opener and the name, so the words
    /// that stand in for a person have to be listed. Without that list,
    /// "Sayın İlgili" -- "Dear concerned party" -- reads as a person called
    /// İlgili and is masked as one.
    public static let turkish = SalutationTemplate(
        language: "tr",
        personalPattern: #"(?im)^\s*Sayın\s+([^,\n]+)\s*,"#,
        genericPattern: #"(?im)^\s*Sayın\s+(?:İlgili|Ilgili|Yetkili|Yetkilisi|Müşterimiz|Musterimiz|Vatandaşımız)\s*,"#,
        nonNameTerms: ["İlgili", "Ilgili", "Yetkili", "Yetkilisi", "Müşterimiz", "Vatandaşımız"]
    )
}
