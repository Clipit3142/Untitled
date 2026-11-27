import Foundation
import Testing
@testable import NomenFS
import NomenCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

struct ExecutorTests {
    @Test func renamesFollowTheJournalSequence() throws {
        let dir = TemporaryDirectory()
        let source = dir.file("Screenshot 2026-11-27 at 14.05.12.png")
        let before = fingerprint(source)
        let journal = InMemoryJournal()
        let executor = makeExecutor(journal: journal)
        let outcome = try executor.execute(OperationRequest(
            directory: dir.path, expected: expected(source), names: { _ in "2026-11-27 Safari Flight Booking.png" },
            grantedRoots: [dir.path], method: .automatic, marker: .renamed(originalName: "Screenshot 2026-11-27 at 14.05.12.png")
        ))
        #expect(FileSystem.name(outcome.newPath) == "2026-11-27 Safari Flight Booking.png")
        #expect(!FileSystem.exists(source))
        #expect(fingerprint(outcome.newPath) == before)
        let entry = try #require(try journal.entry(outcome.entryID))
        #expect(entry.state == .done)
        #expect(entry.oldName == "Screenshot 2026-11-27 at 14.05.12.png")
        let marker = try #require(Marker.read(atPath: outcome.newPath))
        #expect(marker.originalName == "Screenshot 2026-11-27 at 14.05.12.png")
        #expect(marker.state == .renamed)
        #expect(executor.suppression.isSuppressed(entry.identity))
    }

