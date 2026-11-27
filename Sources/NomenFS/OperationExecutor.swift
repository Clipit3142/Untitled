public import Foundation
public import NomenCore
import CNomenSys
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The file as Nomen saw it when it decided to rename it.
public struct ExpectedFile: Sendable, Hashable, Codable {
    public var identity: FileIdentity
    public var size: Int64
    public var modification: Double
    public var name: String

    public init(identity: FileIdentity, size: Int64, modification: Double, name: String) {
        self.identity = identity
        self.size = size
        self.modification = modification
        self.name = name
    }

    public init(status: FileStatus, name: String) {
        self.init(identity: status.identity, size: status.size, modification: status.modification, name: name)
    }
}

/// What the marker should say after the operation.
public enum MarkerAction: Sendable, Hashable {
    /// A rename by Nomen. A new marker records `originalName`; an existing marker keeps
    /// its first original name and date and switches to `renamed`.
    case renamed(originalName: String)
    /// An undo. The marker stays and switches to `restored` (Part 5 #12).
    case restored
}

/// Values recorded in the journal entry.
public struct JournalMetadata: Sendable, Hashable {
    public var styleID: String?
    public var styleVersion: Int?
    public var namingPath: NamingPath?
    public var confidence: Confidence?
    public var batchID: String?
    public var bookmark: Data?
    public var revertsEntryID: Int64?

    public init(styleID: String? = nil, styleVersion: Int? = nil, namingPath: NamingPath? = nil,
                confidence: Confidence? = nil, batchID: String? = nil, bookmark: Data? = nil, revertsEntryID: Int64? = nil) {
        self.styleID = styleID
        self.styleVersion = styleVersion
        self.namingPath = namingPath
        self.confidence = confidence
        self.batchID = batchID
        self.bookmark = bookmark
        self.revertsEntryID = revertsEntryID
    }
}

/// One rename or move.
public struct OperationRequest: Sendable {
    /// The folder the file is in now.
    public var directory: String
    public var expected: ExpectedFile
    /// Where the file goes; equal to `directory` for a rename in place.
    public var destinationDirectory: String
    /// Subfolders to create inside the destination (3.12).
    public var subfolders: [String]
    /// The name for an attempt: nil for the first, then 2…99 for collisions (3.13).
    public var names: @Sendable (Int?) -> String
    /// Granted folders; the destination must be inside one of them.
    public var grantedRoots: [String]
    public var method: OperationMethod
    public var metadata: JournalMetadata
    public var marker: MarkerAction

    public init(directory: String, expected: ExpectedFile, destinationDirectory: String? = nil, subfolders: [String] = [],
                names: @escaping @Sendable (Int?) -> String, grantedRoots: [String], method: OperationMethod,
                metadata: JournalMetadata = JournalMetadata(), marker: MarkerAction) {
        self.directory = directory
        self.expected = expected
        self.destinationDirectory = destinationDirectory ?? directory
        self.subfolders = subfolders
        self.names = names
        self.grantedRoots = grantedRoots
        self.method = method
        self.metadata = metadata
        self.marker = marker
    }
}

public struct OperationOutcome: Sendable, Hashable {
    public var entryID: Int64
    public var newPath: String
    public var collisionNumber: Int?
    public var markerWritten: Bool
}

public enum OperationError: Error, Sendable, Hashable {
    /// The file's name changed since detection (3.13 "named by someone else").
    case namedBySomeoneElse
    /// Size or modification date changed since detection.
    case fileChanged
    case sourceMissing
    /// Every name up to the 99th collision was taken; the file is untouched.
    case collisionLimit
    case crossVolume
    case outsideGrantedFolders
    case invalidName
    case destinationMissing
    /// The journal could not be written, so nothing was done (X4).
    case journalUnavailable
    case failed(errno: Int32)

    public var note: String {
        switch self {
        case .namedBySomeoneElse: "Named by someone else"
        case .fileChanged: "The file changed while Nomen was naming it"
        case .sourceMissing: "The file is no longer there"
        case .collisionLimit: "Too many files with the same name"
        case .crossVolume: "The destination is on another volume"
        case .outsideGrantedFolders: "The destination is outside the folders Nomen can use"
        case .invalidName: "The name isn't a valid file name"
        case .destinationMissing: "The destination folder is missing"
        case .journalUnavailable: "Nomen couldn't record the operation, so it didn't rename the file"
        case .failed(let code): "The rename failed (\(String(cString: strerror(code))))"
        }
    }
}

