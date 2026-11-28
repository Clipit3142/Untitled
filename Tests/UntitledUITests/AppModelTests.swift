import Foundation
import Synchronization
import Testing
@testable import UntitledUI
import UntitledCore
import UntitledEngine
import UntitledExtract
import UntitledFS
import UntitledModel
import UntitledStore

/// A generator that is never reached: these tests run with Basic naming only.
struct UnusedGenerator: FieldGenerator {
    func generate(_ request: GenerationRequest) async throws -> GeneratedFields { throw ModelFailure.assetsUnavailable }
    func tokenCount(instructions: String, prompt: String, image: PromptImage?) async throws -> Int { 0 }
    func contextSize() async throws -> Int { 4_096 }
    func prewarm(instructions: String) async {}
}

/// Reads any file's bytes as text, so a fixture named .pdf can carry its content.
struct TextReader: ContentReader {
    func canRead(extension ext: String) -> Bool { true }
    func read(url: URL, options: ReadOptions) async throws -> ExtractedContent {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return ExtractedContent(lines: text.split(whereSeparator: \.isNewline).map { RecognizedLine(text: String($0)) })
    }
}

struct SilentNotifier: NotificationPresenting {
    func postRenamed(operationID: Int64, oldName: String, newName: String) {}
    func postSummary(summaryID: String, operationIDs: [Int64]) {}
    func removeRenamed(operationIDs: [Int64]) {}
    func postReview(itemID: String, oldName: String, proposedName: String) {}
    func postBurst(groupID: String, count: Int) {}
}

/// A full engine and app model on temporary folders.
@MainActor
final class ModelHarness {
    let root: String
    let desktop: String
    let library: String
    var model: AppModel!

