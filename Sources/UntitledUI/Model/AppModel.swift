public import Foundation
public import Observation
public import UntitledCore
public import UntitledStore
public import UntitledEngine
public import UntitledModel
public import UntitledFS

/// The state every view reads, kept in step with the engine through its event stream.
/// Engine calls run off the main actor; the model only stores results (U2).
@MainActor
@Observable
public final class AppModel {
    public let engine: Engine
    @ObservationIgnored let store: any PreferencesStoring
    @ObservationIgnored public let thumbnails: ThumbnailCache?
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored public var calendar: Calendar
    @ObservationIgnored var eventsTask: Task<Void, Never>?
    @ObservationIgnored var engineStarted = false
    /// Called when the app's Dock presence should change (O1).
    @ObservationIgnored public var onPreferencesChanged: (AppPreferences) -> Void = { _ in }

    public private(set) var status: EngineStatus = .notWatching
    public private(set) var reviewCount = 0
    public private(set) var isWorking = false
    public private(set) var recent: [JournalEntry] = []
    public private(set) var reviewItems: [QueueItem] = []
    public private(set) var folders: [GrantedFolder] = []
    public private(set) var suggestions: [Suggestion] = []
    public private(set) var styles: [NamingStyle] = Presets.all
    public private(set) var rules: [Rule] = []
    public private(set) var destinations: [Destination] = []
    public private(set) var customKinds: [CustomKind] = []
    public private(set) var pauseState = PauseState.none
    public private(set) var settings = EngineSettings()
    public private(set) var availability = ModelAvailability.available
    public private(set) var previewSamples: [StylePreviewSample] = []
    /// Folders for which the one-time "Go Automatic?" offer is showing (O6).
    public private(set) var automaticOffers: [String] = []
    /// Transient messages, newest last ("“Invoice.pdf” was taken, so…").
    public private(set) var notices: [Notice] = []
    public private(set) var preferences = AppPreferences()
    public private(set) var onboarding = OnboardingFlow()
    public private(set) var loaded = false

