public import Foundation

/// Folder mode (3.3).
public enum FolderMode: String, Codable, Sendable, Hashable, CaseIterable {
    case automatic, review, off
}

/// Whether processing was started by a file arriving or by the user (3.6).
public enum RequestKind: String, Codable, Sendable, Hashable {
    /// A file arrived in a watched folder.
    case automatic
    /// Quick Rename, bulk rename or Shortcuts.
    case explicit
}

/// Everything eligibility needs to know about a file. NomenFS fills it in.
public struct FileFacts: Sendable, Hashable {
    public var name: String
    public var isTopLevel: Bool
    public var isRegularFile: Bool
    public var isDirectory: Bool
    public var isPackage: Bool
    public var isSymlink: Bool
    public var isAlias: Bool
    public var isHidden: Bool
    public var dateAdded: Date?
    public var isLocked: Bool
    public var parentWritable: Bool
    public var isDataless: Bool
    public var hasMarker: Bool
    public var seenInHistory: Bool
    public var onIgnoreList: Bool
    public var size: Int64

    public init(
        name: String, isTopLevel: Bool = true, isRegularFile: Bool = true, isDirectory: Bool = false,
        isPackage: Bool = false, isSymlink: Bool = false, isAlias: Bool = false, isHidden: Bool = false,
        dateAdded: Date? = nil, isLocked: Bool = false, parentWritable: Bool = true, isDataless: Bool = false,
        hasMarker: Bool = false, seenInHistory: Bool = false, onIgnoreList: Bool = false, size: Int64 = 0
    ) {
        self.name = name
        self.isTopLevel = isTopLevel
        self.isRegularFile = isRegularFile
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isSymlink = isSymlink
        self.isAlias = isAlias
        self.isHidden = isHidden
        self.dateAdded = dateAdded
        self.isLocked = isLocked
        self.parentWritable = parentWritable
        self.isDataless = isDataless
        self.hasMarker = hasMarker
        self.seenInHistory = seenInHistory
        self.onIgnoreList = onIgnoreList
        self.size = size
    }
}

/// The folder settings eligibility depends on.
public struct FolderPolicy: Sendable, Hashable {
    public var mode: FolderMode
    public var watchStart: Date
    public var onlyGenericNames: Bool
    public var userGenericPatterns: [String]

    public init(mode: FolderMode, watchStart: Date, onlyGenericNames: Bool = true, userGenericPatterns: [String] = []) {
        self.mode = mode
        self.watchStart = watchStart
        self.onlyGenericNames = onlyGenericNames
        self.userGenericPatterns = userGenericPatterns
    }
}

public enum SkipReason: String, Sendable, Hashable, CaseIterable {
    case notTopLevel, folderOff, paused, notRegularFile, directory, package, symlink, alias
    case hidden, systemFile, inProgress, disallowedType, beforeWatchStart, hasMarker, seenBefore
    case ignored, locked, notWritable, dataless, notGeneric
}

public enum MetadataOnlyReason: String, Sendable, Hashable {
    case disallowedType, dataless, tooLarge, passwordProtected
}

public enum EligibilityDecision: Sendable, Hashable {
    /// Read content and propose normally.
    case process
    /// Propose from metadata only; confidence is always Low (3.6).
    case metadataOnly(MetadataOnlyReason)
    case skip(SkipReason)
}

/// The eligibility rules of 3.6.
public enum Eligibility {
    /// Extensions Nomen reads (3.6 "Type").
    public static let allowedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "webp", "pdf", "txt", "md",
        "markdown", "rtf", "html", "htm", "doc", "docx", "xlsx", "pptx", "pages", "numbers", "key",
    ]

    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "webp"]

    /// In-progress download and temp suffixes (3.6 "Not in progress").
    public static let inProgressExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload", "tmp"]

    public static let systemNames: Set<String> = [".DS_Store", ".localized", "Icon\r"]

    public static func isAllowedType(_ name: String) -> Bool {
        guard let ext = FileExtension.typeKey(name) else { return false }
        return allowedExtensions.contains(ext)
    }

    public static func isInProgress(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        guard let last = name.split(separator: ".").last, name.contains(".") else { return false }
        return inProgressExtensions.contains(last.lowercased())
    }

    public static func evaluate(_ facts: FileFacts, folder: FolderPolicy?, request: RequestKind, paused: Bool) -> EligibilityDecision {
        let automatic = request == .automatic

        // Event conditions (automatic only).
        if automatic {
            guard let folder else { return .skip(.notTopLevel) }
            if !facts.isTopLevel { return .skip(.notTopLevel) }
            if folder.mode == .off { return .skip(.folderOff) }
            if paused { return .skip(.paused) }
        }

        // File kind (safety).
        if facts.isSymlink { return .skip(.symlink) }
        if facts.isAlias { return .skip(.alias) }
        if facts.isPackage { return .skip(.package) }
        if facts.isDirectory { return .skip(.directory) }
        if !facts.isRegularFile { return .skip(.notRegularFile) }
        if systemNames.contains(facts.name) { return .skip(.systemFile) }
        if facts.isHidden || facts.name.hasPrefix(".") { return .skip(.hidden) }

        // Not in progress (safety).
        if isInProgress(facts.name) { return .skip(.inProgress) }

        // Writable and local (safety).
        if facts.isLocked { return .skip(.locked) }
        if !facts.parentWritable { return .skip(.notWritable) }

        if automatic {
            guard let folder else { return .skip(.notTopLevel) }
            if !isAllowedType(facts.name) { return .skip(.disallowedType) }
            guard let added = facts.dateAdded, added >= folder.watchStart else { return .skip(.beforeWatchStart) }
            if facts.hasMarker { return .skip(.hasMarker) }
            if facts.seenInHistory { return .skip(.seenBefore) }
            if facts.onIgnoreList { return .skip(.ignored) }
            if facts.isDataless { return .skip(.dataless) }
            if folder.onlyGenericNames,
               !GenericNameDetector(userPatterns: folder.userGenericPatterns).isGeneric(facts.name) {
                return .skip(.notGeneric)
            }
        } else {
            if facts.isDataless { return .metadataOnly(.dataless) }
            if !isAllowedType(facts.name) { return .metadataOnly(.disallowedType) }
        }

        if facts.size > Defaults.contentReadingSizeLimit { return .metadataOnly(.tooLarge) }
        return .process
    }
}
