import Foundation
import Testing
@testable import UntitledEngine
import UntitledCore
import UntitledFS
@testable import UntitledStore
import UntitledModel
import UntitledExtract

@Suite(.serialized)
struct EngineTests {
    static let expectedInvoice = "2026-11-27 Swisscom Invoice Mobile Subscription November.pdf"

    @Test func automaticRenameEndToEnd() async throws {
        let h = try await EngineHarness(mode: .automatic)
        let path = h.file("scan0001.pdf", EngineHarness.invoice)
        let renamed = await eventually { h.desktopNames.contains(Self.expectedInvoice) }
        #expect(renamed, "\(h.desktopNames)")
        #expect(!FileSystem.exists(path))
        let marker = Marker.read(atPath: FileSystem.join(h.desktop, Self.expectedInvoice))
        #expect(marker?.originalName == "scan0001.pdf")
        // L1: the operation appears in Activity within 1 s.
        let inActivity = await eventually(.seconds(1)) { await h.engine.activity().contains { $0.newName == Self.expectedInvoice } }
        #expect(inActivity)
        #expect(h.notifier.all.contains { if case .renamed = $0 { true } else { false } })
        await h.stop()
    }

    @Test func reviewModeQueuesAndAcceptRenames() async throws {
        let h = try await EngineHarness(mode: .review)
        h.file("document (3).pdf", EngineHarness.invoice)
        let queued = await eventually { await h.engine.reviewItems().count == 1 }
        let summary = await h.engine.stateSummary()
        #expect(queued, "\(summary) names=\(h.desktopNames) calls=\(h.model.calls.count)")
        let item = try #require(await h.engine.reviewItems().first)
        #expect(item.proposal?.fileName == Self.expectedInvoice)
        #expect(item.proposal?.confidence == .high)
        #expect(h.notifier.all == [.review(item.id)])
        let report = await h.engine.accept(itemIDs: [item.id])
        #expect(report.renamed.count == 1)
        #expect(h.desktopNames == [Self.expectedInvoice])
        #expect(h.notifier.all.count == 1, "in-app actions never echo as notifications (P3)")
        #expect(try h.config.examples(styleID: Presets.clean.id).names == [Self.expectedInvoice])
        await h.stop()
    }

    /// D6: a burst of 11 files copied in at once causes 0 automatic renames, one Review group and one notification.
    @Test func burstGoesToReviewAsOneGroup() async throws {
        let h = try await EngineHarness(mode: .automatic)
        for index in 1...11 { h.file("scan\(String(format: "%04d", index)).pdf", EngineHarness.invoice + "\nfile \(index)") }
        let queued = await eventually(.seconds(15)) { await h.engine.reviewItems().count == 11 }
        #expect(queued)
        try await Task.sleep(for: .milliseconds(300))
        let items = await h.engine.reviewItems()
        #expect(Set(items.compactMap(\.burstGroup)).count == 1)
        #expect(items.allSatisfy { $0.burstGroup != nil })
        #expect(h.desktopNames.allSatisfy { $0.hasPrefix("scan") }, "0 automatic renames")
        let burstNotices = Set(h.notifier.all.compactMap { if case .burst(let id, _) = $0 { id } else { nil } })
        #expect(burstNotices.count == 1)
        #expect(!h.notifier.all.contains { if case .renamed = $0 { true } else if case .review = $0 { true } else { false } })
        await h.stop()
    }

    /// D8: files with a marker in any state are never processed automatically.
    @Test func markedFilesAreNeverProcessed() async throws {
        let h = try await EngineHarness(mode: .automatic)
        let staging = FileSystem.join(h.root, "staging")
        try FileManager.default.createDirectory(atPath: staging, withIntermediateDirectories: true)
        for (index, state) in [Marker.State.renamed, .restored].enumerated() {
            let path = h.file("IMG_\(index).pdf", EngineHarness.invoice, in: staging)
            try Marker(originalName: "IMG_\(index).pdf", state: state, firstRenamed: Date()).write(toPath: path)
            rename(path, FileSystem.join(h.desktop, "IMG_\(index).pdf"))
        }
        try await Task.sleep(for: .seconds(1))
        #expect(h.desktopNames == ["IMG_0.pdf", "IMG_1.pdf"])
        #expect(h.model.calls.isEmpty)
        await h.stop()
    }

