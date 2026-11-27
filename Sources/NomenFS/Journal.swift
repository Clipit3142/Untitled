public import Foundation
public import NomenCore
import Synchronization

/// How an operation was started (3.14 "method").
public enum OperationMethod: String, Codable, Sendable, Hashable, CaseIterable {
    case automatic, review, quickRename, bulk, shortcut, notification, undo, finderRestore
}

/// Journal entry states (3.14).
public enum JournalState: String, Codable, Sendable, Hashable, CaseIterable {
    case planned, done, failed, reverted
}

/// One rename or move, written before the file is touched (write-ahead journal, 3.13).
public struct JournalEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64?
    public var time: Date
    public var identity: FileIdentity
    public var bookmark: Data?
    public var oldPath: String
    public var newPath: String
    public var method: OperationMethod
    public var styleID: String?
    public var styleVersion: Int?
    public var namingPath: NamingPath?
    public var confidence: Confidence?
    public var batchID: String?
    public var state: JournalState
    public var note: String?
    /// For undo operations: the entry this one reverts.
    public var revertsEntryID: Int64?

    public init(
        id: Int64? = nil, time: Date, identity: FileIdentity, bookmark: Data? = nil, oldPath: String,
        newPath: String, method: OperationMethod, styleID: String? = nil, styleVersion: Int? = nil,
        namingPath: NamingPath? = nil, confidence: Confidence? = nil, batchID: String? = nil,
        state: JournalState = .planned, note: String? = nil, revertsEntryID: Int64? = nil
    ) {
        self.id = id
        self.time = time
        self.identity = identity
        self.bookmark = bookmark
        self.oldPath = oldPath
        self.newPath = newPath
        self.method = method
        self.styleID = styleID
        self.styleVersion = styleVersion
        self.namingPath = namingPath
        self.confidence = confidence
        self.batchID = batchID
        self.state = state
        self.note = note
        self.revertsEntryID = revertsEntryID
    }

    public var oldName: String { FileSystem.name(oldPath) }
    public var newName: String { FileSystem.name(newPath) }
}

/// Persistence for the journal. NomenStore implements it on history.sqlite.
public protocol JournalStore: Sendable {
    func insertPlanned(_ entry: JournalEntry) throws -> Int64
    func markDone(_ id: Int64, newPath: String) throws
    func markFailed(_ id: Int64, note: String) throws
    func markReverted(_ id: Int64) throws
    func plannedEntries() throws -> [JournalEntry]
    func entry(_ id: Int64) throws -> JournalEntry?
}

/// An in-memory journal for tests and previews.
public final class InMemoryJournal: JournalStore {
    private let state = Mutex<(entries: [Int64: JournalEntry], next: Int64)>(([:], 1))

    public init() {}

    public func insertPlanned(_ entry: JournalEntry) throws -> Int64 {
        state.withLock { s in
            var copy = entry
            copy.id = s.next
            copy.state = .planned
            s.entries[s.next] = copy
            s.next += 1
            return s.next - 1
        }
    }

    public func markDone(_ id: Int64, newPath: String) throws {
        state.withLock { s in
            s.entries[id]?.state = .done
            s.entries[id]?.newPath = newPath
        }
    }

    public func markFailed(_ id: Int64, note: String) throws {
        state.withLock { s in
            s.entries[id]?.state = .failed
            s.entries[id]?.note = note
        }
    }

    public func markReverted(_ id: Int64) throws {
        state.withLock { s in s.entries[id]?.state = .reverted }
    }

    public func plannedEntries() throws -> [JournalEntry] {
        state.withLock { s in s.entries.values.filter { $0.state == .planned }.sorted { $0.id! < $1.id! } }
    }

    public func entry(_ id: Int64) throws -> JournalEntry? {
        state.withLock { s in s.entries[id] }
    }

    public var all: [JournalEntry] {
        state.withLock { s in s.entries.values.sorted { $0.id! < $1.id! } }
    }
}

/// Events for files Nomen just moved are ignored for 5 s, keyed by file identity (3.13).
public final class OwnOperationSuppression: Sendable {
    private let entries = Mutex<[FileIdentity: Date]>([:])
    private let duration: TimeInterval

    public init(duration: TimeInterval = Defaults.ownOperationSuppression) {
        self.duration = duration
    }

    public func suppress(_ identity: FileIdentity, now: Date = Date()) {
        entries.withLock { $0[identity] = now.addingTimeInterval(duration) }
    }

    public func isSuppressed(_ identity: FileIdentity, now: Date = Date()) -> Bool {
        entries.withLock { map in
            map = map.filter { $0.value > now }
            return map[identity] != nil
        }
    }
}
