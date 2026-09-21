import Foundation

extension SalutationTemplate {
    /// *Dear Ms Yilmaz,* names someone.
    /// *Dear Sir or Madam,* and *To whom it may concern,* do not.
    public static let english = SalutationTemplate(
        language: "en",
        personalPattern: #"(?im)^\s*Dear\s+(?:Mr|Ms|Mrs|Mx|Dr|Miss|Prof)\.?\s+([^,\n]+)\s*,"#,
        genericPattern: #"(?im)^\s*(?:Dear\s+(?:Sir\s+or\s+Madam|Sir/Madam|Sir|Madam|Customer|Resident|Occupier)|To whom it may concern)\s*[,:]"#
    )
}
