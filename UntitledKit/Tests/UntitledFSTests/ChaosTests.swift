import Foundation
import Synchronization
import Testing
import UntitledTestSupport
@testable import UntitledFS
import UntitledCore
@testable import UntitledStore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// J1: a 10,000-operation chaos test runs concurrent creates, renames, moves, deletes,
/// writes, rules and undo across two watched folders. Every file is accounted for, every
/// content fingerprint is unchanged by Untitled, and there are 0 overwrites.
struct ChaosTests {
    /// What the "world" (other apps and the user) expects to exist: identity → content.
    final class Registry: Sendable {
        let state = Mutex<[FileIdentity: String]>([:])
        func set(_ identity: FileIdentity, _ print: String) { state.withLock { $0[identity] = print } }
        func remove(_ identity: FileIdentity) { state.withLock { _ = $0.removeValue(forKey: identity) } }
        var snapshot: [FileIdentity: String] { state.withLock { $0 } }
    }

    static func allFiles(under roots: [String]) -> [String] {
        var result: [String] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(atPath: root) else { continue }
            while let relative = enumerator.nextObject() as? String {
                let path = FileSystem.join(root, relative)
                if FileSystem.status(atPath: path)?.isRegularFile == true { result.append(path) }
            }
        }
        return result
    }

    @Test func tenThousandConcurrentOperations() throws {
        let root = TemporaryDirectory("chaos")
        let folderA = root.directory("Desktop")
        let folderB = root.directory("Downloads")
        let trash = root.directory("Trash")
        let roots = [folderA, folderB]
        let registry = Registry()
        let journal = InMemoryJournal()
        let executor = makeExecutor(journal: journal)
        let operations = Mutex(0)
        let target = 10_000

        @Sendable func take() -> Bool {
            operations.withLock { count in
                guard count < target else { return false }
                count += 1
                return true
            }
        }

        @Sendable func randomFile(_ g: inout SeededGenerator) -> String? {
            let folder = roots.randomElement(using: &g)!
            let candidates = Self.allFiles(under: [folder])
            return candidates.randomElement(using: &g)
        }

        // The world: creates, renames, moves, deletes and writes.
        let world = Thread {
            var g = SeededGenerator(seed: 1)
            var created = 0
            while take() {
                switch Int.random(in: 0..<10, using: &g) {
                case 0...2:
                    created += 1
                    let folder = roots.randomElement(using: &g)!
                    let path = FileSystem.join(folder, "IMG_\(created).jpg")
                    let contents = "file \(created) \(UInt64.random(in: 0...UInt64.max, using: &g))"
                    let fd = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
                    guard fd >= 0 else { continue }
                    _ = contents.withCString { write(fd, $0, strlen($0)) }
                    let identity = FileSystem.identity(ofDescriptor: fd)
                    close(fd)
                    if let identity { registry.set(identity, "\(contents.utf8.count)") }
                case 3, 4:
                    guard let path = randomFile(&g) else { continue }
                    let renamed = FileSystem.join(FileSystem.parent(path), "user-\(UUID().uuidString.prefix(8)).jpg")
                    _ = untitledRenameNoReplace(path, renamed)
                case 5:
                    guard let path = randomFile(&g) else { continue }
                    let other = roots.randomElement(using: &g)!
                    _ = untitledRenameNoReplace(path, FileSystem.join(other, "moved-\(UUID().uuidString.prefix(8)).jpg"))
                case 6:
                    // Delete by moving to the trash, then record exactly what was moved.
                    guard let path = randomFile(&g) else { continue }
                    let destination = FileSystem.join(trash, UUID().uuidString)
                    if untitledRenameNoReplace(path, destination) == 0, let status = FileSystem.status(atPath: destination) {
                        registry.remove(status.identity)
                    }
                default:
                    // Append through a descriptor, so a concurrent rename cannot redirect the write.
                    guard let path = randomFile(&g) else { continue }
                    let fd = open(path, O_WRONLY | O_APPEND | O_NOFOLLOW)
                    guard fd >= 0 else { continue }
                    guard let identity = FileSystem.identity(ofDescriptor: fd) else { close(fd); continue }
                    let addition = "+more"
                    _ = addition.withCString { write(fd, $0, strlen($0)) }
                    var info = stat()
                    fstat(fd, &info)
                    close(fd)
                    registry.state.withLock { map in
                        if map[identity] != nil { map[identity] = "\(info.st_size)" }
                    }
                }
            }
        }

        // Untitled: renames, rule moves into destination subfolders, and undo.
        let untitled = Thread {
            var g = SeededGenerator(seed: 2)
            var counter = 0
            while take() {
                counter += 1
                let choice = Int.random(in: 0..<10, using: &g)
                if choice < 2 {
                    // Undo a random completed operation.
                    let done = journal.all.filter { $0.state == .done && $0.method != .undo }
                    guard let entry = done.randomElement(using: &g),
                          let status = FileSystem.status(atPath: entry.newPath), status.identity == entry.identity else { continue }
                    let originalDirectory = FileSystem.parent(entry.oldPath)
                    let originalName = entry.oldName
                    _ = try? executor.execute(OperationRequest(
                        directory: FileSystem.parent(entry.newPath), expected: ExpectedFile(status: status, name: entry.newName),
                        destinationDirectory: originalDirectory,
                        names: { n in n.map { "\(FileExtension.split(originalName).base) \($0).jpg" } ?? originalName },
                        grantedRoots: roots, method: .undo, metadata: JournalMetadata(revertsEntryID: entry.id), marker: .restored
                    ))
                    continue
                }
                guard let path = randomFile(&g), let status = FileSystem.status(atPath: path), status.isRegularFile else { continue }
                let directory = FileSystem.parent(path)
                let name = FileSystem.name(path)
                let base = "Untitled \(counter % 37)"
                let move = choice < 5
                let folderRoot = roots.first { FileSystem.isInside(path, root: $0) } ?? directory
                _ = try? executor.execute(OperationRequest(
                    directory: directory, expected: ExpectedFile(status: status, name: name),
                    destinationDirectory: move ? folderRoot : directory, subfolders: move ? ["Filed", "2026"] : [],
                    names: { n in n.map { "\(base)-\($0).jpg" } ?? "\(base).jpg" }, grantedRoots: roots,
                    method: .automatic, marker: .renamed(originalName: name)
                ))
            }
        }

        world.start()
        untitled.start()
        while !world.isFinished || !untitled.isFinished { usleep(1_000) }

        // Every file the world expects exists exactly once, with the content it wrote.
        var found: [FileIdentity: [String]] = [:]
        for path in Self.allFiles(under: roots) {
            if let status = FileSystem.status(atPath: path) { found[status.identity, default: []].append(path) }
        }
        let expectedFiles = registry.snapshot
        #expect(expectedFiles.count > 100)
        for (identity, size) in expectedFiles {
            let paths = found[identity] ?? []
            #expect(paths.count == 1, "\(identity) found \(paths.count) times")
            if let path = paths.first {
                #expect("\(FileSystem.status(atPath: path)!.size)" == size, "content changed at \(path)")
            }
        }
        #expect(Set(found.keys) == Set(expectedFiles.keys), "no unexpected files and no lost files")
        #expect(operations.withLock { $0 } == target)
        #expect(journal.all.allSatisfy { $0.state != .planned })
    }
}

