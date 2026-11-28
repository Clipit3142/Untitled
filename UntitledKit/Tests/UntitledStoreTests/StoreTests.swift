import Foundation
import Testing
@testable import UntitledStore
import UntitledCore
import UntitledFS

private func temporaryURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("untitled-store-\(UUID().uuidString)").appendingPathComponent(name)
}

private func entry(_ index: Int, state: JournalState = .done, time: Date = Date(), old: String? = nil, new: String? = nil) -> JournalEntry {
    JournalEntry(time: time, identity: FileIdentity(device: 1, inode: UInt64(index), birth: 7),
                 oldPath: "/Users/me/Desktop/\(old ?? "Screenshot \(index).png")", newPath: "/Users/me/Desktop/\(new ?? "Renamed \(index).png")",
                 method: .automatic, styleID: "preset.clean", styleVersion: 1, namingPath: .model, confidence: .high, state: state)
}

struct ConfigDatabaseTests {
    @Test func roundTripsConfiguration() throws {
        let db = try ConfigDatabase(url: nil)
        let folder = GrantedFolder(path: "/Users/me/Desktop", role: .watched, watchStart: Date(timeIntervalSince1970: 1_000))
        try db.save(folder)
        #expect(try db.folders() == [folder])
        var style = Presets.compact
        style.id = "mine"
        try db.save(style)
        #expect(try db.style(id: "mine") == style)
        let rules = [Rule(id: "r1", name: "Invoices", conditions: [.kindIs(.builtIn(.invoice))], destinationID: "d"),
                     Rule(id: "r2", name: "Screens", conditions: [.isScreenshot(true)], destinationID: "d")]
        try db.saveRules(rules)
        #expect(try db.rules() == rules)
        try db.saveRules(rules.reversed())
        #expect(try db.rules().map(\.id) == ["r2", "r1"], "order is kept")
        try db.saveCustomKinds([CustomKind(id: "k", label: "Warranty")])
        #expect(try db.customKinds() == [CustomKind(id: "k", label: "Warranty")])
        var examples = ExampleList()
        examples.add("2026-11-27 Swisscom Invoice.pdf")
        try db.saveExamples(examples, styleID: "mine")
        #expect(try db.examples(styleID: "mine") == examples)
        let pause = PauseState(option: .untilTomorrow, until: Date(timeIntervalSince1970: 2_000))
        try db.setSetting(pause, key: "pause")
        #expect(try db.setting(PauseState.self, key: "pause") == pause)
        let identity = FileIdentity(device: 1, inode: 2, birth: 3)
        try db.ignore(identity: identity, name: "IMG_1.png", at: Date())
        #expect(try db.isIgnored(identity: identity))
        #expect(try !db.isIgnored(identity: FileIdentity(device: 1, inode: 2, birth: 4)))
    }

    /// H7 at the storage boundary: invalid styles can't be saved.
    @Test func invalidStylesAreRefused() throws {
        let db = try ConfigDatabase(url: nil)
        var style = Presets.clean
        style.vocabulary = [VocabularyRule(from: "a", to: "b"), VocabularyRule(from: "b", to: "a")]
        #expect(throws: StoreError.self) { try db.save(style) }
        #expect(try db.styles().isEmpty)
    }

    /// O5: Clear learned data and Reset do exactly what they say.
    @Test func clearLearnedDataAndReset() throws {
        let db = try ConfigDatabase(url: nil)
        try db.save(Presets.clean)
        try db.save(GrantedFolder(path: "/x", role: .watched, watchStart: Date()))
        try db.addLearningEvents([EditEvent(pattern: .fillerRemoved, styleID: "s", date: Date())])
        var examples = ExampleList()
        examples.add("A.pdf")
        try db.saveExamples(examples, styleID: "s")
        var answers = SuggestionAnswers()
        answers.neverAsk.insert("s|filler")
        try db.saveSuggestionAnswers(answers)
        try db.setSetting(true, key: "showInDock")

        try db.clearLearnedData()
        var counts = try db.rowCounts()
        #expect(counts["learningEvent"] == 0 && counts["example"] == 0)
        #expect(try db.suggestionAnswers() == SuggestionAnswers())
        #expect(counts["style"] == 1 && counts["folder"] == 1 && counts["setting"] == 1, "everything else stays")

        try db.resetAll()
        counts = try db.rowCounts()
        #expect(counts.values.allSatisfy { $0 == 0 })
    }
}

