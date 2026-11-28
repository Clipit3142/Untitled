import Foundation
import Synchronization
@testable import UntitledEngine
import UntitledCore
import UntitledFS
import UntitledStore
import UntitledModel
import UntitledExtract

/// Reads any file's bytes as text, so fixtures named .png or .pdf can carry content in tests.
struct AnyTextReader: ContentReader {
    func canRead(extension ext: String) -> Bool { true }
    func read(url: URL, options: ReadOptions) async throws -> ExtractedContent {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return ExtractedContent(lines: text.split(whereSeparator: \.isNewline).map { RecognizedLine(text: String($0)) })
    }
}

/// A model that reads KEY=value lines: KIND, SOURCE, SUBJECT, and DATE (the first candidate).
final class ScriptedModel: FieldGenerator {
    struct State {
        var calls: [String] = []
        var failures: [ModelFailure] = []
    }
    let state = Mutex(State())

    func generate(_ request: GenerationRequest) async throws -> GeneratedFields {
        let failure: ModelFailure? = state.withLock { s in
            s.calls.append(request.content.map(\.text).joined(separator: "\n"))
            return s.failures.isEmpty ? nil : s.failures.removeFirst()
        }
        if let failure { throw failure }
        var values: [String: String] = [:]
        for line in request.content.map(\.text) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        let kind = values["KIND"].map { KindRef.fromSchemaValue($0, customKinds: request.schema.customKinds) } ?? .other
        let date = values["DATE"] != nil && request.schema.dateChoices.count > 1 ? 0 : nil
        return GeneratedFields(kind: kind, source: values["SOURCE"], subject: values["SUBJECT"] ?? "", dateChoice: date)
    }

    func tokenCount(instructions: String, prompt: String, image: PromptImage?) async throws -> Int {
        (instructions.utf8.count + prompt.utf8.count) / 4
    }

    func contextSize() async throws -> Int { 8_192 }
    func prewarm(instructions: String) async {}

    var calls: [String] { state.withLock { $0.calls } }
}

final class RecordingNotifier: NotificationPresenting {
    enum Posted: Equatable {
        case renamed(Int64)
        case summary(String, Int)
        case removed([Int64])
        case review(String)
        case burst(String, Int)
    }
    let posted = Mutex<[Posted]>([])

    func postRenamed(operationID: Int64, oldName: String, newName: String) { posted.withLock { $0.append(.renamed(operationID)) } }
    func postSummary(summaryID: String, operationIDs: [Int64]) { posted.withLock { $0.append(.summary(summaryID, operationIDs.count)) } }
    func removeRenamed(operationIDs: [Int64]) { posted.withLock { $0.append(.removed(operationIDs)) } }
    func postReview(itemID: String, oldName: String, proposedName: String) { posted.withLock { $0.append(.review(itemID)) } }
    func postBurst(groupID: String, count: Int) { posted.withLock { $0.append(.burst(groupID, count)) } }

    var all: [Posted] { posted.withLock { $0 } }
}

final class AvailabilityBox: Sendable {
    let state = Mutex(ModelAvailability.available)
}

final class MutablePower: PowerMonitoring {
    let state = Mutex(PowerConditions())
    func conditions() -> PowerConditions { state.withLock { $0 } }
    func set(_ value: PowerConditions) { state.withLock { $0 = value } }
}

/// A full engine on temporary folders.
final class EngineHarness: @unchecked Sendable {
    let root: String
    let desktop: String
    let dataDirectory: String
    let model = ScriptedModel()
    let notifier = RecordingNotifier()
    let power = MutablePower()
    let availability = AvailabilityBox()
    var engine: Engine!
    var config: ConfigDatabase!
    var history: HistoryDatabase!

    let productionTiming: Bool

    init(mode: FolderMode = .automatic, watchStart: Date = Date(timeIntervalSinceNow: -3_600), productionTiming: Bool = false,
         configure: (ConfigDatabase) throws -> Void = { _ in }) async throws {
        self.productionTiming = productionTiming
        root = FileManager.default.temporaryDirectory.appendingPathComponent("untitled-engine-\(UUID().uuidString)").path
        desktop = FileSystem.join(root, "Desktop")
        dataDirectory = FileSystem.join(root, "Library")
        try FileManager.default.createDirectory(atPath: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: dataDirectory, withIntermediateDirectories: true)
        let config = try ConfigDatabase(url: URL(fileURLWithPath: FileSystem.join(dataDirectory, "config.sqlite")))
        var settings = EngineSettings()
        settings.stabilityWait = productionTiming ? Defaults.stabilityWait : 0.1
        try config.setSetting(settings, key: "engineSettings")
        try config.save(GrantedFolder(id: "desktop", path: desktop, role: .watched, mode: mode, watchStart: watchStart))
        try configure(config)
        try await launch()
    }

    deinit {
        try? FileManager.default.removeItem(atPath: root)
    }

    /// Starts (or restarts) the engine on the same databases.
    func launch() async throws {
        if let engine { await engine.stop() }
        config = try ConfigDatabase(url: URL(fileURLWithPath: FileSystem.join(dataDirectory, "config.sqlite")))
        history = try HistoryDatabase(url: URL(fileURLWithPath: FileSystem.join(dataDirectory, "history.sqlite")))
        let executor = OperationExecutor(journal: history, coordinator: DirectMove(), suppression: OwnOperationSuppression())
        let availability = self.availability
        engine = Engine(Engine.Dependencies(
            config: config, history: history, executor: executor,
            extractor: Extractor(readers: [AnyTextReader()], timeZone: TimeZone(identifier: "UTC")!),
            generator: model, notifier: notifier, power: power, bookmarks: PathBookmarks(),
            watcherFactory: { folder in PollingFolderWatcher(path: folder.path, interval: .milliseconds(40)) },
            availability: { availability.state.withLock { $0 } }, timeZone: TimeZone(identifier: "UTC")!,
            stabilityInterval: productionTiming ? .milliseconds(500) : .milliseconds(60), maintenanceInterval: .milliseconds(100),
            generationSleeper: { _ in try await Task.sleep(for: .milliseconds(5)) }
        ))
        try await engine.start()
    }

    func stop() async { await engine.stop() }

    @discardableResult
    func file(_ name: String, _ content: String, in folder: String? = nil) -> String {
        let path = FileSystem.join(folder ?? desktop, name)
        _ = FileManager.default.createFile(atPath: path, contents: Data(content.utf8))
        return path
    }

    var desktopNames: Set<String> { Set((try? FileSystem.entries(ofDirectory: desktop)) ?? []) }

    /// The invoice fixture with another subject month, keeping the 27 November 2026 date.
    static func invoice(month: String) -> String {
        "KIND=Invoice\nSOURCE=Swisscom\nSUBJECT=mobile subscription \(month)\nDATE=27 November 2026\nSwisscom AG invoice for the mobile subscription"
    }

    static let invoice = "KIND=Invoice\nSOURCE=Swisscom\nSUBJECT=mobile subscription November\nDATE=27 November 2026\nSwisscom AG invoice for the mobile subscription"
}

/// Polls until a condition holds or the timeout passes.
func eventually(_ timeout: Duration = .seconds(10), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return await condition()
}
