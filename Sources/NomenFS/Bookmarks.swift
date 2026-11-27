public import Foundation

/// Security-scoped access to granted folders and bookmarks for history entries (3.3, 3.14).
public protocol BookmarkProviding: Sendable {
    /// An app-scoped, security-scoped bookmark for a folder the user granted.
    func folderBookmark(for url: URL) throws -> Data
    /// A bookmark that finds a file again after the user moves it (L3).
    func fileBookmark(for url: URL) throws -> Data
    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool)
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

public enum BookmarkError: Error, Sendable, Hashable {
    case unresolvable
}

/// Path-based bookmarks for Linux tests: they do not follow moved files.
public struct PathBookmarks: BookmarkProviding {
    public init() {}
    public func folderBookmark(for url: URL) throws -> Data { Data(url.path.utf8) }
    public func fileBookmark(for url: URL) throws -> Data { Data(url.path.utf8) }
    public func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        let path = String(decoding: bookmark, as: UTF8.self)
        guard FileSystem.exists(path) else { throw BookmarkError.unresolvable }
        return (URL(fileURLWithPath: path), false)
    }
    public func startAccessing(_ url: URL) -> Bool { true }
    public func stopAccessing(_ url: URL) {}
}

#if canImport(Darwin) && !os(Linux)
/// Security-scoped bookmarks (App Sandbox, files.bookmarks.app-scope).
public struct SecurityScopedBookmarks: BookmarkProviding {
    public init() {}

    public func folderBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func fileBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }

    public func startAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    public func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}
#endif