struct HistoryDatabaseTests {
    @Test func journalStates() throws {
        let db = try HistoryDatabase(url: nil)
        let id = try db.insertPlanned(entry(1))
        #expect(try db.plannedEntries().map(\.id) == [id])
        try db.markDone(id, newPath: "/Users/me/Desktop/Final.png")
        #expect(try db.entry(id)?.state == .done)
        #expect(try db.entry(id)?.newName == "Final.png")
        #expect(try db.plannedEntries().isEmpty)
        try db.markReverted(id)
        #expect(try db.entry(id)?.state == .reverted)
        let failed = try db.insertPlanned(entry(2))
        try db.markFailed(failed, note: String(repeating: "x", count: 500))
        #expect(try db.entry(failed)?.note?.count == 200)
    }

    @Test func searchFindsOldAndNewNamesQuickly() throws {
        let url = temporaryURL("history.sqlite")
        let db = try HistoryDatabase(url: url)
        try db.pool.write { database in
            for index in 0..<100_000 {
                try database.execute(sql: """
                    INSERT INTO operation (time, device, inode, birth, oldPath, newPath, oldName, newName, method, state)
                    VALUES (?, 1, ?, 0, ?, ?, ?, ?, 'automatic', 'done')
                    """, arguments: [Date(), index, "/d/Screenshot \(index).png", "/d/Booking \(index).png", "Screenshot \(index).png", "Booking \(index).png"])
            }
        }
        let start = Date()
        let byNew = try db.search("booking 99999")
        let byOld = try db.search("SCREENSHOT 4242")
        let elapsed = Date().timeIntervalSince(start) / 2
        #expect(byNew.first?.newName == "Booking 99999.png")
        #expect(byOld.contains { $0.oldName == "Screenshot 4242.png" })
        #expect(elapsed <= 0.2, "search took \(elapsed) s across 100,000 entries")
    }

    /// L6: purges never touch planned entries or queued items.
    @Test func purgeKeepsPlannedEntriesAndQueue() throws {
        let db = try HistoryDatabase(url: nil)
        let old = Date(timeIntervalSince1970: 1_000)
        let planned = try db.insertPlanned(entry(1, time: old))
        let done = try db.insertPlanned(entry(2, time: old))
        try db.markDone(done, newPath: "/x/y.png")
        let recent = try db.insertPlanned(entry(3))
        try db.markDone(recent, newPath: "/x/z.png")
        let item = QueueItem(arrival: 1, folderID: "f", directory: "/d",
                             expected: ExpectedFile(identity: FileIdentity(device: 1, inode: 9), size: 1, modification: 1, name: "IMG.png"),
                             dateAdded: old, status: .review, createdAt: old)
        try db.save(item)
        let removed = try db.purge(before: Date().addingTimeInterval(-90 * 86_400))
        #expect(removed >= 1)
        #expect(try db.entry(planned)?.state == .planned)
        #expect(try db.entry(done) == nil)
        #expect(try db.entry(recent) != nil)
        #expect(try db.queueItems() == [item])
    }

    /// O5: Clear history removes finished entries and notes, keeps planned entries and the queue.
    @Test func clearHistory() throws {
        let db = try HistoryDatabase(url: nil)
        let planned = try db.insertPlanned(entry(1))
        let done = try db.insertPlanned(entry(2))
        try db.markDone(done, newPath: "/a/b.png")
        try db.addNote(ActivityNote(time: Date(), message: "note"))
        let item = QueueItem(arrival: 1, folderID: nil, directory: "/d",
                             expected: ExpectedFile(identity: FileIdentity(device: 1, inode: 9), size: 1, modification: 1, name: "a.png"),
                             dateAdded: nil, status: .pending, createdAt: Date())
        try db.save(item)
        try db.clearHistory()
        #expect(try db.entry(done) == nil)
        #expect(try db.entry(planned) != nil)
        #expect(try db.notes().isEmpty)
        #expect(try db.queueItems().count == 1)
    }

