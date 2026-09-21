import Foundation

extension SalutationTemplate {
    /// *Geachte mevrouw Yilmaz,* names someone.
    /// *Geachte heer/mevrouw,* does not.
    public static let dutch = SalutationTemplate(
        language: "nl",
        personalPattern: #"(?im)^\s*Geachte\s+(?:heer|mevrouw)\s+([^,\n]+)\s*,"#,
        genericPattern: #"(?im)^\s*Geachte\s+(?:heer\s*/\s*mevrouw|heer of mevrouw|mevrouw\s*/\s*heer|dames en heren)\s*,"#
    )
}
