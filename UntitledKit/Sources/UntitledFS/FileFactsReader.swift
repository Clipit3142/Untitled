public import Foundation
public import UntitledCore

/// Reads the facts eligibility needs about a file (3.6). Never downloads iCloud files and
/// never follows symlinks.
public enum FileFactsReader {
    public struct Result: Sendable {
        public var facts: FileFacts
        public var status: FileStatus
        public var marker: Marker?
    }

    /// - Parameters:
    ///   - path: the file.
    ///   - isTopLevel: whether the file is directly inside the watched folder.
    ///   - seen: whether history already has this identity and date added.
    ///   - ignored: whether the identity is on the ignore list.
    public static func read(path: String, isTopLevel: Bool,
                            seen: (FileIdentity, Date?) -> Bool = { _, _ in false },
                            ignored: (FileIdentity) -> Bool = { _ in false }) -> Result? {
        guard let status = FileSystem.status(atPath: path) else { return nil }
        let name = FileSystem.name(path)
        let url = URL(fileURLWithPath: path)
        var isPackage = false
        var isAlias = false
        var isHidden = name.hasPrefix(".") || status.isHiddenFlag
        var dateAdded: Date? = Date(timeIntervalSince1970: status.change)
        var isDataless = status.isDataless
        var isLocked = status.isLocked
        #if canImport(Darwin) && !os(Linux)
        let keys: Set<URLResourceKey> = [.isPackageKey, .isAliasFileKey, .isHiddenKey, .addedToDirectoryDateKey,
                                         .isUserImmutableKey, .ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey]
        if let values = try? url.resourceValues(forKeys: keys) {
            isPackage = values.isPackage ?? false
            isAlias = (values.isAliasFile ?? false) && !status.isSymlink
            isHidden = isHidden || (values.isHidden ?? false)
            dateAdded = values.addedToDirectoryDate
            isLocked = isLocked || (values.isUserImmutable ?? false)
            if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded {
                isDataless = true
            }
        }
        #else
        _ = url
        #endif
        let marker = status.isSymlink ? nil : Marker.read(atPath: path)
        let facts = FileFacts(
            name: name, isTopLevel: isTopLevel, isRegularFile: status.isRegularFile, isDirectory: status.isDirectory,
            isPackage: isPackage, isSymlink: status.isSymlink, isAlias: isAlias, isHidden: isHidden,
            dateAdded: dateAdded, isLocked: isLocked, parentWritable: FileSystem.isWritable(FileSystem.parent(path)),
            isDataless: isDataless, hasMarker: marker != nil, seenInHistory: seen(status.identity, dateAdded),
            onIgnoreList: ignored(status.identity), size: status.size
        )
        return Result(facts: facts, status: status, marker: marker)
    }
}