    /// L7: a corrupted history database is detected, set aside and recreated, with configuration intact.
    @Test func corruptedHistoryIsRecreated() throws {
        let url = temporaryURL("history.sqlite")
        let configURL = url.deletingLastPathComponent().appendingPathComponent("config.sqlite")
        let config = try ConfigDatabase(url: configURL)
        try config.save(GrantedFolder(path: "/Users/me/Desktop", role: .watched, watchStart: Date()))
        do {
            let db = try HistoryDatabase(url: url)
            _ = try db.insertPlanned(entry(1))
        }
        try Data(repeating: 0x42, count: 8_192).write(to: url)
        let (recovered, wasRecovered) = try HistoryDatabase.openRecovering(url: url)
        #expect(wasRecovered)
        #expect(try recovered.plannedEntries().isEmpty)
        _ = try recovered.insertPlanned(entry(2))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(siblings.contains { $0.contains("corrupt") }, "the damaged file is set aside")
        #expect(try ConfigDatabase(url: configURL).folders().count == 1)
        let (_, again) = try HistoryDatabase.openRecovering(url: url)
        #expect(!again)
    }

    @Test func seenFilesAreRecognizedByIdentityAndDateAdded() throws {
        let db = try HistoryDatabase(url: nil)
        let added = Date(timeIntervalSince1970: 5_000)
        let id = try db.insertPlanned(entry(5))
        try db.setDateAdded(added, for: id)
        let identity = FileIdentity(device: 1, inode: 5, birth: 7)
        #expect(try db.hasSeen(identity: identity, dateAdded: added))
        #expect(try !db.hasSeen(identity: identity, dateAdded: added.addingTimeInterval(60)))
        #expect(try !db.hasSeen(identity: FileIdentity(device: 1, inode: 6, birth: 7), dateAdded: added))
    }

    /// M3 (storage): the queue survives reopening.
    @Test func queueSurvivesRestart() throws {
        let url = temporaryURL("history.sqlite")
        let item = QueueItem(arrival: 3, folderID: "f", directory: "/d",
                             expected: ExpectedFile(identity: FileIdentity(device: 1, inode: 9, birth: 1), size: 10, modification: 2, name: "IMG.png"),
                             dateAdded: Date(timeIntervalSince1970: 9), status: .review, burstGroup: "burst-1", createdAt: Date(timeIntervalSince1970: 10))
        do { try HistoryDatabase(url: url).save(item) }
        #expect(try HistoryDatabase(url: url).queueItems() == [item])
    }

    /// W1 and E4: the schema stores names, paths, bookmarks, short fields and settings only,
    /// and long free text is capped at 200 characters.
    @Test func schemaAudit() throws {
        let db = try HistoryDatabase(url: nil)
        let schema = try db.schema()
        #expect(schema["operation"]?.contains("text") == false)
        #expect(schema.values.flatMap { $0 }.allSatisfy { !$0.lowercased().contains("content") })
        let long = String(repeating: "word ", count: 200)
        let proposal = Proposal(
            fields: NameFields(kind: .other, source: long, subject: long, app: long, original: long),
            fileName: "x.png", parts: [RenderedPart(token: .subject, text: long, required: true)],
            evidence: [PartEvidence(token: .subject, explanation: long)], confidence: .low, lowReasons: [],
            styleID: "s", styleVersion: 1, path: .model, language: .english, isScreenshot: false
        )
        let item = QueueItem(arrival: 1, folderID: nil, directory: "/d",
                             expected: ExpectedFile(identity: FileIdentity(device: 1, inode: 1), size: 1, modification: 1, name: "x.png"),
                             dateAdded: nil, status: .review, proposal: proposal, createdAt: Date())
        try db.save(item)
        let stored = try #require(try db.queueItems().first?.proposal)
        #expect(stored.fields.subject.count <= 200 && (stored.fields.source ?? "").count <= 200)
        #expect(stored.fields.app!.count <= 200 && stored.fields.original!.count <= 200)
        #expect(stored.parts.allSatisfy { $0.text.count <= 200 })
        #expect(stored.evidence.allSatisfy { $0.explanation.count <= 200 })
    }
}
