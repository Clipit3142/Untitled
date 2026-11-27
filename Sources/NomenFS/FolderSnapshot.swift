import Foundation

/// An entry at the top level of a watched folder.
public struct FolderEntry: Sendable, Hashable {
    public var identity: FileIdentity
    public var name: String
    /// Used to order arrivals (3.8 "in arrival order").
    public var changeTime: Double
}

/// What happened between two snapshots (3.5). Only `arrived` starts processing.
public enum FolderEvent: Sendable, Hashable {
    case arrived(FolderEntry)
    case renamedInPlace(FolderEntry, oldName: String)
    case removed(FileIdentity, name: String)
}

/// The top level of a folder: file identity → name. Subfolders' contents are never listed (C3).
public struct FolderSnapshot: Sendable, Hashable {
    public private(set) var entries: [FileIdentity: FolderEntry]

    public init(entries: [FileIdentity: FolderEntry] = [:]) {
        self.entries = entries
    }

    public static func scan(_ path: String) throws -> FolderSnapshot {
        var entries: [FileIdentity: FolderEntry] = [:]
        for name in try FileSystem.entries(ofDirectory: path) {
            guard let status = FileSystem.status(atPath: FileSystem.join(path, name)) else { continue }
            entries[status.identity] = FolderEntry(identity: status.identity, name: name, changeTime: status.change)
        }
        return FolderSnapshot(entries: entries)
    }

    /// Replaces the snapshot with `newer` and returns the events between them. Arrivals are
    /// ordered by when they appeared, then by name.
    public mutating func update(to newer: FolderSnapshot) -> [FolderEvent] {
        var events: [FolderEvent] = []
        for (identity, entry) in entries where newer.entries[identity] == nil {
            events.append(.removed(identity, name: entry.name))
        }
        var arrivals: [FolderEntry] = []
        for (identity, entry) in newer.entries {
            if let old = entries[identity] {
                if old.name != entry.name { events.append(.renamedInPlace(entry, oldName: old.name)) }
            } else {
                arrivals.append(entry)
            }
        }
        arrivals.sort { ($0.changeTime, $0.name) < ($1.changeTime, $1.name) }
        events += arrivals.map { .arrived($0) }
        entries = newer.entries
        return events
    }
}

/// Waits until a file stops changing (3.4 stability wait, D1): size and modification date
/// equal on two checks at least `interval` apart, after an initial `wait`.
public struct StabilityGate: Sendable {
    public var wait: Duration
    public var interval: Duration

    public init(wait: Duration = .milliseconds(1_000), interval: Duration = .milliseconds(500)) {
        self.wait = wait
        self.interval = interval
    }

    public enum Failure: Error, Sendable, Hashable {
        case vanished
        case replaced
    }

    /// Returns the stable status, or throws if the file disappears or is replaced.
    public func waitUntilStable(path: String, identity: FileIdentity) async throws -> FileStatus {
        try await Task.sleep(for: wait)
        guard var previous = FileSystem.status(atPath: path) else { throw Failure.vanished }
        guard previous.identity == identity else { throw Failure.replaced }
        while true {
            try await Task.sleep(for: interval)
            guard let current = FileSystem.status(atPath: path) else { throw Failure.vanished }
            guard current.identity == identity else { throw Failure.replaced }
            if current.size == previous.size, current.modification == previous.modification {
                return current
            }
            previous = current
        }
    }
}