    init(mode: FolderMode = .automatic) async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("untitled-ui-\(UUID().uuidString)").path
        desktop = FileSystem.join(root, "Desktop")
        library = FileSystem.join(root, "Library")
        try FileManager.default.createDirectory(atPath: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: library, withIntermediateDirectories: true)
        let config = try ConfigDatabase(url: URL(fileURLWithPath: FileSystem.join(library, "config.sqlite")))
        var settings = EngineSettings()
        settings.stabilityWait = 0.1
        settings.basicNamingOnly = true
        try config.setSetting(settings, key: "engineSettings")
        try config.save(GrantedFolder(id: "desktop", path: desktop, role: .watched, mode: mode, watchStart: Date(timeIntervalSinceNow: -3_600)))
        try await launch()
    }

    func launch() async throws {
        if let model { await model.shutdown() }
        let config = try ConfigDatabase(url: URL(fileURLWithPath: FileSystem.join(library, "config.sqlite")))
        let history = try HistoryDatabase(url: URL(fileURLWithPath: FileSystem.join(library, "history.sqlite")))
        let engine = Engine(Engine.Dependencies(
            config: config, history: history,
            executor: OperationExecutor(journal: history, coordinator: DirectMove(), suppression: OwnOperationSuppression()),
            extractor: Extractor(readers: [TextReader()], timeZone: TimeZone(identifier: "UTC")!),
            generator: UnusedGenerator(), notifier: SilentNotifier(), power: FixedPower(), bookmarks: PathBookmarks(),
            watcherFactory: { folder in PollingFolderWatcher(path: folder.path, interval: .milliseconds(40)) },
            availability: { .available }, timeZone: TimeZone(identifier: "UTC")!,
            stabilityInterval: .milliseconds(60), maintenanceInterval: .milliseconds(100),
            generationSleeper: { _ in }
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        model = AppModel(engine: engine, store: EnginePreferencesStore(engine: engine),
                         thumbnails: ThumbnailCache(directory: URL(fileURLWithPath: FileSystem.join(library, "Thumbnails"))),
                         calendar: calendar)
        await model.load()
    }

    static let scanName = "scan0001.pdf"

    /// A generic-named scan of a Swisscom invoice.
    @discardableResult
    func scan(_ name: String = scanName) -> String {
        let path = FileSystem.join(desktop, name)
        _ = FileManager.default.createFile(atPath: path, contents: Data("Swisscom invoice\nInvoice 27 November 2026\nMobile subscription November".utf8))
        return path
    }

    var desktopNames: Set<String> { Set((try? FileSystem.entries(ofDirectory: desktop)) ?? []) }

    func finish() async {
        await model.shutdown()
        try? FileManager.default.removeItem(atPath: root)
    }
}

@MainActor
func eventually(_ timeout: Duration = .seconds(10), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return await condition()
}

@Suite("App model", .serialized)
@MainActor
struct AppModelTests {
    @Test("Nothing is watched before onboarding finishes, and quitting resumes at the same step (B7)")
    func onboardingGatesWatching() async throws {
        let harness = try await ModelHarness()
        #expect(harness.model.onboarding.step == .welcome)
        await harness.model.updateOnboarding { $0.next(); $0.next(); $0.next() }
        harness.scan()
        try await Task.sleep(for: .milliseconds(600))
        #expect(harness.desktopNames == [ModelHarness.scanName])
        #expect(harness.model.recent.isEmpty)

        // Quit mid-onboarding: the step is kept.
        try await harness.launch()
        #expect(harness.model.onboarding.step == .style)
        #expect(!harness.model.onboarding.isComplete)

        // Finishing starts watching; the file added during onboarding is handled.
        await harness.model.updateOnboarding { $0.finish() }
        let renamed = await eventually { harness.model.recent.count == 1 }
        #expect(renamed)
        #expect(!harness.desktopNames.contains(ModelHarness.scanName))
        await harness.finish()
    }

    @Test("Recent, glyph and status follow the engine; undo restores the name")
    func recentAndUndo() async throws {
        let harness = try await ModelHarness()
        await harness.model.updateOnboarding { $0.skip() }
        #expect(harness.model.statusText == "Basic naming")
        #expect(harness.model.glyphState == .idle)
        harness.scan()
        #expect(await eventually { harness.model.recent.count == 1 })
        let entry = try #require(harness.model.recent.first)
        let result = await harness.model.undo(entryID: try #require(entry.id))
        guard case .restored = result else {
            Issue.record("undo failed: \(result)")
            return
        }
        #expect(harness.desktopNames.contains(ModelHarness.scanName))
        await harness.finish()
    }

    @Test("Review items appear, accept renames them, and the glyph shows the dot")
    func review() async throws {
        let harness = try await ModelHarness(mode: .review)
        await harness.model.updateOnboarding { $0.skip() }
        harness.scan()
        #expect(await eventually { harness.model.reviewCount == 1 })
        #expect(harness.model.glyphState == .needsReview)
        let item = try #require(harness.model.reviewItems.first)
        let report = await harness.model.accept([item.id])
        #expect(report.renamed.count == 1)
        #expect(harness.model.reviewCount == 0)
        #expect(harness.model.glyphState == .idle)
        #expect(harness.model.recent.count == 1)
        await harness.finish()
    }

    @Test("Pause persists across restarts and shows in the glyph (N4)")
    func pause() async throws {
        let harness = try await ModelHarness()
        await harness.model.updateOnboarding { $0.skip() }
        await harness.model.pause(.untilTomorrow)
        #expect(harness.model.glyphState == .paused)
        #expect(harness.model.statusText == "Paused until 06:00")
        try await harness.launch()
        #expect(harness.model.pauseState.option == .untilTomorrow)
        #expect(harness.model.glyphState == .paused)
        await harness.model.resume()
        #expect(harness.model.glyphState != .paused)
        await harness.finish()
    }

    @Test("Preferences persist, and Reset clears them with onboarding (O5)")
    func preferencesAndReset() async throws {
        let harness = try await ModelHarness()
        var dockChanges: [Bool] = []
        harness.model.onPreferencesChanged = { dockChanges.append($0.showInDock) }
        await harness.model.update { $0.showInDock = true }
        await harness.model.updateOnboarding { $0.skip() }
        try await harness.launch()
        #expect(harness.model.preferences.showInDock)
        #expect(harness.model.onboarding.completion == .skipped)
        harness.model.onPreferencesChanged = { dockChanges.append($0.showInDock) }
        await harness.model.resetEverything()
        #expect(!harness.model.preferences.showInDock)
        #expect(harness.model.onboarding == OnboardingFlow())
        #expect(harness.model.folders.isEmpty)
        #expect(dockChanges.last == false)
        try await harness.launch()
        #expect(harness.model.onboarding == OnboardingFlow())
        await harness.finish()
    }

    @Test("Invalid styles are refused with their reasons (H7)")
    func invalidStyle() async throws {
        let harness = try await ModelHarness()
        var style = Presets.clean
        style.id = "custom"
        style.characters.asciiOnly = true
        style.partSeparator = .spacedEnDash
        let issues = await harness.model.save(style)
        #expect(!issues.isEmpty)
        #expect(!harness.model.styles.contains { $0.id == "custom" })
        style.partSeparator = .spacedHyphen
        #expect(await harness.model.save(style).isEmpty)
        #expect(harness.model.styles.contains { $0.id == "custom" })
        await harness.finish()
    }

    @Test("Learn from folder needs 10 files and reads their style (B5)")
    func learnFromFolder() async throws {
        let harness = try await ModelHarness()
        let folder = FileSystem.join(harness.root, "Archive")
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for day in 1...9 {
            _ = FileManager.default.createFile(atPath: FileSystem.join(folder, "2026-11-0\(day)_swisscom_invoice.pdf"), contents: Data())
        }
        await #expect(throws: StyleInferenceError.tooFewNames(minimum: 10, found: 9)) {
            try await harness.model.learnStyle(fromFolder: folder)
        }
        _ = FileManager.default.createFile(atPath: FileSystem.join(folder, "2026-11-10_swisscom_invoice.pdf"), contents: Data())
        let inferred = try await harness.model.learnStyle(fromFolder: folder)
        #expect(inferred.dateFormat == .iso)
        #expect(inferred.wordSeparator == .underscore)
        #expect(inferred.caseMode == .lowercase)
        await harness.finish()
    }
}