    /// J8: collision suffixes match 3.13 (case-insensitive), and the 100th collision fails safely.
    @Test func collisionSuffixesAndTheHundredthCollision() throws {
        let dir = TemporaryDirectory()
        dir.file("Invoice.pdf")
        dir.file("invoice-2.PDF")
        let source = dir.file("scan0001.pdf")
        let outcome = try makeExecutor().execute(OperationRequest(
            directory: dir.path, expected: expected(source), names: suffixedNames("Invoice"),
            grantedRoots: [dir.path], method: .automatic, marker: .renamed(originalName: "scan0001.pdf")
        ))
        #expect(FileSystem.name(outcome.newPath) == "Invoice-3.pdf")
        #expect(outcome.collisionNumber == 3)

        let full = TemporaryDirectory()
        full.file("Report.pdf")
        for n in 2...99 { full.file("Report-\(n).pdf") }
        let lonely = full.file("scan0002.pdf")
        let print = fingerprint(lonely)
        let journal = InMemoryJournal()
        #expect(throws: OperationError.collisionLimit) {
            try makeExecutor(journal: journal).execute(OperationRequest(
                directory: full.path, expected: expected(lonely), names: suffixedNames("Report"),
                grantedRoots: [full.path], method: .automatic, marker: .renamed(originalName: "scan0002.pdf")
            ))
        }
        #expect(fingerprint(lonely) == print, "the file is untouched")
        #expect(Marker.read(atPath: lonely) == nil)
        #expect(journal.all.first?.state == .failed)
    }

    @Test func caseOnlyRenameWorks() throws {
        let dir = TemporaryDirectory()
        let source = dir.file("invoice.pdf")
        let outcome = try makeExecutor().execute(OperationRequest(
            directory: dir.path, expected: expected(source), names: { _ in "Invoice.pdf" },
            grantedRoots: [dir.path], method: .quickRename, marker: .renamed(originalName: "invoice.pdf")
        ))
        #expect(FileSystem.name(outcome.newPath) == "Invoice.pdf")
        #expect(dir.names == ["Invoice.pdf"])
    }

    /// J2: 1,000 races to create the target name cause 0 overwrites.
    @Test func racesForTheTargetNameNeverOverwrite() throws {
        let dir = TemporaryDirectory()
        let executor = makeExecutor()
        for round in 0..<1_000 {
            let source = dir.file("IMG_\(round).jpg", contents: "ours \(round)")
            let target = "Target \(round).jpg"
            let theirs = "theirs \(round)"
            let racer = Thread {
                let fd = open(FileSystem.join(dir.path, target), O_CREAT | O_EXCL | O_WRONLY, 0o644)
                if fd >= 0 {
                    _ = theirs.withCString { write(fd, $0, strlen($0)) }
                    close(fd)
                }
            }
            racer.start()
            let outcome = try? executor.execute(OperationRequest(
                directory: dir.path, expected: expected(source),
                names: { n in n.map { "Target \(round)-\($0).jpg" } ?? target },
                grantedRoots: [dir.path], method: .automatic, marker: .renamed(originalName: "IMG_\(round).jpg")
            ))
            while !racer.isFinished { usleep(50) }
            // Both contents survive somewhere.
            let contents = Set(dir.names.filter { $0.hasPrefix("Target \(round)") || $0 == "IMG_\(round).jpg" }
                .compactMap { FileManager.default.contents(atPath: FileSystem.join(dir.path, $0)) }
                .map { String(decoding: $0, as: UTF8.self) })
            #expect(contents.contains("ours \(round)"), "round \(round)")
            if FileSystem.exists(FileSystem.join(dir.path, target)), outcome?.newPath != FileSystem.join(dir.path, target) {
                #expect(contents.contains(theirs), "round \(round)")
            }
        }
    }

    /// D7: in 1,000 scripted races where someone else renames the file mid-process, Nomen renames it 0 times.
    @Test func filesRenamedBySomeoneElseAreLeftAlone() throws {
        let dir = TemporaryDirectory()
        let journal = InMemoryJournal()
        let executor = makeExecutor(journal: journal)
        var nomenRenames = 0
        for round in 0..<1_000 {
            let source = dir.file("Screenshot \(round).png")
            let seen = expected(source)
            // Someone else renames the file between detection and execution.
            let theirName = round % 3 == 0 ? "screenshot \(round).png" : "Holiday \(round).png"
            rename(source, FileSystem.join(dir.path, theirName))
            do {
                _ = try executor.execute(OperationRequest(
                    directory: dir.path, expected: seen, names: { _ in "Nomen \(round).png" },
                    grantedRoots: [dir.path], method: .automatic, marker: .renamed(originalName: seen.name)
                ))
                nomenRenames += 1
            } catch {
                #expect(error == .namedBySomeoneElse)
            }
            #expect(FileSystem.exists(FileSystem.join(dir.path, theirName)))
            #expect(Marker.read(atPath: FileSystem.join(dir.path, theirName)) == nil)
        }
        #expect(nomenRenames == 0)
        #expect(journal.all.allSatisfy { $0.state == .failed && $0.note == "Named by someone else" })
    }

    @Test func concurrentRenamesBySomeoneElseStayConsistent() throws {
        let dir = TemporaryDirectory()
        let executor = makeExecutor()
        for round in 0..<300 {
            let source = dir.file("IMG_\(round).heic")
            let seen = expected(source)
            let racer = Thread { rename(source, FileSystem.join(dir.path, "Theirs \(round).heic")) }
            racer.start()
            let outcome = try? executor.execute(OperationRequest(
                directory: dir.path, expected: seen, names: { _ in "Ours \(round).heic" },
                grantedRoots: [dir.path], method: .automatic, marker: .renamed(originalName: seen.name)
            ))
            while !racer.isFinished { usleep(50) }
            let ours = FileSystem.exists(FileSystem.join(dir.path, "Ours \(round).heic"))
            let theirs = FileSystem.exists(FileSystem.join(dir.path, "Theirs \(round).heic"))
            #expect(ours != theirs, "exactly one name wins")
            #expect(ours == (outcome != nil))
        }
    }

    /// J6, W4: dates, tags, comments, quarantine and other extended attributes are unchanged.
    @Test func attributesAndDatesAreUnchanged() throws {
        let dir = TemporaryDirectory()
        let destination = dir.directory("Filed")
        let source = dir.file("IMG_0001.jpg")
        let attributes: [String: Data] = [
            "com.apple.quarantine": Data("0081;65a1b2c3;Safari;".utf8),
            "com.apple.metadata:_kMDItemUserTags": Data([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74]),
            "com.apple.metadata:kMDItemFinderComment": Data("A comment".utf8),
            "com.apple.metadata:kMDItemWhereFroms": Data("https://example.com".utf8),
            "com.example.custom": Data([0, 1, 2, 3]),
        ]
        for (name, value) in attributes { try ExtendedAttributes.set(name, data: value, atPath: source) }
        var times = [timespec(tv_sec: 1_700_000_000, tv_nsec: 0), timespec(tv_sec: 1_600_000_000, tv_nsec: 123_000_000)]
        utimensat(AT_FDCWD, source, &times, AT_SYMLINK_NOFOLLOW)
        let before = try #require(FileSystem.status(atPath: source))
        let contentBefore = fingerprint(source)

        let journal = InMemoryJournal()
        let executor = makeExecutor(journal: journal)
        let renamed = try executor.execute(OperationRequest(
            directory: dir.path, expected: expected(source), destinationDirectory: destination, subfolders: ["2026"],
            names: { _ in "Beach.jpg" }, grantedRoots: [dir.path], method: .automatic,
            marker: .renamed(originalName: "IMG_0001.jpg")
        ))
        func check(_ path: String) throws {
            let after = try #require(FileSystem.status(atPath: path))
            #expect(after.modification == before.modification)
            #expect(after.size == before.size)
            #expect(fingerprint(path) == contentBefore)
            var current = ExtendedAttributes.all(atPath: path)
            current.removeValue(forKey: Marker.attributeName)
            #expect(current == attributes)
        }
        try check(renamed.newPath)

        // Undo back to the original folder and name.
        let undone = try executor.execute(OperationRequest(
            directory: FileSystem.parent(renamed.newPath), expected: expected(renamed.newPath), destinationDirectory: dir.path,
            names: { n in n.map { "IMG_0001 \($0).jpg" } ?? "IMG_0001.jpg" }, grantedRoots: [dir.path], method: .undo,
            metadata: JournalMetadata(revertsEntryID: renamed.entryID), marker: .restored
        ))
        #expect(undone.newPath == source)
        try check(undone.newPath)
        #expect(Marker.read(atPath: source)?.state == .restored)
        #expect(try journal.entry(renamed.entryID)?.state == .reverted)
    }

    /// J7: the marker always holds the first original name, and its state switches correctly.
    @Test func markerKeepsTheFirstOriginalName() throws {
        let dir = TemporaryDirectory()
        let executor = makeExecutor()
        var path = dir.file("IMG_7.png")
        let steps: [(String, MarkerAction, Marker.State)] = [
            ("First.png", .renamed(originalName: "IMG_7.png"), .renamed),
            ("Second.png", .renamed(originalName: "First.png"), .renamed),
            ("IMG_7.png", .restored, .restored),
            ("Third.png", .renamed(originalName: "IMG_7.png"), .renamed),
        ]
        var firstDate: Date?
        for (name, action, state) in steps {
            let outcome = try executor.execute(OperationRequest(
                directory: dir.path, expected: expected(path), names: { _ in name }, grantedRoots: [dir.path],
                method: .quickRename, marker: action
            ))
            path = outcome.newPath
            let marker = try #require(Marker.read(atPath: path))
            #expect(marker.originalName == "IMG_7.png")
            #expect(marker.state == state)
            if firstDate == nil { firstDate = marker.firstRenamed }
            #expect(marker.firstRenamed == firstDate)
        }
    }

    /// J9: no cross-volume move is ever attempted.
    @Test func crossVolumeMovesAreRefused() throws {
        guard let other = FileSystem.status(atPath: "/dev/shm"), other.isDirectory else { return }
        let dir = TemporaryDirectory()
        guard FileSystem.status(atPath: dir.path)?.identity.device != other.identity.device else { return }
        let elsewhere = "/dev/shm/nomen-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: elsewhere, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: elsewhere) }
        let source = dir.file("scan.pdf")
        let journal = InMemoryJournal()
        #expect(throws: OperationError.crossVolume) {
            try makeExecutor(journal: journal).execute(OperationRequest(
                directory: dir.path, expected: expected(source), destinationDirectory: elsewhere, names: { _ in "Moved.pdf" },
                grantedRoots: [dir.path, elsewhere], method: .automatic, marker: .renamed(originalName: "scan.pdf")
            ))
        }
        #expect(journal.all.isEmpty, "nothing was planned or attempted")
        #expect(FileSystem.exists(source))
    }

    @Test func destinationsOutsideGrantedFoldersAndEscapesAreRefused() throws {
        let dir = TemporaryDirectory()
        let source = dir.file("scan.pdf")
        #expect(throws: OperationError.outsideGrantedFolders) {
            try makeExecutor().execute(OperationRequest(
                directory: dir.path, expected: expected(source), destinationDirectory: FileSystem.parent(dir.path),
                names: { _ in "Out.pdf" }, grantedRoots: [dir.path], method: .automatic, marker: .renamed(originalName: "scan.pdf")
            ))
        }
        #expect(throws: OperationError.outsideGrantedFolders) {
            try makeExecutor().execute(OperationRequest(
                directory: dir.path, expected: expected(source), subfolders: ["..", "x"], names: { _ in "Out.pdf" },
                grantedRoots: [dir.path], method: .automatic, marker: .renamed(originalName: "scan.pdf")
            ))
        }
        #expect(throws: OperationError.invalidName) {
            try makeExecutor().execute(OperationRequest(
                directory: dir.path, expected: expected(source), names: { _ in "../escape.pdf" },
                grantedRoots: [dir.path], method: .automatic, marker: .renamed(originalName: "scan.pdf")
            ))
        }
        let destination = dir.directory("Missing")
        try FileManager.default.removeItem(atPath: destination)
        #expect(throws: OperationError.destinationMissing) {
            try makeExecutor().execute(OperationRequest(
                directory: dir.path, expected: expected(source), destinationDirectory: destination, names: { _ in "x.pdf" },
                grantedRoots: [dir.path], method: .automatic, marker: .renamed(originalName: "scan.pdf")
            ))
        }
        #expect(FileSystem.exists(source))
    }

    @Test func changedFilesAndSymlinksAreNotRenamed() throws {
        let dir = TemporaryDirectory()
        let source = dir.file("download.pdf")
        let seen = expected(source)
        let handle = try #require(FileHandle(forWritingAtPath: source))
        handle.seekToEndOfFile()
        handle.write(Data("grown".utf8))
        try handle.close()
        #expect(throws: OperationError.fileChanged) {
            try makeExecutor().execute(OperationRequest(
                directory: dir.path, expected: seen, names: { _ in "x.pdf" }, grantedRoots: [dir.path],
                method: .automatic, marker: .renamed(originalName: "download.pdf")
            ))
        }
        let target = dir.file("real.pdf")
        let link = FileSystem.join(dir.path, "link.pdf")
        symlink(target, link)
        let linkStatus = try #require(FileSystem.status(atPath: link))
        #expect(linkStatus.isSymlink)
        #expect(throws: OperationError.namedBySomeoneElse) {
            try makeExecutor().execute(OperationRequest(
                directory: dir.path, expected: ExpectedFile(status: linkStatus, name: "link.pdf"), names: { _ in "y.pdf" },
                grantedRoots: [dir.path], method: .automatic, marker: .renamed(originalName: "link.pdf")
            ))
        }
    }

    /// X4: when the journal can't be written, nothing happens.
    @Test func noOperationWithoutAJournalEntry() throws {
        struct FullDisk: JournalStore {
            struct DiskFull: Error {}
            func insertPlanned(_ entry: JournalEntry) throws -> Int64 { throw DiskFull() }
            func markDone(_ id: Int64, newPath: String) throws {}
            func markFailed(_ id: Int64, note: String) throws {}
            func markReverted(_ id: Int64) throws {}
            func plannedEntries() throws -> [JournalEntry] { [] }
            func entry(_ id: Int64) throws -> JournalEntry? { nil }
        }
        let dir = TemporaryDirectory()
        let source = dir.file("scan.pdf")
        #expect(throws: OperationError.journalUnavailable) {
            try makeExecutor(journal: FullDisk()).execute(OperationRequest(
                directory: dir.path, expected: expected(source), names: { _ in "x.pdf" }, grantedRoots: [dir.path],
                method: .automatic, marker: .renamed(originalName: "scan.pdf")
            ))
        }
        #expect(dir.names == ["scan.pdf"])
    }
}
