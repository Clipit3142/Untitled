public import Foundation
public import NomenCore
import CNomenSys

/// Watched and destination folders must be on APFS or Mac OS Extended (3.2, C6).
public enum VolumePolicy {
    public enum Support: Sendable, Hashable {
        case supported
        case unsupported(reason: String)
    }

    /// File systems accepted on macOS.
    public static let supportedTypes: Set<String> = ["apfs", "hfs"]
    #if os(Linux)
    /// Local Linux file systems, accepted only so the test suite can run on Linux.
    static let testTypes: Set<String> = ["ext4", "btrfs", "xfs", "tmpfs", "overlay"]
    #else
    static let testTypes: Set<String> = []
    #endif

    public static func check(path: String) -> Support {
        var name = [CChar](repeating: 0, count: 64)
        var local: Int32 = 0
        guard nomen_volume_info(path, &name, name.count, &local) == 0 else {
            return .unsupported(reason: "Nomen can't read this folder's volume.")
        }
        let typeName = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return evaluate(typeName: typeName, isLocal: local != 0)
    }

    public static func evaluate(typeName: String, isLocal: Bool) -> Support {
        let type = typeName.lowercased()
        guard isLocal else {
            return .unsupported(reason: "This folder is on a network volume. Nomen works with folders on APFS or Mac OS Extended disks, because network volumes don't reliably report changes or keep file attributes.")
        }
        if supportedTypes.contains(type) || testTypes.contains(type) { return .supported }
        let label: String
        switch type {
        case "exfat": label = "exFAT"
        case "msdos": label = "FAT"
        case "ntfs": label = "NTFS"
        default: label = typeName
        }
        return .unsupported(reason: "This folder is on a \(label) volume. Nomen works with folders on APFS or Mac OS Extended disks, because other formats don't reliably keep file attributes or report changes.")
    }
}

/// Folders that look like code projects need explicit confirmation before watching (3.13, C7).
public enum ProjectFolderDetector {
    public static let markerNames: Set<String> = [".git", "package.json", "Cargo.toml", "pyproject.toml", "go.mod"]

    /// The project markers found at the top level of a folder.
    public static func markers(in path: String) -> [String] {
        let names = (try? FileSystem.entries(ofDirectory: path)) ?? []
        return names.filter { markerNames.contains($0) || $0.hasSuffix(".xcodeproj") }.sorted()
    }
}

/// Cached thumbnails in Caches, capped at 200 MB with least-recently-used eviction (3.20, W3).
public final class ThumbnailCache: Sendable {
    public let directory: URL
    public let limit: Int64

    public init(directory: URL, limit: Int64 = Defaults.thumbnailCacheBytes) {
        self.directory = directory
        self.limit = limit
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for key: String) -> URL {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return directory.appendingPathComponent(String(hash, radix: 16) + "-\(key.utf8.count).thumb")
    }

    public func store(_ data: Data, for key: String) {
        try? data.write(to: url(for: key), options: .atomic)
        enforceLimit()
    }

    public func data(for key: String) -> Data? {
        let file = url(for: key)
        guard let data = try? Data(contentsOf: file) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return data
    }

    public var totalSize: Int64 {
        files().reduce(0) { $0 + $1.size }
    }

    public func clear() {
        for file in files() { try? FileManager.default.removeItem(at: file.url) }
    }

    public func enforceLimit() {
        var all = files().sorted { $0.used < $1.used }
        var total = all.reduce(0) { $0 + $1.size }
        while total > limit, !all.isEmpty {
            let oldest = all.removeFirst()
            try? FileManager.default.removeItem(at: oldest.url)
            total -= oldest.size
        }
    }

    private func files() -> [(url: URL, size: Int64, used: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.filter { $0.pathExtension == "thumb" }.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return (url, Int64(values?.fileSize ?? 0), values?.contentModificationDate ?? .distantPast)
        }
    }
}
