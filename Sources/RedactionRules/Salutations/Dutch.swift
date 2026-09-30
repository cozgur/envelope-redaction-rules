import Foundation

extension SalutationTemplate {
    /// *Geachte mevrouw Yilmaz,* and *Beste meneer De Vries,* name someone.
    /// *Geachte heer/mevrouw,* and *Beste klant,* do not.
    public static let dutch = SalutationTemplate(
        language: "nl",
        personalPattern: #"(?im)^\s*(?:Geachte|Beste)\s+(?:heer|mevrouw|meneer)\s+([^,\n]+)\s*,"#,
        genericPattern: #"(?im)^\s*(?:Geachte\s+(?:heer\s*/\s*mevrouw|heer of mevrouw|mevrouw\s*/\s*heer|dames en heren)|Beste\s+(?:meneer\s*/\s*mevrouw|heer\s*/\s*mevrouw|klant|huurder|lezer|relatie))\s*,"#
    )
}