    /// D9: renaming an existing file in place never triggers processing, also across a restart.
    @Test func renamesInPlaceNeverTrigger() async throws {
        let h = try await EngineHarness(mode: .automatic)
        // Files present before the engine started are part of the baseline snapshot.
        let report = h.file("Report.pdf", EngineHarness.invoice)
        let other = h.file("Notes.pdf", EngineHarness.invoice)
        try await Task.sleep(for: .milliseconds(600))
        #expect(h.model.calls.isEmpty, "Report.pdf and Notes.pdf are not generic")
        rename(report, FileSystem.join(h.desktop, "IMG_0001.pdf"))
        try await Task.sleep(for: .milliseconds(800))
        #expect(h.desktopNames.contains("IMG_0001.pdf"))
        await h.stop()
        rename(other, FileSystem.join(h.desktop, "IMG_0002.pdf"))
        try await h.launch()
        try await Task.sleep(for: .milliseconds(800))
        #expect(h.desktopNames == ["IMG_0001.pdf", "IMG_0002.pdf"])
        #expect(h.model.calls.isEmpty)
        await h.stop()
    }

    /// C4: files added while the app was quit are handled at the next launch, if added after the watch start.
    @Test func filesAddedWhileQuitAreHandled() async throws {
        let h = try await EngineHarness(mode: .automatic)
        await h.stop()
        h.file("scan0009.pdf", EngineHarness.invoice)
        try await h.launch()
        #expect(await eventually { h.desktopNames.contains(Self.expectedInvoice) })
        await h.stop()

        let future = try await EngineHarness(mode: .automatic, watchStart: Date(timeIntervalSinceNow: 3_600))
        await future.stop()
        future.file("scan0010.pdf", EngineHarness.invoice)
        try await future.launch()
        try await Task.sleep(for: .seconds(1))
        #expect(future.desktopNames == ["scan0010.pdf"], "added before the watch start")
        await future.stop()
    }

    /// C3: files in subfolders are never processed automatically.
    @Test func subfoldersAreIgnored() async throws {
        let h = try await EngineHarness(mode: .automatic)
        let nested = FileSystem.join(h.desktop, "Folder")
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
        for index in 0..<100 { h.file("IMG_\(index).pdf", EngineHarness.invoice, in: nested) }
        try await Task.sleep(for: .seconds(1))
        #expect(try FileSystem.entries(ofDirectory: nested).count == 100)
        #expect(try FileSystem.entries(ofDirectory: nested).allSatisfy { $0.hasPrefix("IMG_") })
        #expect(h.model.calls.isEmpty)
        await h.stop()
    }

    /// F6: 50 simultaneous arrivals are processed in arrival order with no concurrency errors.
    @Test func fiftyArrivalsInOrder() async throws {
        let h = try await EngineHarness(mode: .review)
        for index in 0..<50 { h.file("scan\(String(format: "%04d", index)).pdf", "SUBJECT=file \(index)\nKIND=Report\nfile number \(index) content") }
        #expect(await eventually(.seconds(20)) { await h.engine.reviewItems().count == 50 })
        let order = h.model.calls.compactMap { call in call.split(separator: "\n").first { $0.hasPrefix("SUBJECT=") } }.map { String($0.dropFirst(8)) }
        #expect(order == (0..<50).map { "file \($0)" })
        await h.stop()
    }