/// Renames without replacing, for the simulated world.
func untitledRenameNoReplace(_ from: String, _ to: String) -> Int32 {
    FileSystem.renameExclusive(from, to)
}

/// J3: kill -9 at random points during 1,000 operations leaves every planned entry
/// reconciled correctly after relaunch.
struct CrashRecoveryTests {
    static func harnessPath() throws -> String {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var directory = executable.deletingLastPathComponent()
        for _ in 0..<4 {
            let candidate = directory.appendingPathComponent("untitled-journal-harness").path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            directory = directory.deletingLastPathComponent()
        }
        let products = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build")
        let enumerator = FileManager.default.enumerator(atPath: products.path)
        while let relative = enumerator?.nextObject() as? String {
            if relative.hasSuffix("/untitled-journal-harness") {
                let path = products.appendingPathComponent(relative).path
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    @Test(.timeLimit(.minutes(10)))
    func killNineDuringOperationsReconcilesCorrectly() async throws {
        let harness = try Self.harnessPath()
        let dir = TemporaryDirectory("crash")
        let work = dir.directory("work")
        var prints: [String: FileIdentity] = [:]
        for index in 0..<40 {
            let path = FileSystem.join(work, "IMG_\(index).jpg")
            _ = FileManager.default.createFile(atPath: path, contents: Data("unique \(index) \(UUID())".utf8))
            prints[fingerprint(path)!] = FileSystem.status(atPath: path)!.identity
        }
        let dbURL = URL(fileURLWithPath: FileSystem.join(dir.path, "history.sqlite"))
        var g = SeededGenerator(seed: 0x4A33)
        var kills = 0
        var cycle = 0
        while true {
            let database = try HistoryDatabase(url: dbURL)
            if database.operationCount >= 1_000 { break }
            cycle += 1
            let process = Process()
            process.executableURL = URL(fileURLWithPath: harness)
            process.arguments = [work, dbURL.path, "200", String(cycle)]
            try process.run()
            try await Task.sleep(for: .milliseconds(Int.random(in: 30...250, using: &g)))
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                kills += 1
            }
            process.waitUntilExit()

            // Relaunch: reconcile, then check the journal against the disk.
            let relaunched = try HistoryDatabase(url: dbURL)
            _ = try Reconciler(journal: relaunched).reconcile()
            #expect(try relaunched.plannedEntries().isEmpty)
            try Self.verify(relaunched, work: work, prints: prints)
        }
        #expect(kills >= 5, "the harness was killed mid-run \(kills) times")
    }

    static func verify(_ database: HistoryDatabase, work: String, prints: [String: FileIdentity]) throws {
        // The same files, by content and identity, and nothing else.
        let names = try FileSystem.entries(ofDirectory: work).filter { !$0.hasPrefix(".") }
        #expect(names.count == prints.count)
        var located: [FileIdentity: String] = [:]
        for name in names {
            let path = FileSystem.join(work, name)
            let print = try #require(fingerprint(path))
            let identity = try #require(prints[print], "unknown content in \(name)")
            #expect(FileSystem.status(atPath: path)?.identity == identity)
            located[identity] = path
        }
        // Replaying completed entries reproduces where every file is.
        let entries = try database.entries(sql: "SELECT * FROM operation ORDER BY id")
        var replayed: [FileIdentity: String] = [:]
        for entry in entries where entry.state == .done {
            replayed[entry.identity] = entry.newPath
        }
        for (identity, path) in located {
            if let expectedPath = replayed[identity] {
                #expect(expectedPath == path, "journal says \(expectedPath), file is at \(path)")
                #expect(Marker.read(atPath: path) != nil, "renamed files carry a marker")
            } else {
                #expect(FileSystem.name(path).hasPrefix("IMG_"), "\(path) moved without a done entry")
            }
        }
    }
}
