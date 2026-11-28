import Foundation
@testable import UntitledFS
import UntitledCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A temporary directory removed when the value is released.
final class TemporaryDirectory: @unchecked Sendable {
    let path: String

    init(_ label: String = "untitled") {
        let base = FileManager.default.temporaryDirectory.path
        path = FileSystem.join(base, "\(label)-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    @discardableResult
    func file(_ name: String, contents: String? = nil, in subdirectory: String? = nil) -> String {
        var directory = path
        if let subdirectory {
            directory = FileSystem.join(path, subdirectory)
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        let filePath = FileSystem.join(directory, name)
        _ = FileManager.default.createFile(atPath: filePath, contents: Data((contents ?? "content of \(name) \(UUID())").utf8))
        return filePath
    }

    func directory(_ name: String) -> String {
        let directory = FileSystem.join(path, name)
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        return directory
    }

    var names: Set<String> {
        Set((try? FileSystem.entries(ofDirectory: path)) ?? [])
    }
}

/// A content fingerprint (FNV-1a 64) of a file; stands in for SHA-256 equality in tests,
/// where only "unchanged" matters.
func fingerprint(_ path: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in data {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01B3
    }
    return "\(data.count)-\(String(hash, radix: 16))"
}

func expected(_ path: String) -> ExpectedFile {
    ExpectedFile(status: FileSystem.status(atPath: path)!, name: FileSystem.name(path))
}

/// Names "Base.pdf", "Base-2.pdf" … like the formatter's collision suffix with a hyphen.
func suffixedNames(_ base: String, ext: String = "pdf", separator: String = "-") -> @Sendable (Int?) -> String {
    { number in number.map { "\(base)\(separator)\($0).\(ext)" } ?? "\(base).\(ext)" }
}

func makeExecutor(journal: any JournalStore = InMemoryJournal()) -> OperationExecutor {
    OperationExecutor(journal: journal, coordinator: DirectMove(), suppression: OwnOperationSuppression())
}