/// Executes renames and moves with the sequence of 3.13. Never deletes, never overwrites,
/// never changes contents, dates or other extended attributes, never follows symlinks and
/// never moves across volumes.
public final class OperationExecutor: Sendable {
    let journal: any JournalStore
    let coordinator: any FileCoordinating
    public let suppression: OwnOperationSuppression
    let now: @Sendable () -> Date

    public init(journal: any JournalStore, coordinator: any FileCoordinating, suppression: OwnOperationSuppression,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.journal = journal
        self.coordinator = coordinator
        self.suppression = suppression
        self.now = now
    }

    public func execute(_ request: OperationRequest) throws(OperationError) -> OperationOutcome {
        let sourcePath = FileSystem.join(request.directory, request.expected.name)

        // Checks that touch nothing.
        let targetDirectory = request.subfolders.reduce(request.destinationDirectory) { FileSystem.join($0, $1) }
        guard request.grantedRoots.contains(where: { FileSystem.isInside(targetDirectory, root: $0) }),
              request.grantedRoots.contains(where: { FileSystem.isInside(request.directory, root: $0) }) else {
            throw .outsideGrantedFolders
        }
        guard let destination = FileSystem.status(atPath: request.destinationDirectory), destination.isDirectory,
              !destination.isSymlink else {
            throw .destinationMissing
        }
        guard destination.identity.device == request.expected.identity.device else { throw .crossVolume }
        let firstName = request.names(nil)
        guard Sanitizer.isValidFileName(firstName) else { throw .invalidName }

        // 1. Journal entry planned.
        let entryID: Int64
        do {
            entryID = try journal.insertPlanned(JournalEntry(
                time: now(), identity: request.expected.identity, bookmark: request.metadata.bookmark,
                oldPath: sourcePath, newPath: FileSystem.join(targetDirectory, firstName), method: request.method,
                styleID: request.metadata.styleID, styleVersion: request.metadata.styleVersion,
                namingPath: request.metadata.namingPath, confidence: request.metadata.confidence,
                batchID: request.metadata.batchID, revertsEntryID: request.metadata.revertsEntryID
            ))
        } catch {
            throw .journalUnavailable
        }

        do {
            let outcome = try perform(request, sourcePath: sourcePath, targetDirectory: targetDirectory, entryID: entryID)
            // 6. Journal entry done.
            do {
                try journal.markDone(entryID, newPath: outcome.newPath)
                if let reverted = request.metadata.revertsEntryID { try journal.markReverted(reverted) }
            } catch {
                // The file is renamed and marked; launch reconciliation completes the entry.
            }
            return outcome
        } catch {
            try? journal.markFailed(entryID, note: error.note)
            throw error
        }
    }

    private func perform(_ request: OperationRequest, sourcePath: String, targetDirectory: String,
                         entryID: Int64) throws(OperationError) -> OperationOutcome {
        try createSubfolders(request)

        // 3. Identity re-check: same identity, size, modification date and an unchanged name.
        try recheck(request, sourcePath: sourcePath)

        var taken = Set(((try? FileSystem.entries(ofDirectory: targetDirectory)) ?? []).map(Self.fold))
        let sourceKey = Self.fold(request.expected.name)
        let sameDirectory = FileSystem.standardized(targetDirectory) == FileSystem.standardized(request.directory)
        if sameDirectory { taken.remove(sourceKey) }

        var finalPath: String?
        var usedNumber: Int?
        let attempts: [Int?] = [nil] + Defaults.collisionRange.map { Optional($0) }
        for number in attempts {
            let name = request.names(number)
            guard Sanitizer.isValidFileName(name) else { throw .invalidName }
            let target = FileSystem.join(targetDirectory, name)
            if sameDirectory, name == request.expected.name {
                finalPath = target
                usedNumber = number
                break
            }
            let key = Self.fold(name)
            if taken.contains(key) { continue }
            // 2 and 4. Coordinated exclusive rename.
            var renameError: Int32 = 0
            do {
                try coordinator.coordinateMove(from: URL(fileURLWithPath: sourcePath), to: URL(fileURLWithPath: target)) {
                    if sameDirectory, key == sourceKey {
                        renameError = Self.caseOnlyRename(from: sourcePath, to: target, directory: targetDirectory)
                    } else if nomen_rename_exclusive(sourcePath, target) != 0 {
                        renameError = errno
                    }
                }
            } catch {
                throw .failed(errno: EIO)
            }
            if renameError == 0 {
                finalPath = target
                usedNumber = number
                break
            }
            if renameError == EEXIST || renameError == ENOTEMPTY {
                taken.insert(key)
                continue
            }
            if renameError == ENOENT {
                try recheck(request, sourcePath: sourcePath)
                throw .sourceMissing
            }
            if renameError == EXDEV { throw .crossVolume }
            throw .failed(errno: renameError)
        }
        guard let newPath = finalPath else { throw .collisionLimit }

        // Verify that the file we moved is the file we meant; otherwise put it back.
        guard let moved = FileSystem.status(atPath: newPath), moved.identity == request.expected.identity else {
            if newPath != sourcePath { _ = nomen_rename_exclusive(newPath, sourcePath) }
            throw .namedBySomeoneElse
        }

        // 5. Marker.
        let markerWritten = writeMarker(request.marker, path: newPath)
        suppression.suppress(request.expected.identity, now: now())
        return OperationOutcome(entryID: entryID, newPath: newPath, collisionNumber: usedNumber, markerWritten: markerWritten)
    }

