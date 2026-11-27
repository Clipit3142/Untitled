public import Foundation
import UntitledCore
public import UntitledFS
import GRDB

/// history.sqlite in WAL mode: history and journal, the queue and activity notes (3.14, 3.20).
public final class HistoryDatabase: JournalStore, Sendable {
    let pool: any DatabaseWriter

    /// Opens or creates the database. Pass nil for an in-memory database.
    public init(url: URL?) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var configuration = Configuration()
            configuration.prepareDatabase { db in
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
            }
            pool = try DatabasePool(path: url.path, configuration: configuration)
        } else {
            pool = try DatabaseQueue()
        }
        try Self.migrator.migrate(pool)
    }

    /// Opens the history database. A corrupted file is detected, set aside and recreated;
    /// configuration lives in another file and is unaffected (L7).
    public static func openRecovering(url: URL, now: Date = Date()) throws -> (database: HistoryDatabase, recovered: Bool) {
        do {
            let database = try HistoryDatabase(url: url)
            if try database.passesIntegrityCheck() { return (database, false) }
        } catch {
            // Fall through to recovery.
        }
        let stamp = Int(now.timeIntervalSince1970)
        let aside = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).sqlite")
        try? FileManager.default.moveItem(at: url, to: aside)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            try? FileManager.default.moveItem(at: sidecar, to: URL(fileURLWithPath: aside.path + suffix))
        }
        return (try HistoryDatabase(url: url), true)
    }

    func passesIntegrityCheck() throws -> Bool {
        try pool.read { db in try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok" }
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "operation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("time", .datetime).notNull()
                t.column("device", .integer).notNull()
                t.column("inode", .integer).notNull()
                t.column("birth", .integer).notNull().defaults(to: 0)
                t.column("bookmark", .blob)
                t.column("oldPath", .text).notNull()
                t.column("newPath", .text).notNull()
                t.column("oldName", .text).notNull()
                t.column("newName", .text).notNull()
                t.column("method", .text).notNull()
                t.column("styleID", .text)
                t.column("styleVersion", .integer)
                t.column("namingPath", .text)
                t.column("confidence", .text)
                t.column("batchID", .text)
                t.column("state", .text).notNull()
                t.column("note", .text)
                t.column("revertsEntryID", .integer)
                t.column("dateAdded", .datetime)
            }
            try db.create(index: "operation_state", on: "operation", columns: ["state"])
            try db.create(index: "operation_time", on: "operation", columns: ["time"])
            try db.create(index: "operation_identity", on: "operation", columns: ["device", "inode"])
            try db.create(index: "operation_batch", on: "operation", columns: ["batchID"])
            try db.create(table: "queueItem") { t in
                t.primaryKey("id", .text)
                t.column("arrival", .integer).notNull()
                t.column("status", .text).notNull()
                t.column("json", .text).notNull()
            }
            try db.create(table: "note") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("time", .datetime).notNull()
                t.column("message", .text).notNull()
            }
        }
        return migrator
    }

    // MARK: JournalStore

    public func insertPlanned(_ entry: JournalEntry) throws -> Int64 {
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO operation (time, device, inode, birth, bookmark, oldPath, newPath, oldName, newName, method, styleID,
                    styleVersion, namingPath, confidence, batchID, state, note, revertsEntryID)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'planned', ?, ?)
                """, arguments: [
                    entry.time, Int64(bitPattern: entry.identity.device), Int64(bitPattern: entry.identity.inode), entry.identity.birth,
                    entry.bookmark, entry.oldPath, entry.newPath, entry.oldName, entry.newName, entry.method.rawValue,
                    entry.styleID, entry.styleVersion, entry.namingPath?.rawValue, entry.confidence?.rawValue,
                    entry.batchID, StoredText.clamp(entry.note), entry.revertsEntryID,
                ])
            return db.lastInsertedRowID
        }
    }

    public func markDone(_ id: Int64, newPath: String) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE operation SET state = 'done', newPath = ?, newName = ? WHERE id = ?",
                           arguments: [newPath, FileSystem.name(newPath), id])
        }
    }

    public func markFailed(_ id: Int64, note: String) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE operation SET state = 'failed', note = ? WHERE id = ?", arguments: [StoredText.clamp(note), id])
        }
    }

    public func markReverted(_ id: Int64) throws {
        try pool.write { db in try db.execute(sql: "UPDATE operation SET state = 'reverted' WHERE id = ?", arguments: [id]) }
    }

    public func plannedEntries() throws -> [JournalEntry] {
        try entries(sql: "SELECT * FROM operation WHERE state = 'planned' ORDER BY id")
    }

    public func entry(_ id: Int64) throws -> JournalEntry? {
        try entries(sql: "SELECT * FROM operation WHERE id = ?", arguments: [id]).first
    }

    /// Records the file's date added with its operation, for "not seen before" (3.6).
    public func setDateAdded(_ date: Date?, for id: Int64) throws {
        try pool.write { db in try db.execute(sql: "UPDATE operation SET dateAdded = ? WHERE id = ?", arguments: [date, id]) }
    }

    // MARK: History queries

    func entries(sql: String, arguments: StatementArguments = []) throws -> [JournalEntry] {
        try pool.read { db in try Row.fetchAll(db, sql: sql, arguments: arguments).map(Self.entry(from:)) }
    }

    static func entry(from row: Row) -> JournalEntry {
        JournalEntry(
            id: row["id"], time: row["time"],
            identity: FileIdentity(device: UInt64(bitPattern: row["device"]), inode: UInt64(bitPattern: row["inode"]), birth: row["birth"]),
            bookmark: row["bookmark"], oldPath: row["oldPath"], newPath: row["newPath"],
            method: OperationMethod(rawValue: row["method"]) ?? .automatic, styleID: row["styleID"], styleVersion: row["styleVersion"],
            namingPath: (row["namingPath"] as String?).flatMap(NamingPath.init(rawValue:)),
            confidence: (row["confidence"] as String?).flatMap(Confidence.init(rawValue:)),
            batchID: row["batchID"], state: JournalState(rawValue: row["state"]) ?? .failed, note: row["note"],
            revertsEntryID: row["revertsEntryID"]
        )
    }

    /// Completed operations, newest first (Recent and Activity).
    public func recent(limit: Int) throws -> [JournalEntry] {
        try entries(sql: "SELECT * FROM operation WHERE state IN ('done', 'reverted') AND method NOT IN ('undo', 'finderRestore') ORDER BY id DESC LIMIT ?",
                    arguments: [limit])
    }

    /// Activity search by old or new name (3.15). Case-insensitive.
    public func search(_ text: String, limit: Int = 500) throws -> [JournalEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return try recent(limit: limit) }
        let pattern = "%" + trimmed.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
        return try entries(sql: """
            SELECT * FROM operation WHERE state IN ('done', 'reverted') AND method NOT IN ('undo', 'finderRestore')
              AND (oldName LIKE ? ESCAPE '\\' OR newName LIKE ? ESCAPE '\\') ORDER BY id DESC LIMIT ?
            """, arguments: [pattern, pattern, limit])
    }

    public func entries(batchID: String) throws -> [JournalEntry] {
        try entries(sql: "SELECT * FROM operation WHERE batchID = ? AND state = 'done' AND method NOT IN ('undo', 'finderRestore') ORDER BY id",
                    arguments: [batchID])
    }

    /// The latest completed operation for a file, if any.
    public func latestDone(identity: FileIdentity) throws -> JournalEntry? {
        try entries(sql: "SELECT * FROM operation WHERE device = ? AND inode = ? AND birth = ? AND state = 'done' AND method NOT IN ('undo', 'finderRestore') ORDER BY id DESC LIMIT 1",
                    arguments: [Int64(bitPattern: identity.device), Int64(bitPattern: identity.inode), identity.birth]).first
    }

    /// True if history has this file identity with this date added (3.6 "Not seen before").
    public func hasSeen(identity: FileIdentity, dateAdded: Date?) throws -> Bool {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT dateAdded FROM operation WHERE device = ? AND inode = ? AND birth = ?",
                                        arguments: [Int64(bitPattern: identity.device), Int64(bitPattern: identity.inode), identity.birth])
            return rows.contains { row in
                let stored: Date? = row["dateAdded"]
                guard let stored, let dateAdded else { return dateAdded == nil }
                return abs(stored.timeIntervalSince(dateAdded)) < 1
            }
        }
    }

    public var operationCount: Int {
        ((try? pool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM operation") }) ?? nil) ?? 0
    }

    // MARK: Retention (3.14, L6)

    /// Deletes finished entries older than the cutoff. Planned entries and queued items are never touched.
    @discardableResult
    public func purge(before cutoff: Date) throws -> Int {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM operation WHERE time < ? AND state IN ('done', 'failed', 'reverted')", arguments: [cutoff])
            let removed = db.changesCount
            try db.execute(sql: "DELETE FROM note WHERE time < ?", arguments: [cutoff])
            return removed
        }
    }

    /// Clear history (O5): every finished entry and note. Planned entries and the queue stay.
    public func clearHistory() throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM operation WHERE state != 'planned'")
            try db.execute(sql: "DELETE FROM note")
        }
    }

    /// Reset: everything, including the queue.
    public func resetAll() throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM operation")
            try db.execute(sql: "DELETE FROM note")
            try db.execute(sql: "DELETE FROM queueItem")
        }
    }

    // MARK: Queue

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    public func save(_ item: QueueItem) throws {
        var stored = item
        stored.proposal = item.proposal.map { StoredText.clamp($0) }
        let json = String(decoding: try Self.encoder.encode(stored), as: UTF8.self)
        try pool.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO queueItem (id, arrival, status, json) VALUES (?, ?, ?, ?)",
                           arguments: [item.id, item.arrival, item.status.rawValue, json])
        }
    }

    public func queueItems() throws -> [QueueItem] {
        try pool.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM queueItem ORDER BY arrival").map {
                try Self.decoder.decode(QueueItem.self, from: Data($0.utf8))
            }
        }
    }

    public func removeQueueItem(id: String) throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM queueItem WHERE id = ?", arguments: [id]) }
    }

    public func nextArrival() throws -> Int64 {
        try pool.read { db in try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(arrival) + 1, 1) FROM queueItem") ?? 1 }
    }

    // MARK: Notes

    public func addNote(_ note: ActivityNote) throws {
        try pool.write { db in
            try db.execute(sql: "INSERT INTO note (time, message) VALUES (?, ?)", arguments: [note.time, note.message])
        }
    }

    public func notes() throws -> [ActivityNote] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT id, time, message FROM note ORDER BY id DESC").map {
                ActivityNote(id: $0["id"], time: $0["time"], message: $0["message"])
            }
        }
    }

    // MARK: Schema audit (W1)

    /// Every column of every table, for the schema audit.
    public func schema() throws -> [String: [String]] {
        try pool.read { db in
            var result: [String: [String]] = [:]
            for table in ["operation", "queueItem", "note"] {
                result[table] = try db.columns(in: table).map(\.name)
            }
            return result
        }
    }
}
