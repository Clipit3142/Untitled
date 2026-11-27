// Test-only helper for J3 (kill -9 during operations). Not part of the app.
//
// Usage: nomen-journal-harness <work directory> <history.sqlite> <operations> <seed>
//
// Renames random files in the work directory through the real executor and the real
// history database. The journal is wrapped so each step pauses briefly, which makes a
// SIGKILL from the test likely to land between "planned", the rename and "done".

import Foundation
import NomenCore
import NomenFS
import NomenStore

struct SlowJournal: JournalStore {
    let base: HistoryDatabase

    func insertPlanned(_ entry: JournalEntry) throws -> Int64 {
        let id = try base.insertPlanned(entry)
        usleep(UInt32.random(in: 0...3_000))
        return id
    }

    func markDone(_ id: Int64, newPath: String) throws {
        usleep(UInt32.random(in: 0...3_000))
        try base.markDone(id, newPath: newPath)
    }

    func markFailed(_ id: Int64, note: String) throws { try base.markFailed(id, note: note) }
    func markReverted(_ id: Int64) throws { try base.markReverted(id) }
    func plannedEntries() throws -> [JournalEntry] { try base.plannedEntries() }
    func entry(_ id: Int64) throws -> JournalEntry? { try base.entry(id) }
}

let arguments = CommandLine.arguments
guard arguments.count == 5, let count = Int(arguments[3]), let seed = UInt64(arguments[4]) else {
    FileHandle.standardError.write(Data("usage: nomen-journal-harness <dir> <db> <operations> <seed>\n".utf8))
    exit(2)
}
let directory = arguments[1]
let database = try HistoryDatabase(url: URL(fileURLWithPath: arguments[2]))
let executor = OperationExecutor(journal: SlowJournal(base: database), coordinator: DirectMove(),
                                 suppression: OwnOperationSuppression())
var counter = Int(seed % 1_000_000) * 10_000
for _ in 0..<count {
    let names = ((try? FileSystem.entries(ofDirectory: directory)) ?? []).filter { !$0.hasPrefix(".") && !$0.hasSuffix(".sqlite") }
    guard let name = names.randomElement(), let status = FileSystem.status(atPath: FileSystem.join(directory, name)), status.isRegularFile else {
        continue
    }
    counter += 1
    let number = counter
    let newName = "file-\(number).dat"
    _ = try? executor.execute(OperationRequest(
        directory: directory, expected: ExpectedFile(status: status, name: name), names: { n in n.map { "file-\(number)-\($0).dat" } ?? newName },
        grantedRoots: [directory], method: .automatic, marker: .renamed(originalName: name)
    ))
}