    private func recheck(_ request: OperationRequest, sourcePath: String) throws(OperationError) {
        guard let current = FileSystem.status(atPath: sourcePath) else {
            // Gone from its name: renamed by someone else, or removed.
            let names = (try? FileSystem.entries(ofDirectory: request.directory)) ?? []
            for name in names where FileSystem.status(atPath: FileSystem.join(request.directory, name))?.identity == request.expected.identity {
                throw .namedBySomeoneElse
            }
            throw .sourceMissing
        }
        if current.isSymlink || !current.isRegularFile { throw .namedBySomeoneElse }
        if current.identity != request.expected.identity { throw .namedBySomeoneElse }
        if current.size != request.expected.size || current.modification != request.expected.modification { throw .fileChanged }
    }

    private func createSubfolders(_ request: OperationRequest) throws(OperationError) {
        var current = request.destinationDirectory
        for component in request.subfolders {
            guard Sanitizer.isValidFileName(component), component != ".", component != ".." else { throw .invalidName }
            current = FileSystem.join(current, component)
            if let status = FileSystem.status(atPath: current) {
                guard status.isDirectory, !status.isSymlink else { throw .invalidName }
                continue
            }
            if mkdir(current, 0o755) != 0, errno != EEXIST { throw .failed(errno: errno) }
            guard let created = FileSystem.status(atPath: current), created.isDirectory, !created.isSymlink else {
                throw .invalidName
            }
        }
    }

    /// Case-only renames ("invoice.pdf" → "Invoice.pdf") go through a hidden temporary name,
    /// because an exclusive rename sees the target as taken on case-insensitive volumes.
    private static func caseOnlyRename(from source: String, to target: String, directory: String) -> Int32 {
        let temporary = FileSystem.join(directory, ".nomen-\(UUID().uuidString).tmp")
        guard nomen_rename_exclusive(source, temporary) == 0 else { return errno }
        if nomen_rename_exclusive(temporary, target) == 0 { return 0 }
        let failure = errno
        _ = nomen_rename_exclusive(temporary, source)
        return failure
    }

    private func writeMarker(_ action: MarkerAction, path: String) -> Bool {
        let existing = Marker.read(atPath: path)
        let marker: Marker
        switch action {
        case .renamed(let originalName):
            marker = existing.map { Marker(originalName: $0.originalName, state: .renamed, firstRenamed: $0.firstRenamed) }
                ?? Marker(originalName: originalName, state: .renamed, firstRenamed: now())
        case .restored:
            guard let existing else { return false }
            marker = Marker(originalName: existing.originalName, state: .restored, firstRenamed: existing.firstRenamed)
        }
        return (try? marker.write(toPath: path)) != nil
    }

    /// Case-insensitive comparison key for names (3.13 "Comparisons are case-insensitive").
    static func fold(_ name: String) -> String {
        name.nfcForComparison.lowercased()
    }
}

extension String {
    var nfcForComparison: String { precomposedStringWithCanonicalMapping }
}