    public struct Notice: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let text: String
        public init(text: String) {
            id = UUID()
            self.text = text
        }
    }

    public init(engine: Engine, store: any PreferencesStoring, thumbnails: ThumbnailCache?,
                calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.engine = engine
        self.store = store
        self.thumbnails = thumbnails
        self.calendar = calendar
        self.now = now
    }

    // MARK: Derived state

    public var glyphState: GlyphState { GlyphState.state(status: status, reviewCount: reviewCount, isWorking: isWorking) }

    public var statusText: String { status.text(timeZone: calendar.timeZone) }

    public var watchedFolders: [GrantedFolder] { folders.filter { $0.role == .watched } }

    public func folders(role: FolderRole) -> [GrantedFolder] { folders.filter { $0.role == role } }

    public func style(id: String) -> NamingStyle {
        styles.first { $0.id == id } ?? Presets.clean
    }

    public func folder(id: String?) -> GrantedFolder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    public func destinationName(_ id: String?) -> String? {
        guard let id, let destination = destinations.first(where: { $0.id == id }) else { return nil }
        return folder(id: destination.folderID)?.displayName
    }

    // MARK: Lifecycle

    /// Loads state, starts the engine once onboarding allows watching (B7), and follows engine events.
    public func load() async {
        preferences = await store.loadPreferences() ?? AppPreferences()
        onboarding = await store.loadOnboarding() ?? OnboardingFlow()
        let stream = await engine.events()
        eventsTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handle(event)
            }
        }
        if onboarding.allowsWatching || onboarding.step == .demo { await startEngine() }
        await refreshAll()
        loaded = true
        onPreferencesChanged(preferences)
    }

    public func shutdown() async {
        eventsTask?.cancel()
        eventsTask = nil
        await engine.stop()
        engineStarted = false
    }

    func startEngine() async {
        guard !engineStarted else { return }
        do {
            try await engine.start()
            engineStarted = true
        } catch {
            post("Untitled couldn't start watching: \(error.localizedDescription)")
        }
    }

    func handle(_ event: EngineEvent) async {
        switch event {
        case .queueChanged: await refreshQueue()
        case .historyChanged: await refreshRecent()
        case .statusChanged: await refreshStatus()
        case .foldersChanged: await refreshFolders()
        case .suggestionsChanged: suggestions = await engine.pendingSuggestions()
        case .libraryChanged: await refreshLibrary()
        case .automaticOffer(let folderID):
            if !automaticOffers.contains(folderID) { automaticOffers.append(folderID) }
        case .notice(let text): post(text)
        }
    }

    public func refreshAll() async {
        await refreshStatus()
        await refreshQueue()
        await refreshRecent()
        await refreshFolders()
        await refreshLibrary()
        suggestions = await engine.pendingSuggestions()
    }

    func refreshStatus() async {
        status = await engine.status()
        isWorking = await engine.isWorking()
        pauseState = await engine.pauseState()
        settings = await engine.currentSettings()
        availability = await engine.modelAvailability()
    }

    func refreshQueue() async {
        reviewItems = await engine.reviewItems()
        reviewCount = reviewItems.count
        previewSamples = await engine.previewSamples()
    }

    func refreshRecent() async {
        recent = await engine.activity(limit: Metrics.recentCount)
    }

    func refreshFolders() async {
        folders = await engine.allFolders()
        status = await engine.status()
    }

    func refreshLibrary() async {
        styles = await engine.styles()
        rules = await engine.rules()
        destinations = await engine.destinations()
        customKinds = await engine.customKinds()
    }

    public func post(_ text: String) {
        notices.append(Notice(text: text))
        if notices.count > 3 { notices.removeFirst(notices.count - 3) }
    }

    public func dismiss(_ notice: Notice) {
        notices.removeAll { $0.id == notice.id }
    }

    // MARK: Preferences and onboarding

    public func update(_ change: (inout AppPreferences) -> Void) async {
        change(&preferences)
        await store.savePreferences(preferences)
        onPreferencesChanged(preferences)
    }

    public func updateOnboarding(_ change: (inout OnboardingFlow) -> Void) async {
        change(&onboarding)
        await store.saveOnboarding(onboarding)
        if onboarding.allowsWatching || onboarding.step == .demo { await startEngine() }
        await refreshStatus()
    }

    public func updateSettings(_ change: (inout EngineSettings) -> Void) async {
        var copy = settings
        change(&copy)
        await engine.updateSettings(copy)
        await refreshStatus()
    }

    // MARK: Pause (N4)

    public func pause(_ option: PauseOption) async {
        await engine.pause(option)
        await refreshStatus()
    }

    public func resume() async {
        await engine.resume()
        await refreshStatus()
    }

    // MARK: Undo and Activity

    @discardableResult
    public func undo(entryID: Int64) async -> UndoResult {
        let result = await engine.undo(entryID: entryID)
        if case .unavailable(let reason) = result { post(reason) }
        await refreshRecent()
        return result
    }

    @discardableResult
    public func undoLast() async -> UndoResult? {
        let result = await engine.undoLast()
        if case .unavailable(let reason)? = result { post(reason) }
        await refreshRecent()
        return result
    }

    public func activity(search: String) async -> [JournalEntry] {
        await engine.activity(search: search, limit: 2_000)
    }

    public func notes() async -> [ActivityNote] { await engine.notes() }

    public func neverRenameAgain(entryID: Int64) async {
        await engine.neverRenameAgain(entryID: entryID)
    }

    // MARK: Review (3.15)

    public func accept(_ itemIDs: [String], edits: [String: ReviewEdit] = [:], moveEnabled: [String: Bool] = [:],
                       progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async -> AcceptReport {
        let report = await engine.accept(itemIDs: itemIDs, edits: edits, moveEnabled: moveEnabled, progress: progress)
        if !report.failed.isEmpty { post(report.failed.joined(separator: "\n")) }
        await refreshQueue()
        await refreshRecent()
        return report
    }

    public func skip(_ itemIDs: [String]) async {
        await engine.skip(itemIDs: itemIDs)
        await refreshQueue()
    }

    public func updateFields(itemID: String, fields: NameFields) async -> Proposal? {
        let proposal = try? await engine.updateFields(itemID: itemID, fields: fields)
        await refreshQueue()
        return proposal
    }

    public func previewTyped(itemID: String, name: String) async -> TypedName.Result? {
        await engine.previewTyped(itemID: itemID, name: name)
    }

    /// Applies one style to the selected items' folders ("Change style" in the action bar).
    public func changeStyle(of itemIDs: [String], to styleID: String) async {
        let folderIDs = Set(reviewItems.filter { itemIDs.contains($0.id) }.compactMap(\.folderID))
        for id in folderIDs {
            guard var folder = folder(id: id) else { continue }
            folder.styleID = styleID
            try? await engine.updateFolder(folder)
        }
        _ = try? await engine.saveStyle(style(id: styleID))
        await refreshAll()
    }

    // MARK: Suggestions (3.11)

    public func answer(_ answer: SuggestionEngine.Answer, to suggestion: Suggestion) async {
        try? await engine.answer(answer, to: suggestion)
        suggestions = await engine.pendingSuggestions()
        await refreshLibrary()
    }

    // MARK: Folders

    public func addFolder(_ folder: GrantedFolder, confirmedProject: Bool = false) async throws(FolderError) {
        do {
            try await engine.addFolder(folder, confirmedProject: confirmedProject)
        } catch let error as FolderError {
            throw error
        } catch {
            post(error.localizedDescription)
        }
        await refreshFolders()
    }

    public func updateFolder(_ folder: GrantedFolder) async {
        try? await engine.updateFolder(folder)
        await refreshFolders()
    }

    public func removeFolder(id: String) async {
        try? await engine.removeFolder(id: id)
        await refreshFolders()
    }

    /// Answers the one-time offer; either way it is not shown again (O6).
    public func answerAutomaticOffer(folderID: String, switchToAutomatic: Bool) async {
        automaticOffers.removeAll { $0 == folderID }
        guard switchToAutomatic, var folder = folder(id: folderID) else { return }
        folder.mode = .automatic
        await updateFolder(folder)
    }

    public func renameExisting(folderID: String) async -> Int {
        let count = (try? await engine.renameExisting(folderID: folderID)) ?? 0
        post(count == 0 ? "No files to rename in this folder." : "\(count) proposals were added to Review.")
        return count
    }

    // MARK: Styles and rules

    /// Saves a valid style; invalid ones return their issues and are not saved (H7).
    public func save(_ style: NamingStyle) async -> [StyleIssue] {
        let issues = StyleValidator.issues(style)
        guard issues.isEmpty else { return issues }
        _ = try? await engine.saveStyle(style)
        await refreshLibrary()
        await refreshQueue()
        return []
    }

    public func deleteStyle(id: String) async {
        try? await engine.deleteStyle(id: id)
        await refreshLibrary()
        await refreshFolders()
    }

    public func saveRules(_ rules: [Rule]) async {
        try? await engine.saveRules(rules)
        await refreshLibrary()
    }

    public func saveDestination(_ destination: Destination) async {
        try? await engine.saveDestination(destination)
        await refreshLibrary()
    }

    public func testRule(_ rule: Rule) async -> [(name: String, matches: Bool)] {
        await engine.testRule(rule)
    }

    public func ruleHasWarning(_ ruleID: String) async -> Bool { await engine.ruleHasWarning(ruleID) }

    public func examples(styleID: String) async -> ExampleList { await engine.examples(styleID: styleID) }

    public func removeExample(_ name: String, styleID: String) async {
        var list = await engine.examples(styleID: styleID)
        list.remove(name)
        try? await engine.saveExamples(list, styleID: styleID)
    }

    public func addExample(_ name: String, styleID: String) async {
        var list = await engine.examples(styleID: styleID)
        list.add(name)
        try? await engine.saveExamples(list, styleID: styleID)
    }

    public func learnStyle(fromFolder path: String) async throws(StyleInferenceError) -> InferredStyle {
        try await engine.learnStyle(fromFolder: path)
    }

    // MARK: Privacy (O5)

    public func clearHistory() async {
        try? await engine.clearHistory(thumbnails: thumbnails)
        await refreshRecent()
    }

    public func clearLearnedData() async {
        try? await engine.clearLearnedData()
        suggestions = []
    }

    /// Resets everything, including onboarding, which starts again from step 1.
    public func resetEverything() async {
        try? await engine.resetEverything(thumbnails: thumbnails)
        engineStarted = false
        preferences = AppPreferences()
        onboarding = OnboardingFlow()
        await store.savePreferences(preferences)
        await store.saveOnboarding(onboarding)
        automaticOffers = []
        await refreshAll()
        onPreferencesChanged(preferences)
    }

    public func diagnosticsReport() async -> String { await engine.diagnosticsReport() }

    // MARK: Explicit requests (Quick Rename, Finder, Shortcuts)

    public func explicitProposals(paths: [String], regenerate: Bool = false) async throws(ExplicitError) -> [ExplicitProposal] {
        try await engine.explicitProposals(paths: paths, regenerate: regenerate)
    }

    public func applyExplicit(_ proposal: ExplicitProposal, typedBase: String?, move: Bool) async throws(ExplicitError) -> String {
        let path = try await engine.applyExplicit(proposal, typedBase: typedBase, move: move)
        await refreshRecent()
        return path
    }

    public func restoreOriginalName(path: String) async -> UndoResult {
        let result = await engine.restoreOriginalName(path: path)
        if case .unavailable(let reason) = result { post(reason) }
        await refreshRecent()
        return result
    }

    /// Whether a path is inside a granted folder (Quick Rename asks for access otherwise, M6).
    public func isGranted(path: String) -> Bool {
        folders.contains { $0.attention == nil && FileSystem.isInside(path, root: $0.path) }
    }
}

/// Stores app preferences through the engine, in config.sqlite.
public struct EnginePreferencesStore: PreferencesStoring {
    let engine: Engine

    public init(engine: Engine) { self.engine = engine }

    public func loadPreferences() async -> AppPreferences? { await engine.appSetting(AppPreferences.self, key: "preferences") }
    public func savePreferences(_ preferences: AppPreferences) async { await engine.setAppSetting(preferences, key: "preferences") }
    public func loadOnboarding() async -> OnboardingFlow? { await engine.appSetting(OnboardingFlow.self, key: "onboarding") }
    public func saveOnboarding(_ flow: OnboardingFlow) async { await engine.setAppSetting(flow, key: "onboarding") }
}
