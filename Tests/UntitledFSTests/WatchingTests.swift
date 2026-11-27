import Foundation
import Testing
@testable import UntitledFS
import UntitledCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

struct SnapshotTests {
    /// D9: renaming an existing file in place is reported as a rename, never as an arrival.
    @Test func renameInPlaceIsNotAnArrival() throws {
        let dir = TemporaryDirectory()
        let file = dir.file("Report.pdf")
        var snapshot = try FolderSnapshot.scan(dir.path)
        rename(file, FileSystem.join(dir.path, "IMG_0001.pdf"))
        let events = snapshot.update(to: try FolderSnapshot.scan(dir.path))
        #expect(events.count == 1)
        guard case .renamedInPlace(let entry, let oldName) = events.first else {
            Issue.record("expected a rename, got \(events)")
            return
        }
        #expect(entry.name == "IMG_0001.pdf")
        #expect(oldName == "Report.pdf")
    }

    @Test func arrivalsAndRemovals() throws {
        let dir = TemporaryDirectory()
        let old = dir.file("old.txt")
        var snapshot = try FolderSnapshot.scan(dir.path)
        try FileManager.default.removeItem(atPath: old)
        dir.file("b.png")
        dir.file("a.png")
        let events = snapshot.update(to: try FolderSnapshot.scan(dir.path))
        #expect(events.contains { if case .removed(_, "old.txt") = $0 { true } else { false } })
        let arrivals = events.compactMap { event -> String? in if case .arrived(let e) = event { e.name } else { nil } }
        #expect(Set(arrivals) == ["a.png", "b.png"])
    }

    @Test func filesMovedInFromElsewhereAreArrivals() throws {
        let watched = TemporaryDirectory()
        let other = TemporaryDirectory()
        let file = other.file("IMG_1.jpg")
        var snapshot = try FolderSnapshot.scan(watched.path)
        rename(file, FileSystem.join(watched.path, "IMG_1.jpg"))
        let events = snapshot.update(to: try FolderSnapshot.scan(watched.path))
        #expect(events.count == 1)
        if case .arrived(let entry) = events.first { #expect(entry.name == "IMG_1.jpg") } else { Issue.record("\(events)") }
    }

    /// C3: files in subfolders are never seen (100 nested fixtures, 0 processed).
    @Test func subfolderContentsAreNeverListed() throws {
        let dir = TemporaryDirectory()
        var snapshot = try FolderSnapshot.scan(dir.path)
        for index in 0..<100 {
            dir.file("IMG_\(index).jpg", in: "Nested/Level\(index % 5)/Deeper")
        }
        let events = snapshot.update(to: try FolderSnapshot.scan(dir.path))
        let arrivals = events.compactMap { event -> FolderEntry? in if case .arrived(let e) = event { e } else { nil } }
        #expect(arrivals.map(\.name) == ["Nested"])
        // The only arrival is a folder, which eligibility skips.
        let facts = try #require(FileFactsReader.read(path: FileSystem.join(dir.path, "Nested"), isTopLevel: true))
        let decision = Eligibility.evaluate(facts.facts, folder: FolderPolicy(mode: .automatic, watchStart: .distantPast), request: .automatic, paused: false)
        #expect(decision == .skip(.directory))
    }
}

struct StabilityTests {
    @Test func waitsUntilWritesStop() async throws {
        let dir = TemporaryDirectory()
        let path = dir.file("download.pdf", contents: "")
        let identity = try #require(FileSystem.status(atPath: path)).identity
        let writer = Task.detached {
            let handle = FileHandle(forWritingAtPath: path)!
            for _ in 0..<12 {
                handle.seekToEndOfFile()
                handle.write(Data(repeating: 7, count: 4_096))
                try? await Task.sleep(for: .milliseconds(60))
            }
            try? handle.close()
            return Date()
        }
        let gate = StabilityGate(wait: .milliseconds(100), interval: .milliseconds(150))
        let stable = try await gate.waitUntilStable(path: path, identity: identity)
        let finished = await writer.value
        #expect(stable.size == 12 * 4_096, "only the finished file is reported")
        #expect(Date() >= finished)
    }

