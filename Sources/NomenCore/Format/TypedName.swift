/// Names the user types are never restyled (3.10). Only step 7 and the 255-byte limit
/// apply, and any change is shown before saving (H9).
public enum TypedName {
    public struct Result: Sendable, Hashable {
        /// The base name that will be used.
        public var base: String
        /// Base plus the file's extension.
        public var fileName: String
        /// True if sanitizing or the byte limit changed what was typed.
        public var changed: Bool
        /// A one-line explanation of the change, shown before saving.
        public var notice: String?
    }

    public enum Failure: Error, Sendable, Hashable {
        case empty
    }

    /// Prepares a typed base name. If it ends with the file's own extension, that
    /// extension is stripped first.
    public static func prepare(_ typed: String, fileExtension: String?, extensionCase: ExtensionCase = .keep) throws(Failure) -> Result {
        var base = typed
        if let ext = fileExtension, base.lowercased().hasSuffix("." + ext.lowercased()), base.count > ext.count + 1 {
            base.removeLast(ext.count + 1)
        }
        let typedBase = base
        var sanitized = Sanitizer.sanitizeBase(base, partSeparator: " ", wordSeparator: " ",
                                               options: CharacterOptions(allowEmoji: true))
        let renderedExt = FileExtension.render(fileExtension, case: extensionCase)
        let extBytes = renderedExt.map { $0.utf8.count + 1 } ?? 0
        let beforeFit = sanitized
        sanitized = Sanitizer.fitBytes(sanitized, limit: Defaults.maxFileNameBytes - extBytes)
        guard !sanitized.isEmpty else { throw .empty }

        var notice: String?
        if sanitized != beforeFit {
            notice = "The name was shortened to fit the 255-byte limit for file names."
        } else if sanitized != typedBase {
            notice = "Characters that can't be used in file names (such as “/” and “:”) were removed."
        }
        let fileName = renderedExt.map { sanitized + "." + $0 } ?? sanitized
        return Result(base: sanitized, fileName: fileName, changed: sanitized != typedBase, notice: notice)
    }
}