    /// K2, K4, K1: moves only when a rule matches; a missing destination renames in place with a warning;
    /// the rule tester matches what happened.
    @Test func rulesMoveOnlyOnMatch() async throws {
        let filed = FileManager.default.temporaryDirectory.appendingPathComponent("untitled-filed-\(UUID().uuidString)").path
        let rule = Rule(id: "invoices", name: "Invoices", conditions: [.kindIs(.builtIn(.invoice))], destinationID: "dest", subfolderPattern: "{year}/{source}")
        let h = try await EngineHarness(mode: .automatic) { config in
            try FileManager.default.createDirectory(atPath: filed, withIntermediateDirectories: true)
            try config.save(GrantedFolder(id: "filed", path: filed, role: .destination, watchStart: Date()))
            try config.save(Destination(id: "dest", folderID: "filed"))
            try config.saveRules([rule])
        }
        defer { try? FileManager.default.removeItem(atPath: filed) }
        h.file("scan0001.pdf", EngineHarness.invoice)
        h.file("scan0002.pdf", "KIND=Receipt\nSOURCE=Migros\nSUBJECT=groceries\nDATE=3 December 2026\nMigros receipt for groceries")
        let movedPath = FileSystem.join(filed, "2026/Swisscom/" + Self.expectedInvoice)
        #expect(await eventually { FileSystem.exists(movedPath) })
        #expect(await eventually { h.desktopNames.contains("2026-12-03 Migros Receipt Groceries.pdf") })
        let tested = await h.engine.testRule(rule)
        let actual = await h.engine.recentProcessedFacts()
        #expect(tested.map(\.matches) == actual.map { $0.matchedRuleID == rule.id })

        // K4: a missing destination leads to a rename in place, a note and a rule warning.
        try FileManager.default.removeItem(atPath: filed)
        h.file("scan0003.pdf", EngineHarness.invoice(month: "December"))
        let renamedInPlace = await eventually { h.desktopNames.contains("2026-11-27 Swisscom Invoice Mobile Subscription December.pdf") }
        let summary = await h.engine.stateSummary()
        let notes = await h.engine.notes().map(\.message)
        #expect(renamedInPlace, "\(summary) names=\(h.desktopNames) notes=\(notes)")
        #expect(await h.engine.ruleHasWarning("invoices"))
        #expect(await h.engine.notes().contains { $0.message.contains("destination folder is missing") })
        await h.stop()
    }

    /// L2, L4, L5: undo entry points and conflicts.
    @Test func undoEntryPointsAndConflicts() async throws {
        let h = try await EngineHarness(mode: .automatic)
        h.file("scan0001.pdf", EngineHarness.invoice)
        #expect(await eventually { h.desktopNames.contains(Self.expectedInvoice) })
        let entry = try #require(await h.engine.activity().first)
        // Name taken: a suffix is added.
        h.file("scan0001.pdf", "someone else's file")
        try await Task.sleep(for: .milliseconds(400))
        guard case .restored(let path, let collision) = await h.engine.undo(entryID: try #require(entry.id)) else {
            Issue.record("undo failed")
            return
        }
        #expect(FileSystem.name(path) == "scan0001 2.pdf")
        #expect(collision == 2)
        #expect(Marker.read(atPath: path)?.state == .restored)
        #expect(await h.engine.undo(entryID: entry.id!) == .unavailable(reason: "This change was already undone."))

        // Finder's Restore Original Name works from the marker, even after history is purged.
        let second = h.file("Untitled 7.pdf", EngineHarness.invoice(month: "October"))
        let secondName = "2026-11-27 Swisscom Invoice Mobile Subscription October.pdf"
        #expect(await eventually { h.desktopNames.contains(secondName) })
        try h.history.clearHistory()
        guard case .restored(let restoredPath, _) = await h.engine.restoreOriginalName(path: FileSystem.join(h.desktop, secondName)) else {
            Issue.record("restore failed")
            return
        }
        #expect(restoredPath == second)

        // Deleted file: undo is disabled with the reason.
        h.file("scan0005.pdf", EngineHarness.invoice(month: "June"))
        let juneName = "2026-11-27 Swisscom Invoice Mobile Subscription June.pdf"
        #expect(await eventually { h.desktopNames.contains(juneName) })
        let june = try #require(await h.engine.activity().first { $0.newName == juneName })
        try FileManager.default.removeItem(atPath: FileSystem.join(h.desktop, juneName))
        #expect(await h.engine.undo(entryID: june.id!) == .unavailable(reason: "The file was deleted, so this change can't be undone."))
        await h.stop()
    }

