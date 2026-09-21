import Foundation

extension SalutationTemplate {
    /// *Madame Yilmaz,* names someone.
    /// *Madame,* and *Madame, Monsieur,* do not.
    ///
    /// French opens with the honorific alone far more often than the others,
    /// so the generic pattern carries most of the work here.
    public static let french = SalutationTemplate(
        language: "fr",
        personalPattern: #"(?im)^\s*(?:Madame|Monsieur)\s+([^,\n]+)\s*,"#,
        genericPattern: #"(?im)^\s*(?:Madame\s*,\s*Monsieur|Madame|Monsieur|Madame\s*/\s*Monsieur)\s*,"#
    )
}
