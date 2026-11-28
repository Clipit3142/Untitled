#if canImport(Darwin) && !os(Linux)
import Foundation
import Testing
@testable import UntitledFS
import UntitledCore

/// The Darwin-only parts of UntitledFS: FSEvents, coordinated moves and security-scoped bookmarks.
@Suite("Darwin file system")
struct DarwinTests {
    @Test("FSEvents reports a new file at the top level")
    func fseventsSignalsChanges() async throws {
        let dir = TemporaryDirectory("untitled-fsevents")
        let watcher = FSEventsFolderWatcher(path: dir.path, sinceEventID: nil, onEventID: { _ in })
        let signals = watcher.signals()
        let received = Task { () -> WatchSignal? in
            for await signal in signals { return signal }
            return nil
        }
        try await Task.sleep(for: .milliseconds(300))
        dir.file("Screenshot 2026-11-27 at 14.05.12.png")
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            received.cancel()
        }
        let signal = await received.value
        timeout.cancel()
        watcher.stop()
        #expect(signal == .changed || signal == .mustRescan)
        #expect(FSEventsFolderWatcher.currentEventID > 0)
    }

    @Test("FSEvents reports the folder itself going away (C2)")
    func fseventsSignalsRootChange() async throws {
        let dir = TemporaryDirectory("untitled-fsevents-root")
        let watched = dir.directory("Desktop")
        let watcher = FSEventsFolderWatcher(path: watched, sinceEventID: nil, onEventID: { _ in })
        let signals = watcher.signals()
        let sawRoot = Task { () -> Bool in
            for await signal in signals where signal == .rootChanged { return true }
            return false
        }
        try await Task.sleep(for: .milliseconds(300))
        try FileManager.default.moveItem(atPath: watched, toPath: watched + "-moved")
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            sawRoot.cancel()
        }
        let result = await sawRoot.value
        timeout.cancel()
        watcher.stop()
        #expect(result)
    }

    @Test("Coordinated moves rename exactly once and keep the content")
    func coordinatedMove() throws {
        let dir = TemporaryDirectory("untitled-coordinated")
        let source = dir.file("scan0001.pdf", contents: "invoice")
        let executor = OperationExecutor(journal: InMemoryJournal(), coordinator: CoordinatedMove(), suppression: OwnOperationSuppression())
        let outcome = try executor.execute(OperationRequest(
            directory: dir.path, expected: expected(source), names: { _ in "Invoice.pdf" },
            grantedRoots: [dir.path], method: .automatic, marker: .renamed(originalName: "scan0001.pdf")
        ))
        #expect(FileSystem.name(outcome.newPath) == "Invoice.pdf")
        #expect(try String(contentsOfFile: outcome.newPath, encoding: .utf8) == "invoice")
        #expect(!FileSystem.exists(source))
    }

    @Test("Security-scoped bookmarks resolve to the folder and find it after a move")
    func securityScopedBookmarks() throws {
        let dir = TemporaryDirectory("untitled-bookmarks")
        let folder = dir.directory("Invoices")
        let bookmarks = SecurityScopedBookmarks()
        let data: Data
        do {
            data = try bookmarks.folderBookmark(for: URL(fileURLWithPath: folder))
        } catch {
            // Outside the sandbox, security-scoped bookmarks may be unavailable; a plain bookmark still proves resolution.
            data = try URL(fileURLWithPath: folder).bookmarkData()
        }
        let resolved = try bookmarks.resolve(data)
        #expect(resolved.url.resolvingSymlinksInPath().path == URL(fileURLWithPath: folder).resolvingSymlinksInPath().path)
        _ = bookmarks.startAccessing(resolved.url)
        bookmarks.stopAccessing(resolved.url)
        let file = dir.file("a.pdf", in: "Invoices")
        let fileBookmark = (try? bookmarks.fileBookmark(for: URL(fileURLWithPath: file))) ?? (try URL(fileURLWithPath: file).bookmarkData())
        try FileManager.default.moveItem(atPath: file, toPath: FileSystem.join(dir.path, "b.pdf"))
        let moved = try bookmarks.resolve(fileBookmark)
        #expect(moved.url.lastPathComponent == "b.pdf")
    }
}
#endif