    /// L3: undo finds files the user moved, and asks for access when they're outside granted folders.
    @Test func undoFindsMovedFiles() async throws {
        let h = try await EngineHarness(mode: .automatic)
        h.file("scan0001.pdf", EngineHarness.invoice)
        #expect(await eventually { h.desktopNames.contains(Self.expectedInvoice) })
        let entry = try #require(await h.engine.activity().first)
        let sub = FileSystem.join(h.desktop, "Archive")
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        rename(FileSystem.join(h.desktop, Self.expectedInvoice), FileSystem.join(sub, "Moved.pdf"))
        guard case .restored(let path, _) = await h.engine.undo(entryID: entry.id!) else {
            Issue.record("moved file not found")
            return
        }
        #expect(path == FileSystem.join(h.desktop, "scan0001.pdf"))

        h.file("scan0002.pdf", EngineHarness.invoice(month: "May"))
        let mayName = "2026-11-27 Swisscom Invoice Mobile Subscription May.pdf"
        #expect(await eventually { h.desktopNames.contains(mayName) })
        let may = try #require(await h.engine.activity().first { $0.newName == mayName })
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("untitled-outside-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: outside) }
        let outsidePath = FileSystem.join(outside, "x.pdf")
        rename(FileSystem.join(h.desktop, mayName), outsidePath)
        // Path bookmarks do not follow moves; a real bookmark does. Simulate the resolved location.
        try await h.history.pool.write { db in try db.execute(sql: "UPDATE operation SET bookmark = ? WHERE id = ?", arguments: [Data(outsidePath.utf8), may.id!]) }
        #expect(await h.engine.undo(entryID: may.id!) == .needsAccess(folder: outside))
        await h.stop()
    }

    /// M3: the queue survives restarts; items whose files vanished are removed with an Activity note.
    @Test func queueSurvivesRestart() async throws {
        let h = try await EngineHarness(mode: .review)
        h.file("scan0001.pdf", EngineHarness.invoice)
        let gone = h.file("scan0002.pdf", EngineHarness.invoice + "\nsecond")
        #expect(await eventually { await h.engine.reviewItems().count == 2 })
        await h.stop()
        try FileManager.default.removeItem(atPath: gone)
        try await h.launch()
        #expect(await h.engine.reviewItems().count == 1)
        #expect(await h.engine.notes().contains { $0.message.contains("scan0002.pdf") })
        await h.stop()
    }

    /// M4: accepting many items shows progress and can be cancelled with the rest untouched.
    @Test func acceptManyWithProgressAndCancel() async throws {
        let h = try await EngineHarness(mode: .review)
        await h.stop()
        for index in 0..<500 { h.file("scan\(String(format: "%04d", index)).pdf", "KIND=Report\nSUBJECT=page \(index)\nreport page \(index) text") }
        try await h.launch()
        _ = try await h.engine.renameExisting(folderID: "desktop")
        #expect(await eventually(.seconds(60)) { await h.engine.reviewItems().count == 500 })
        let ids = await h.engine.reviewItems().map(\.id)
        let progress = ProgressLog()
        let task = Task { await h.engine.accept(itemIDs: ids, progress: { done, total in progress.record(done, total) }) }
        _ = await eventually(.seconds(30)) { progress.latest >= 100 }
        task.cancel()
        let report = await task.value
        #expect(report.cancelledRemaining > 0)
        #expect(report.renamed.count + report.cancelledRemaining == 500)
        let untouched = h.desktopNames.filter { $0.hasPrefix("scan") }.count
        #expect(untouched == report.cancelledRemaining)
        #expect(progress.latestTotal == 500)
        await h.stop()
    }

    /// H8: a style change re-formats queued proposals within 50 ms with 0 model calls; renamed files are untouched.
    @Test func styleChangeReformatsQueue() async throws {
        let h = try await EngineHarness(mode: .review)
        for index in 0..<20 { h.file("scan\(String(format: "%04d", index)).pdf", EngineHarness.invoice + "\n\(index)") }
        #expect(await eventually(.seconds(15)) { await h.engine.reviewItems().count == 20 })
        let callsBefore = h.model.calls.count
        var kebab = Presets.kebab
        kebab.id = Presets.clean.id
        kebab.version = 2
        let elapsed = try await h.engine.saveStyle(kebab)
        #expect(elapsed < .milliseconds(50))
        #expect(h.model.calls.count == callsBefore)
        #expect(await h.engine.reviewItems().allSatisfy { $0.proposal?.fileName == "2026-11-27-swisscom-invoice-mobile-subscription-november.pdf" })
        await h.stop()
    }

    /// I5: Finder renames within 7 days count as edits; Untitled's own operations never do.
    @Test func finderRenamesAreLearned() async throws {
        let h = try await EngineHarness(mode: .automatic)
        h.file("scan0001.pdf", EngineHarness.invoice)
        #expect(await eventually { h.desktopNames.contains(Self.expectedInvoice) })
        try await Task.sleep(for: .milliseconds(300))
        #expect(try h.config.learningEvents().isEmpty, "the automatic rename itself is not an edit")
        try await Task.sleep(for: .seconds(5.5)) // past own-operation suppression
        rename(FileSystem.join(h.desktop, Self.expectedInvoice), FileSystem.join(h.desktop, "2026-11-27 swisscom invoice mobile subscription november.pdf"))
        #expect(await eventually { ((try? h.config.learningEvents()) ?? []).contains { $0.pattern == .caseChange(.lowercase) } })
        await h.stop()
    }

    /// P3: four automatic renames within 10 s become one summary.
    @Test func notificationsBatch() async throws {
        let h = try await EngineHarness(mode: .automatic)
        for index in 0..<4 {
            h.file("scan\(String(format: "%04d", index)).pdf", EngineHarness.invoice(month: "Item\(index)"))
            try await Task.sleep(for: .milliseconds(500))
        }
        #expect(await eventually { h.notifier.all.contains { if case .summary(_, 4) = $0 { true } else { false } } })
        #expect(h.notifier.all.contains { if case .removed(let ids) = $0 { ids.count == 3 } else { false } })
        await h.stop()
    }

    /// V2, V3: holds stop processing, and work resumes within 10 s after the condition clears.
    @Test func powerHoldsAndResume() async throws {
        let h = try await EngineHarness(mode: .automatic)
        h.power.set(PowerConditions(lowPowerMode: true))
        h.file("scan0001.pdf", EngineHarness.invoice)
        try await Task.sleep(for: .seconds(1))
        #expect(h.desktopNames == ["scan0001.pdf"])
        #expect(await h.engine.status() == .held(.lowPowerMode))
        h.power.set(PowerConditions(thermal: .critical))
        try await Task.sleep(for: .milliseconds(400))
        #expect(h.desktopNames == ["scan0001.pdf"])
        h.power.set(PowerConditions())
        let clock = ContinuousClock()
        let start = clock.now
        #expect(await eventually(.seconds(10)) { h.desktopNames.contains(Self.expectedInvoice) })
        #expect(clock.now - start < .seconds(10))

        var settings = await h.engine.currentSettings()
        settings.processing.waitUntilPluggedIn = true
        await h.engine.updateSettings(settings)
        h.power.set(PowerConditions(onBattery: true))
        h.file("scan0002.pdf", EngineHarness.invoice(month: "April"))
        try await Task.sleep(for: .seconds(1))
        #expect(h.desktopNames.contains("scan0002.pdf"))
        h.power.set(PowerConditions(onBattery: false))
        #expect(await eventually(.seconds(10)) { !h.desktopNames.contains("scan0002.pdf") })
        await h.stop()
    }

    /// V4 (engine): under rate limiting the file is processed exactly once.
    @Test func rateLimitedFilesAreProcessedOnce() async throws {
        let h = try await EngineHarness(mode: .automatic)
        h.model.state.withLock { $0.failures = [.rateLimited(resetDate: nil), .rateLimited(resetDate: nil), .concurrentRequests] }
        h.file("scan0001.pdf", EngineHarness.invoice)
        #expect(await eventually { h.desktopNames.contains(Self.expectedInvoice) })
        try await Task.sleep(for: .milliseconds(300))
        #expect(h.model.calls.count == 4)
        #expect(await h.engine.activity().count == 1)
        await h.stop()
    }

    /// F3: when Apple Intelligence is unavailable, Basic naming is used and the status shows it.
    @Test func basicNamingWhenUnavailable() async throws {
        let h = try await EngineHarness(mode: .review)
        h.availability.state.withLock { $0 = .appleIntelligenceNotEnabled }
        #expect(await h.engine.status() == .basicNaming(folderNames: ["Desktop"]))
        h.file("scan0001.pdf", "RECHNUNG\nSwisscom Rechnung vom 27. November 2026\nMobile Abo")
        #expect(await eventually { await h.engine.reviewItems().count == 1 })
        let proposal = try #require(await h.engine.reviewItems().first?.proposal)
        #expect(proposal.path == .basic)
        #expect(proposal.fields.kind == .builtIn(.invoice))
        #expect(h.model.calls.isEmpty)
        await h.stop()
    }

    /// User pauses skip arrivals; "until tomorrow" persists across restarts (N4).
    @Test func pauseSkipsAndPersists() async throws {
        let h = try await EngineHarness(mode: .automatic)
        await h.engine.pause(.untilTomorrow)
        h.file("scan0001.pdf", EngineHarness.invoice)
        try await Task.sleep(for: .seconds(1))
        #expect(h.desktopNames == ["scan0001.pdf"])
        try await h.launch()
        #expect(await h.engine.pauseState().option == .untilTomorrow)
        guard case .paused(let until) = await h.engine.status(), let until else {
            Issue.record("not paused")
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(calendar.component(.hour, from: until) == 6)
        await h.engine.resume()
        #expect(await h.engine.pauseState() == .none)
        await h.stop()
    }

    /// Quick Rename: typed names are used as typed (sanitized only); files outside granted folders get a clear error.
    @Test func quickRename() async throws {
        let h = try await EngineHarness(mode: .off)
        let path = h.file("Tax return 2025.pdf", EngineHarness.invoice)
        let proposals = try await h.engine.explicitProposals(paths: [path])
        let proposal = try #require(proposals.first)
        #expect(proposal.proposal.fileName == Self.expectedInvoice)
        #expect(proposal.baseName == "2026-11-27 Swisscom Invoice Mobile Subscription November")
        let newPath = try await h.engine.applyExplicit(proposal, typedBase: "my TAX stuff: 2025", move: true)
        #expect(FileSystem.name(newPath) == "my TAX stuff 2025.pdf")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("untitled-q-\(UUID().uuidString).pdf").path
        _ = FileManager.default.createFile(atPath: outside, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(atPath: outside) }
        await #expect(throws: ExplicitError.outsideGrantedFolders(folder: FileSystem.parent(outside))) {
            _ = try await h.engine.explicitProposals(paths: [outside])
        }
        await #expect(throws: ExplicitError.selectionSize(51)) {
            _ = try await h.engine.explicitProposals(paths: Array(repeating: newPath, count: 51))
        }
        let suggested = try await h.engine.suggestName(path: newPath)
        #expect(suggested == Self.expectedInvoice)
        #expect(FileSystem.exists(newPath), "Suggest Name changes nothing")
        await h.stop()
    }

