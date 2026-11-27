import Foundation

/// Reconciles planned journal entries at launch by locating each file's identity (3.14, J3).
public struct Reconciler: Sendable {
    public enum Outcome: Sendable, Hashable {
        case completed(id: Int64, path: String)
        case notStarted(id: Int64)
        case movedElsewhere(id: Int64, path: String)
        case missing(id: Int64)
    }

    let journal: any JournalStore

    public init(journal: any JournalStore) {
        self.journal = journal
    }

    public func reconcile() throws -> [Outcome] {
        var outcomes: [Outcome] = []
        for entry in try journal.plannedEntries() {
            guard let id = entry.id else { continue }
            if FileSystem.status(atPath: entry.newPath)?.identity == entry.identity {
                // The rename happened; finish what the crash interrupted.
                ensureMarker(entry)
                try journal.markDone(id, newPath: entry.newPath)
                if let reverted = entry.revertsEntryID { try journal.markReverted(reverted) }
                outcomes.append(.completed(id: id, path: entry.newPath))
            } else if FileSystem.status(atPath: entry.oldPath)?.identity == entry.identity {
                try journal.markFailed(id, note: "Interrupted before the rename; the file is unchanged")
                outcomes.append(.notStarted(id: id))
            } else if let found = locate(entry) {
                try journal.markFailed(id, note: "Named by someone else")
                outcomes.append(.movedElsewhere(id: id, path: found))
            } else {
                try journal.markFailed(id, note: "The file is no longer there")
                outcomes.append(.missing(id: id))
            }
        }
        return outcomes
    }

    private func locate(_ entry: JournalEntry) -> String? {
        for directory in Set([FileSystem.parent(entry.oldPath), FileSystem.parent(entry.newPath)]) {
            for name in (try? FileSystem.entries(ofDirectory: directory)) ?? [] {
                let path = FileSystem.join(directory, name)
                if FileSystem.status(atPath: path)?.identity == entry.identity { return path }
            }
        }
        return nil
    }

    private func ensureMarker(_ entry: JournalEntry) {
        switch entry.method {
        case .undo, .finderRestore:
            if let marker = Marker.read(atPath: entry.newPath), marker.state != .restored {
                try? Marker(originalName: marker.originalName, state: .restored, firstRenamed: marker.firstRenamed).write(toPath: entry.newPath)
            }
        default:
            if Marker.read(atPath: entry.newPath) == nil {
                try? Marker(originalName: entry.oldName, state: .renamed, firstRenamed: entry.time).write(toPath: entry.newPath)
            }
        }
    }
}
