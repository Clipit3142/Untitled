import Foundation
import UntitledCore
public import UntitledFS
public import UntitledStore

extension Engine {
    // MARK: Undo (3.14)

    /// ⌘Z in the main window: undoes the last operation.
    public func undoLast() -> UndoResult? {
        guard let id = lastOperationID ?? (try? deps.history.recent(limit: 1).first?.id) ?? nil else { return nil }
        return undo(entryID: id)
    }

    /// Undoes one operation: restores the original name and folder, exclusively.
    public func undo(entryID: Int64) -> UndoResult {
        guard let entry = try? deps.history.entry(entryID), entry.state == .done else {
            return .unavailable(reason: "This change was already undone.")
        }
        // Find the file: where Untitled put it, its bookmark, or by identity in granted folders (L3).
        var currentPath: String?
        if FileSystem.status(atPath: entry.newPath)?.identity == entry.identity {
            currentPath = entry.newPath
        } else if let bookmark = entry.bookmark, let resolved = try? deps.bookmarks.resolve(bookmark),
                  FileSystem.status(atPath: resolved.url.path)?.identity == entry.identity {
            currentPath = resolved.url.path
        } else {
            currentPath = locate(entry.identity)
        }
        guard let path = currentPath, let status = FileSystem.status(atPath: path) else {
            return .unavailable(reason: "The file was deleted, so this change can't be undone.")
        }
        let roots = grantedRoots()
        guard roots.contains(where: { FileSystem.isInside(path, root: $0) }) else {
            return .needsAccess(folder: FileSystem.parent(path))
        }
        // The original folder is recreated only inside a granted folder.
        let originalFolder = FileSystem.parent(entry.oldPath)
        var destination = originalFolder
        var missing: [String] = []
        while FileSystem.status(atPath: destination)?.isDirectory != true {
            missing.insert(FileSystem.name(destination), at: 0)
            destination = FileSystem.parent(destination)
            if destination == "/" { break }
        }
        guard roots.contains(where: { FileSystem.isInside(originalFolder, root: $0) && FileSystem.isInside(destination, root: $0) }) else {
            return .unavailable(reason: "The original folder is gone and is outside the folders Untitled can use.")
        }
        let originalName = entry.oldName
        let split = FileExtension.split(originalName)
        let request = OperationRequest(
            directory: FileSystem.parent(path), expected: ExpectedFile(status: status, name: FileSystem.name(path)),
            destinationDirectory: destination, subfolders: missing,
            names: { n in n.map { split.base + " \($0)" + (split.extension.map { "." + $0 } ?? "") } ?? originalName },
            grantedRoots: roots, method: .undo, metadata: JournalMetadata(batchID: entry.batchID, revertsEntryID: entryID),
            marker: .restored
        )
        do {
            let outcome = try deps.executor.execute(request)
            if outcome.collisionNumber != nil {
                emit(.notice("“\(originalName)” was taken, so the file is now “\(FileSystem.name(outcome.newPath))”."))
            }
            emit(.historyChanged)
            return .restored(path: outcome.newPath, collisionNumber: outcome.collisionNumber)
        } catch {
            return .unavailable(reason: error.note)
        }
    }

    /// Batch undo for bulk runs and bursts; failures are listed one by one (L5).
    public func undoBatch(_ batchID: String) -> [Int64: UndoResult] {
        var results: [Int64: UndoResult] = [:]
        for entry in (try? deps.history.entries(batchID: batchID)) ?? [] {
            guard let id = entry.id else { continue }
            results[id] = undo(entryID: id)
        }
        return results
    }

    /// Undo All from a notification summary.
    public func undo(entryIDs: [Int64]) -> [Int64: UndoResult] {
        var results: [Int64: UndoResult] = [:]
        for id in entryIDs { results[id] = undo(entryID: id) }
        return results
    }

    /// Finder's "Restore Original Name": uses the marker, so it works even after history is purged.
    public func restoreOriginalName(path: String) -> UndoResult {
        guard let marker = Marker.read(atPath: path), marker.state == .renamed, let status = FileSystem.status(atPath: path) else {
            return .unavailable(reason: "Untitled didn't rename this file.")
        }
        let roots = grantedRoots()
        guard roots.contains(where: { FileSystem.isInside(path, root: $0) }) else { return .needsAccess(folder: FileSystem.parent(path)) }
        let split = FileExtension.split(marker.originalName)
        let request = OperationRequest(
            directory: FileSystem.parent(path), expected: ExpectedFile(status: status, name: FileSystem.name(path)),
            names: { n in n.map { split.base + " \($0)" + (split.extension.map { "." + $0 } ?? "") } ?? marker.originalName },
            grantedRoots: roots, method: .finderRestore, marker: .restored
        )
        do {
            let outcome = try deps.executor.execute(request)
            if let previous = try? deps.history.latestDone(identity: status.identity), let id = previous.id {
                try? deps.history.markReverted(id)
            }
            emit(.historyChanged)
            return .restored(path: outcome.newPath, collisionNumber: outcome.collisionNumber)
        } catch {
            return .unavailable(reason: error.note)
        }
    }

    /// "Never rename again" in Activity.
    public func neverRenameAgain(entryID: Int64) {
        guard let entry = try? deps.history.entry(entryID) else { return }
        try? deps.config.ignore(identity: entry.identity, name: entry.newName, at: deps.now())
    }

    /// Looks for a file by identity in the granted folders and their subfolders, two levels deep.
    func locate(_ identity: FileIdentity) -> String? {
        for root in grantedRoots() {
            var queue: [(String, Int)] = [(root, 0)]
            while let (directory, depth) = queue.popLast() {
                for name in (try? FileSystem.entries(ofDirectory: directory)) ?? [] {
                    let path = FileSystem.join(directory, name)
                    guard let status = FileSystem.status(atPath: path) else { continue }
                    if status.identity == identity { return path }
                    if status.isDirectory, !status.isSymlink, depth < 2 { queue.append((path, depth + 1)) }
                }
            }
        }
        return nil
    }

    // MARK: Activity

    public func entry(id: Int64) -> JournalEntry? { try? deps.history.entry(id) }

    /// Current paths of renamed files that were not restored, for the Finder extension.
    public func renamedPaths(limit: Int = 5_000) -> [String] { (try? deps.history.renamedPaths(limit: limit)) ?? [] }

    public func activity(search: String = "", limit: Int = 500) -> [JournalEntry] {
        (try? deps.history.search(search, limit: limit)) ?? []
    }

    public func notes() -> [ActivityNote] {
        (try? deps.history.notes()) ?? []
    }

    /// Clear history (O5): history entries, notes and the thumbnail cache (W3).
    public func clearHistory(thumbnails: ThumbnailCache?) throws {
        try deps.history.clearHistory()
        thumbnails?.clear()
        emit(.historyChanged)
    }

    /// Clear learned data (O5).
    public func clearLearnedData() throws {
        try deps.config.clearLearnedData()
        emit(.suggestionsChanged)
    }

    /// Reset (O5): every setting, folder, style, rule and learned item, history and queue.
    public func resetEverything(thumbnails: ThumbnailCache?) throws {
        stop()
        try deps.config.resetAll()
        try deps.history.resetAll()
        thumbnails?.clear()
        folders.removeAll()
        snapshots.removeAll()
        items.removeAll()
        recentFacts.removeAll()
        ruleWarnings.removeAll()
        pause = .none
        settings = EngineSettings()
        emit(.foldersChanged)
        emit(.queueChanged)
        emit(.historyChanged)
    }
}
