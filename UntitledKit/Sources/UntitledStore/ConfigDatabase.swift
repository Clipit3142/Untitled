public import Foundation
public import UntitledCore
public import UntitledFS
import GRDB

/// config.sqlite: folders, styles, rules, kinds, examples, learning, ignore list, event IDs
/// and settings (3.20). Kept apart from history so a damaged history never loses configuration.
public final class ConfigDatabase: Sendable {
    let queue: DatabaseQueue

    /// Opens or creates the database. Pass nil for an in-memory database.
    public init(url: URL?) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var configuration = Configuration()
            configuration.busyMode = .timeout(10)
            queue = try DatabaseQueue(path: url.path, configuration: configuration)
        } else {
            queue = try DatabaseQueue()
        }
        try Self.migrator.migrate(queue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "folder") { t in
                t.primaryKey("id", .text)
                t.column("position", .integer).notNull()
                t.column("json", .text).notNull()
            }
            try db.create(table: "style") { t in
                t.primaryKey("id", .text)
                t.column("json", .text).notNull()
            }
            try db.create(table: "rule") { t in
                t.primaryKey("id", .text)
                t.column("position", .integer).notNull()
                t.column("json", .text).notNull()
            }
            try db.create(table: "destination") { t in
                t.primaryKey("id", .text)
                t.column("json", .text).notNull()
            }
            try db.create(table: "customKind") { t in
                t.primaryKey("id", .text)
                t.column("label", .text).notNull()
            }
            try db.create(table: "example") { t in
                t.primaryKey("styleID", .text)
                t.column("json", .text).notNull()
            }
            try db.create(table: "learningEvent") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("styleID", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("json", .text).notNull()
            }
            try db.create(table: "ignoreItem") { t in
                t.column("device", .integer).notNull()
                t.column("inode", .integer).notNull()
                t.column("birth", .integer).notNull()
                t.column("name", .text).notNull()
                t.column("addedAt", .datetime).notNull()
                t.primaryKey(["device", "inode", "birth"])
            }
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("json", .text).notNull()
            }
        }
        migrator.registerMigration("v2") { db in
            try db.create(table: "folderSnapshot") { t in
                t.primaryKey("folderID", .text)
                t.column("json", .text).notNull()
            }
        }
        return migrator
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    static func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: Folders

    public func folders() throws -> [GrantedFolder] {
        try queue.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM folder ORDER BY position").map { try Self.decode(GrantedFolder.self, $0) }
        }
    }

    public func save(_ folder: GrantedFolder) throws {
        try queue.write { db in
            let position = try Int.fetchOne(db, sql: "SELECT position FROM folder WHERE id = ?", arguments: [folder.id])
                ?? (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM folder") ?? 0)
            try db.execute(sql: "INSERT OR REPLACE INTO folder (id, position, json) VALUES (?, ?, ?)",
                           arguments: [folder.id, position, try Self.json(folder)])
        }
    }

    public func deleteFolder(id: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM folder WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM folderSnapshot WHERE folderID = ?", arguments: [id])
        }
    }

    /// The last top-level snapshot of a watched folder, so renames made while the app was
    /// quit are not mistaken for arrivals at launch (D9).
    public func snapshot(folderID: String) throws -> FolderSnapshot? {
        try queue.read { db in
            try String.fetchOne(db, sql: "SELECT json FROM folderSnapshot WHERE folderID = ?", arguments: [folderID])
                .map { try Self.decode(FolderSnapshot.self, $0) }
        }
    }

    public func saveSnapshot(_ snapshot: FolderSnapshot, folderID: String) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO folderSnapshot (folderID, json) VALUES (?, ?)",
                           arguments: [folderID, try Self.json(snapshot)])
        }
    }

    // MARK: Styles

    public func styles() throws -> [NamingStyle] {
        try queue.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM style ORDER BY id").map { try Self.decode(NamingStyle.self, $0) }
        }
    }

    public func style(id: String) throws -> NamingStyle? {
        try queue.read { db in
            try String.fetchOne(db, sql: "SELECT json FROM style WHERE id = ?", arguments: [id]).map { try Self.decode(NamingStyle.self, $0) }
        }
    }

    /// Saves a style. Styles that fail validation are refused (H7).
    public func save(_ style: NamingStyle) throws {
        let issues = StyleValidator.issues(style)
        guard issues.isEmpty else { throw StoreError.invalidStyle(issues) }
        try queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO style (id, json) VALUES (?, ?)", arguments: [style.id, try Self.json(style)])
        }
    }

    public func deleteStyle(id: String) throws {
        try queue.write { db in try db.execute(sql: "DELETE FROM style WHERE id = ?", arguments: [id]) }
    }

    // MARK: Rules and destinations

    public func rules() throws -> [Rule] {
        try queue.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM rule ORDER BY position").map { try Self.decode(Rule.self, $0) }
        }
    }

    /// Replaces all rules, keeping their order (first match wins, 3.12).
    public func saveRules(_ rules: [Rule]) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM rule")
            for (position, rule) in rules.enumerated() {
                try db.execute(sql: "INSERT INTO rule (id, position, json) VALUES (?, ?, ?)",
                               arguments: [rule.id, position, try Self.json(rule)])
            }
        }
    }

    public func destinations() throws -> [Destination] {
        try queue.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM destination ORDER BY id").map { try Self.decode(Destination.self, $0) }
        }
    }

    public func save(_ destination: Destination) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO destination (id, json) VALUES (?, ?)",
                           arguments: [destination.id, try Self.json(destination)])
        }
    }

    // MARK: Kinds

    public func customKinds() throws -> [CustomKind] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, label FROM customKind ORDER BY label").map { CustomKind(id: $0["id"], label: $0["label"]) }
        }
    }

    public func saveCustomKinds(_ kinds: [CustomKind]) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM customKind")
            for kind in kinds {
                try db.execute(sql: "INSERT INTO customKind (id, label) VALUES (?, ?)", arguments: [kind.id, StoredText.clamp(kind.label)])
            }
        }
    }

    // MARK: Learning

    public func examples(styleID: String) throws -> ExampleList {
        try queue.read { db in
            try String.fetchOne(db, sql: "SELECT json FROM example WHERE styleID = ?", arguments: [styleID])
                .map { try Self.decode(ExampleList.self, $0) } ?? ExampleList()
        }
    }

    public func saveExamples(_ examples: ExampleList, styleID: String) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO example (styleID, json) VALUES (?, ?)", arguments: [styleID, try Self.json(examples)])
        }
    }

    public func learningEvents() throws -> [EditEvent] {
        try queue.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM learningEvent ORDER BY id").map { try Self.decode(EditEvent.self, $0) }
        }
    }

    public func addLearningEvents(_ events: [EditEvent]) throws {
        try queue.write { db in
            for event in events {
                try db.execute(sql: "INSERT INTO learningEvent (styleID, date, json) VALUES (?, ?, ?)",
                               arguments: [event.styleID, event.date, try Self.json(event)])
            }
            // Events older than the learning window can never count again.
            try db.execute(sql: "DELETE FROM learningEvent WHERE date < ?", arguments: [Date().addingTimeInterval(-Defaults.learningWindow * 2)])
        }
    }

    public func suggestionAnswers() throws -> SuggestionAnswers {
        try setting(SuggestionAnswers.self, key: "suggestionAnswers") ?? SuggestionAnswers()
    }

    public func saveSuggestionAnswers(_ answers: SuggestionAnswers) throws {
        try setSetting(answers, key: "suggestionAnswers")
    }

    // MARK: Ignore list

    public func ignore(identity: FileIdentity, name: String, at date: Date) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO ignoreItem (device, inode, birth, name, addedAt) VALUES (?, ?, ?, ?, ?)",
                           arguments: [Int64(bitPattern: identity.device), Int64(bitPattern: identity.inode), identity.birth, name, date])
        }
    }

    public func isIgnored(identity: FileIdentity) throws -> Bool {
        try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ignoreItem WHERE device = ? AND inode = ? AND birth = ?",
                             arguments: [Int64(bitPattern: identity.device), Int64(bitPattern: identity.inode), identity.birth]) ?? 0 > 0
        }
    }

    // MARK: Settings

    public func setting<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        try queue.read { db in
            try String.fetchOne(db, sql: "SELECT json FROM setting WHERE key = ?", arguments: [key]).map { try Self.decode(type, $0) }
        }
    }

    public func setSetting<T: Encodable>(_ value: T, key: String) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO setting (key, json) VALUES (?, ?)", arguments: [key, try Self.json(value)])
        }
    }

    // MARK: Privacy actions (O5)

    /// Clear learned data: learning events, suggestion answers and examples. Styles stay.
    public func clearLearnedData() throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM learningEvent")
            try db.execute(sql: "DELETE FROM example")
            try db.execute(sql: "DELETE FROM setting WHERE key = 'suggestionAnswers'")
        }
    }

    /// Reset: removes every folder, style, rule, kind, example, learned item, ignored file and setting.
    public func resetAll() throws {
        try queue.write { db in
            for table in ["folder", "style", "rule", "destination", "customKind", "example", "learningEvent", "ignoreItem", "setting", "folderSnapshot"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }

    /// Row counts per table, for tests and diagnostics.
    public func rowCounts() throws -> [String: Int] {
        try queue.read { db in
            var counts: [String: Int] = [:]
            for table in ["folder", "style", "rule", "destination", "customKind", "example", "learningEvent", "ignoreItem", "setting"] {
                counts[table] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
            }
            return counts
        }
    }
}

public enum StoreError: Error, Sendable, Hashable {
    case invalidStyle([StyleIssue])
}
