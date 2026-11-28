/// Splits names into base and extension (3.10 step 10, J4).
///
/// An extension is the text after the last dot when it is 1–15 ASCII letters and digits
/// with at least one letter ("pdf", "JPG", "m4a", "7z"), or exactly three digits (split
/// archives such as ".001"). `.tar.gz`, `.tar.bz2`, `.tar.xz` and `.tar.zst` count as one
/// extension. A name whose base would be empty (".bashrc") has no extension. Everything
/// else, such as "Report v1.2", has no extension and keeps its dots in the base.
public enum FileExtension {
    static let multiPart = ["tar.gz", "tar.bz2", "tar.xz", "tar.zst"]

    public static func split(_ name: String) -> (base: String, extension: String?) {
        let lowered = name.lowercased()
        for ext in multiPart {
            let suffix = "." + ext
            if lowered.hasSuffix(suffix), lowered.count > suffix.count {
                let cut = name.index(name.endIndex, offsetBy: -suffix.count)
                return (String(name[..<cut]), String(name[name.index(after: cut)...]))
            }
        }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, nil) }
        let ext = String(name[name.index(after: dot)...])
        guard isExtension(ext) else { return (name, nil) }
        return (String(name[..<dot]), ext)
    }

    static func isExtension(_ ext: String) -> Bool {
        guard (1...15).contains(ext.count), ext.unicodeScalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)) }) else {
            return false
        }
        if ext.unicodeScalars.contains(where: { $0.properties.isAlphabetic }) { return true }
        return ext.count == 3
    }

    /// The extension as it goes into the new name: byte-for-byte, or lowercased.
    public static func render(_ ext: String?, case extensionCase: ExtensionCase) -> String? {
        guard let ext else { return nil }
        return extensionCase == .lowercase ? ext.lowercased() : ext
    }

    /// The lowercased extension used for type checks ("JPG" → "jpg", "tar.gz" → "tar.gz").
    public static func typeKey(_ name: String) -> String? {
        split(name).extension?.lowercased()
    }
}