    /// C2: a watched folder that is renamed or deleted needs attention within 5 s.
    @Test func missingFolderNeedsAttention() async throws {
        let h = try await EngineHarness(mode: .automatic)
        let moved = h.desktop + "-moved"
        rename(h.desktop, moved)
        defer { rename(moved, h.desktop) }
        #expect(await eventually(.seconds(5)) { await h.engine.allFolders().first?.attention == .needsReconnect })
        #expect(await h.engine.status() == .needsAttention(folderName: "Desktop"))
        await h.stop()
    }

    /// E4 and W2: extracted text never reaches disk, and diagnostics contain no planted tokens.
    @Test func extractedTextNeverStoredAndDiagnosticsAreClean() async throws {
        let h = try await EngineHarness(mode: .review)
        let tokens = (0..<20).map { _ in "TOKEN" + UUID().uuidString.replacingOccurrences(of: "-", with: "") }
        for (index, token) in tokens.enumerated() {
            // Generic names, so every file is processed; the token is only in the content.
            h.file("scan\(String(format: "%04d", index)).pdf", "KIND=Report\nSUBJECT=plain words\nsecret line \(token) not for disk\n")
        }
        // Tokens in names and paths too, for the diagnostics check (W2).
        let nameTokens = (0..<2).map { _ in "NAMETOKEN" + UUID().uuidString.replacingOccurrences(of: "-", with: "") }
        let named = FileSystem.join(h.desktop, "Folder \(nameTokens[0])")
        try FileManager.default.createDirectory(atPath: named, withIntermediateDirectories: true)
        h.file("Notes \(nameTokens[1]).txt", "x", in: named)
        #expect(await eventually(.seconds(15)) { await h.engine.reviewItems().count == 20 })
        let report = await h.engine.diagnosticsReport()
        for token in tokens + nameTokens + [h.desktop] { #expect(!report.contains(token)) }
        await h.stop()
        var stored = Data()
        for name in try FileSystem.entries(ofDirectory: h.dataDirectory) {
            stored += (FileManager.default.contents(atPath: FileSystem.join(h.dataDirectory, name)) ?? Data())
        }
        let text = String(decoding: stored, as: UTF8.self)
        for token in tokens { #expect(!text.contains(token)) }
    }

    /// O6: the Automatic offer appears exactly once per folder after 20 accepted proposals with ≤ 2 edits.
    @Test func automaticOfferOnce() async throws {
        let h = try await EngineHarness(mode: .review)
        let events = await h.engine.events()
        let offers = OfferCounter()
        let listener = Task { for await event in events { if case .automaticOffer = event { offers.increment() } } }
        await h.stop()
        for index in 0..<25 { h.file("scan\(String(format: "%04d", index)).pdf", EngineHarness.invoice + "\n\(index)") }
        try await h.launch()
        _ = try await h.engine.renameExisting(folderID: "desktop")
        #expect(await eventually(.seconds(20)) { await h.engine.reviewItems().count == 25 })
        let newEvents = await h.engine.events()
        let newListener = Task { for await event in newEvents { if case .automaticOffer = event { offers.increment() } } }
        for item in await h.engine.reviewItems() { _ = await h.engine.accept(itemIDs: [item.id]) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(offers.value == 1)
        listener.cancel()
        newListener.cancel()
        await h.stop()
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var done = 0
    private var total = 0
    func record(_ done: Int, _ total: Int) { lock.lock(); self.done = done; self.total = total; lock.unlock() }
    var latest: Int { lock.lock(); defer { lock.unlock() }; return done }
    var latestTotal: Int { lock.lock(); defer { lock.unlock() }; return total }
}

final class OfferCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