    @Test func vanishingFilesFail() async throws {
        let dir = TemporaryDirectory()
        let path = dir.file("temp.part")
        let identity = try #require(FileSystem.status(atPath: path)).identity
        try FileManager.default.removeItem(atPath: path)
        await #expect(throws: StabilityGate.Failure.vanished) {
            try await StabilityGate(wait: .milliseconds(10), interval: .milliseconds(10)).waitUntilStable(path: path, identity: identity)
        }
    }
}

struct WatcherTests {
    @Test func pollingWatcherSignalsChangesAndRootChanges() async throws {
        let dir = TemporaryDirectory()
        let watcher = PollingFolderWatcher(path: dir.path, interval: .milliseconds(50))
        var iterator = watcher.signals().makeAsyncIterator()
        dir.file("IMG_1.png")
        let first = await iterator.next()
        #expect(first == .changed)
        let renamed = dir.path + "-renamed"
        rename(dir.path, renamed)
        defer { rename(renamed, dir.path) }
        let second = await iterator.next()
        #expect(second == .rootChanged)
        watcher.stop()
    }
}

struct FolderCheckTests {
    /// C6: exFAT, FAT, NTFS and network volumes are refused with an explanation.
    @Test func unsupportedVolumesAreRefused() {
        #expect(VolumePolicy.evaluate(typeName: "apfs", isLocal: true) == .supported)
        #expect(VolumePolicy.evaluate(typeName: "hfs", isLocal: true) == .supported)
        for type in ["exfat", "msdos", "ntfs"] {
            guard case .unsupported(let reason) = VolumePolicy.evaluate(typeName: type, isLocal: true) else {
                Issue.record("\(type) accepted")
                continue
            }
            #expect(reason.contains("APFS"))
        }
        for type in ["smbfs", "nfs", "afpfs", "webdav", "apfs"] {
            guard case .unsupported(let reason) = VolumePolicy.evaluate(typeName: type, isLocal: false) else {
                Issue.record("network \(type) accepted")
                continue
            }
            #expect(reason.contains("network"))
        }
        let here = TemporaryDirectory()
        #expect(VolumePolicy.check(path: here.path) == .supported)
    }

    /// C7: project-like folders are detected for explicit confirmation.
    @Test func projectFoldersAreDetected() {
        let plain = TemporaryDirectory()
        plain.file("notes.txt")
        #expect(ProjectFolderDetector.markers(in: plain.path).isEmpty)
        for marker in ["package.json", "Cargo.toml", "pyproject.toml", "go.mod"] {
            let project = TemporaryDirectory()
            project.file(marker)
            #expect(ProjectFolderDetector.markers(in: project.path) == [marker])
        }
        let git = TemporaryDirectory()
        _ = git.directory(".git")
        _ = git.directory("App.xcodeproj")
        #expect(ProjectFolderDetector.markers(in: git.path) == [".git", "App.xcodeproj"])
    }

    /// W3: the thumbnail cache stays under its limit and is cleared by Clear history.
    @Test func thumbnailCacheEvictsLeastRecentlyUsed() throws {
        let dir = TemporaryDirectory()
        let cache = ThumbnailCache(directory: URL(fileURLWithPath: dir.path), limit: 10_000)
        for index in 0..<10 {
            cache.store(Data(repeating: UInt8(index), count: 3_000), for: "thumb-\(index)")
            #expect(cache.totalSize <= 10_000)
        }
        #expect(cache.data(for: "thumb-9") != nil)
        #expect(cache.data(for: "thumb-0") == nil)
        cache.clear()
        #expect(cache.totalSize == 0)
    }

    @Test func factsReaderDetectsKinds() throws {
        let dir = TemporaryDirectory()
        let file = dir.file("IMG_1.png")
        let link = FileSystem.join(dir.path, "IMG_2.png")
        symlink(file, link)
        let hidden = dir.file(".hidden.png")
        let facts = try #require(FileFactsReader.read(path: file, isTopLevel: true)).facts
        #expect(facts.isRegularFile && !facts.isSymlink && !facts.hasMarker && facts.parentWritable)
        #expect(try #require(FileFactsReader.read(path: link, isTopLevel: true)).facts.isSymlink)
        #expect(try #require(FileFactsReader.read(path: hidden, isTopLevel: true)).facts.isHidden)
        try Marker(originalName: "x", state: .restored, firstRenamed: Date()).write(toPath: file)
        #expect(try #require(FileFactsReader.read(path: file, isTopLevel: true)).facts.hasMarker)
    }
}
