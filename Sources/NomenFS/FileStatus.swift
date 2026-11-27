import Foundation
import CNomenSys
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A file's identity on its volume: device, inode and birth time. It survives renames and
/// moves within the volume, so Nomen tracks files by it (3.5, 3.13). The birth time tells a
/// new file apart from a deleted one whose inode number the file system reused.
public struct FileIdentity: Codable, Hashable, Sendable, CustomStringConvertible {
    public var device: UInt64
    public var inode: UInt64
    /// Birth time in nanoseconds since 1970, or 0 when the file system does not record it.
    public var birth: Int64

    public init(device: UInt64, inode: UInt64, birth: Int64 = 0) {
        self.device = device
        self.inode = inode
        self.birth = birth
    }

    public var description: String { "\(device):\(inode):\(birth)" }
}

/// What `lstat` says about a path. Symlinks are never followed.
public struct FileStatus: Sendable, Hashable {
    public var identity: FileIdentity
    public var size: Int64
    /// Modification time in seconds since 1970, with nanosecond precision.
    public var modification: Double
    /// Inode change time; used as the date added on systems without one (Linux tests).
    public var change: Double
    public var isRegularFile: Bool
    public var isDirectory: Bool
    public var isSymlink: Bool
    /// BSD flags (UF_IMMUTABLE, UF_HIDDEN, SF_DATALESS). Always 0 on Linux.
    public var flags: UInt32

    public var isLocked: Bool { flags & UInt32(nomen_flag_immutable()) != 0 }
    public var isDataless: Bool { flags & UInt32(nomen_flag_dataless()) != 0 }
    public var isHiddenFlag: Bool { flags & UInt32(nomen_flag_hidden()) != 0 }
}

public enum FileSystem {
    private static let typeMask: UInt32 = 0o170000
    private static let regularType: UInt32 = 0o100000
    private static let directoryType: UInt32 = 0o040000
    private static let symlinkType: UInt32 = 0o120000

    /// `lstat` of a path, or nil if it does not exist.
    public static func status(atPath path: String) -> FileStatus? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let mode = UInt32(info.st_mode)
        #if canImport(Darwin)
        let modification = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
        let change = Double(info.st_ctimespec.tv_sec) + Double(info.st_ctimespec.tv_nsec) / 1e9
        let flags = UInt32(info.st_flags)
        #else
        let modification = Double(info.st_mtim.tv_sec) + Double(info.st_mtim.tv_nsec) / 1e9
        let change = Double(info.st_ctim.tv_sec) + Double(info.st_ctim.tv_nsec) / 1e9
        let flags: UInt32 = 0
        #endif
        var seconds: Int64 = 0
        var nanoseconds: Int = 0
        _ = nomen_birth_time(path, &seconds, &nanoseconds)
        let birth = seconds &* 1_000_000_000 &+ Int64(nanoseconds)
        return FileStatus(
            identity: FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino), birth: birth),
            size: Int64(info.st_size),
            modification: modification,
            change: change,
            isRegularFile: mode & typeMask == regularType,
            isDirectory: mode & typeMask == directoryType,
            isSymlink: mode & typeMask == symlinkType,
            flags: flags
        )
    }

    public static func exists(_ path: String) -> Bool { status(atPath: path) != nil }

    /// Top-level entry names of a directory, unsorted. Hidden entries are included.
    public static func entries(ofDirectory path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    /// True if the directory is writable by this process.
    public static func isWritable(_ path: String) -> Bool { access(path, W_OK) == 0 }

    /// The identity of an open file descriptor.
    public static func identity(ofDescriptor fd: Int32) -> FileIdentity? {
        var device: UInt64 = 0
        var inode: UInt64 = 0
        var seconds: Int64 = 0
        var nanoseconds: Int = 0
        guard nomen_fd_identity(fd, &device, &inode, &seconds, &nanoseconds) == 0 else { return nil }
        return FileIdentity(device: device, inode: inode, birth: seconds &* 1_000_000_000 &+ Int64(nanoseconds))
    }

    /// Renames without replacing an existing target. Returns 0, or the errno on failure.
    public static func renameExclusive(_ from: String, _ to: String) -> Int32 {
        nomen_rename_exclusive(from, to) == 0 ? 0 : errno
    }

    /// The current `errno`.
    public static var lastError: Int32 { errno }

    public static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    public static func parent(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    public static func name(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// Resolves "." and ".." textually, without following symlinks.
    public static func standardized(_ path: String) -> String {
        var components: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." { continue }
            if component == ".." { _ = components.popLast(); continue }
            components.append(String(component))
        }
        return "/" + components.joined(separator: "/")
    }

    /// True when `path` is `root` or inside it (textually, after standardizing both).
    public static func isInside(_ path: String, root: String) -> Bool {
        let p = standardized(path)
        let r = standardized(root)
        return p == r || p.hasPrefix(r.hasSuffix("/") ? r : r + "/")
    }
}
