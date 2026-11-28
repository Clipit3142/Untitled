public import Foundation
public import UntitledCore
public import UntitledFS
public import UntitledStore
public import UntitledModel
public import UntitledExtract

/// The pipeline of 3.5: watch, stability gate, eligibility, extract, generate, validate,
/// format, decide, execute, learn. It has no UI; the app and the tests drive it.
public actor Engine {
    // MARK: Dependencies

    public struct Dependencies: Sendable {
        public var config: ConfigDatabase
        public var history: HistoryDatabase
        public var executor: OperationExecutor
        public var extractor: Extractor
        public var generator: any FieldGenerator
        public var notifier: any NotificationPresenting
        public var power: any PowerMonitoring
        public var bookmarks: any BookmarkProviding
        public var watcherFactory: @Sendable (GrantedFolder) -> any FolderWatcher
        public var availability: @Sendable () -> ModelAvailability
        public var now: @Sendable () -> Date
        public var timeZone: TimeZone
        /// Shortens the stability gate and the maintenance interval in tests.
        public var stabilityInterval: Duration
        public var maintenanceInterval: Duration
        public var generationSleeper: GenerationCoordinator.Sleeper

        public init(config: ConfigDatabase, history: HistoryDatabase, executor: OperationExecutor, extractor: Extractor,
                    generator: any FieldGenerator, notifier: any NotificationPresenting, power: any PowerMonitoring = FixedPower(),
                    bookmarks: any BookmarkProviding, watcherFactory: @escaping @Sendable (GrantedFolder) -> any FolderWatcher,
                    availability: @escaping @Sendable () -> ModelAvailability, now: @escaping @Sendable () -> Date = { Date() },
                    timeZone: TimeZone = .current, stabilityInterval: Duration = .milliseconds(500),
                    maintenanceInterval: Duration = .seconds(5),
                    generationSleeper: @escaping GenerationCoordinator.Sleeper = { try await Task.sleep(for: .seconds($0)) }) {
            self.config = config
            self.history = history
            self.executor = executor
            self.extractor = extractor
            self.generator = generator
            self.notifier = notifier
            self.power = power
            self.bookmarks = bookmarks
            self.watcherFactory = watcherFactory
            self.availability = availability
            self.now = now
            self.timeZone = timeZone
            self.stabilityInterval = stabilityInterval
            self.maintenanceInterval = maintenanceInterval
            self.generationSleeper = generationSleeper
        }
    }

    let deps: Dependencies
    let coordinator: GenerationCoordinator
    var settings = EngineSettings()

    // MARK: State

    var folders: [String: GrantedFolder] = [:]
    var snapshots: [String: FolderSnapshot] = [:]
    var watchers: [String: any FolderWatcher] = [:]
    var watchTasks: [String: Task<Void, Never>] = [:]
    var burstGuards: [String: BurstGuard] = [:]
    var burstCounts: [String: Int] = [:]
    var batcher = NotificationBatcher()
    var pause = PauseState.none
    var items: [String: QueueItem] = [:]
    var stabilizing: Set<FileIdentity> = []
    /// Folders with arrivals still settling; their queued files wait, so a bulk copy is seen
    /// whole by the burst guard before anything is renamed (3.6).
    var settlingFolders: [String: Int] = [:]
    /// Arrival order, fixed when a file is first seen and kept if it is renamed while it
    /// settles (a temporary file getting its real name), so the queue follows arrival order (F6).
    var arrivalNumbers: [FileIdentity: Int64] = [:]
    var nextArrivalNumber: Int64 = 0
    var workerTask: Task<Void, Never>?
    var workerWake: AsyncStream<Void>.Continuation?
    var maintenanceTask: Task<Void, Never>?
    var subscribers: [UUID: AsyncStream<EngineEvent>.Continuation] = [:]
    var modelStatus: GenerationStatus = .idle
    var lastPurge: Date?
    var started = false
    var ruleWarnings: Set<String> = []
    var recentFacts: [RecentFacts] = []
    var lastOperationID: Int64?
    /// True while the worker is naming a file; the menu bar glyph animates only then (3.16).
    var working = false

    public init(_ dependencies: Dependencies) {
        deps = dependencies
        let relay = StatusRelay()
        coordinator = GenerationCoordinator(
            generator: dependencies.generator, availability: dependencies.availability,
            sleeper: dependencies.generationSleeper, now: dependencies.now,
            onStatus: { status in relay.forward(status) }
        )
        relay.engine = self
    }

    // MARK: Events

    public func events() -> AsyncStream<EngineEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        return stream
    }

    func unsubscribe(_ id: UUID) { subscribers.removeValue(forKey: id) }

    func emit(_ event: EngineEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    func setModelStatus(_ status: GenerationStatus) {
        guard status != modelStatus else { return }
        modelStatus = status
        emit(.statusChanged)
    }

    // MARK: Start and stop

    /// Starts the engine: reconciles the journal, purges old history, restores the queue
    /// and starts watching. Call only after onboarding finished or was skipped (B7).
    public func start() async throws {
        guard !started else { return }
        started = true
        settings = (try? deps.config.setting(EngineSettings.self, key: "engineSettings")) ?? EngineSettings()
        pause = (try? deps.config.setting(PauseState.self, key: "pause")) ?? .none
        ruleWarnings = (try? deps.config.setting(Set<String>.self, key: "ruleWarnings")) ?? []
        recentFacts = (try? deps.config.setting([RecentFacts].self, key: "recentFacts")) ?? []
        _ = try? Reconciler(journal: deps.history).reconcile()
        purgeIfDue(force: true)
        for folder in try deps.config.folders() { folders[folder.id] = folder }
        restoreQueue()
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        workerWake = continuation
        workerTask = Task { [weak self] in
            for await _ in stream {
                guard let self else { return }
                await self.drainQueue()
            }
        }
        for folder in folders.values where folder.role == .watched && folder.mode != .off {
            startWatching(folder)
        }
        maintenanceTask = Task { [weak self, interval = deps.maintenanceInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await self?.maintenance()
            }
        }
        wakeWorker()
        emit(.statusChanged)
    }

    public func stop() {
        for watcher in watchers.values { watcher.stop() }
        for task in watchTasks.values { task.cancel() }
        watchers.removeAll()
        watchTasks.removeAll()
        workerTask?.cancel()
        workerWake?.finish()
        maintenanceTask?.cancel()
        started = false
    }

    func wakeWorker() { workerWake?.yield() }

    /// Restores the queue after a restart (M3). Items whose files vanished are removed with a note.
    func restoreQueue() {
        for item in (try? deps.history.queueItems()) ?? [] {
            if FileSystem.status(atPath: item.path)?.identity == item.expected.identity {
                items[item.id] = item
            } else {
                try? deps.history.removeQueueItem(id: item.id)
                note("Removed from Review: “\(item.expected.name)” is no longer there.")
            }
        }
    }

    func note(_ message: String) {
        try? deps.history.addNote(ActivityNote(time: deps.now(), message: message))
        emit(.historyChanged)
    }

    // MARK: Watching (3.5 step 1)

    func startWatching(_ folder: GrantedFolder) {
        guard watchTasks[folder.id] == nil else { return }
        guard FileSystem.status(atPath: folder.path)?.isDirectory == true else {
            markAttention(folder.id, missing: true)
            return
        }
        if case .unsupported = VolumePolicy.check(path: folder.path) {
            markAttention(folder.id, missing: false)
            return
        }
        // The saved snapshot lets renames made while the app was quit count as renames (D9),
        // and files added while it was quit count as arrivals (C4).
        let saved = (try? deps.config.snapshot(folderID: folder.id)) ?? nil
        if let saved {
            snapshots[folder.id] = saved
        } else {
            // The first scan of a folder. Files added after the watch start but before watching
            // began (for example during onboarding) stay out of the baseline, so they arrive (C4).
            let scanned = (try? FolderSnapshot.scan(folder.path)) ?? FolderSnapshot()
            let baseline = FolderSnapshot(entries: scanned.entries.filter { _, entry in
                guard let read = FileFactsReader.read(path: FileSystem.join(folder.path, entry.name), isTopLevel: true),
                      let added = read.facts.dateAdded else { return true }
                return added < folder.watchStart
            })
            snapshots[folder.id] = baseline
            try? deps.config.saveSnapshot(baseline, folderID: folder.id)
        }
        let watcher = deps.watcherFactory(folder)
        watchers[folder.id] = watcher
        let signals = watcher.signals()
        let id = folder.id
        watchTasks[folder.id] = Task { [weak self] in
            await self?.rescan(folderID: id)
            for await signal in signals {
                guard let self else { return }
                switch signal {
                case .changed, .mustRescan: await self.rescan(folderID: id)
                case .rootChanged: await self.rootChanged(folderID: id)
                }
            }
        }
        if folders[folder.id]?.attention != nil {
            folders[folder.id]?.attention = nil
            try? deps.config.save(folders[folder.id]!)
            emit(.foldersChanged)
        }
    }

    func stopWatching(_ folderID: String) {
        watchers[folderID]?.stop()
        watchers.removeValue(forKey: folderID)
        watchTasks[folderID]?.cancel()
        watchTasks.removeValue(forKey: folderID)
    }

    func rootChanged(folderID: String) {
        guard let folder = folders[folderID] else { return }
        stopWatching(folderID)
        markAttention(folderID, missing: FileSystem.status(atPath: FileSystem.parent(folder.path)) != nil)
    }

    /// C2 and C5: a missing folder needs Reconnect; a folder on an unmounted volume is Disconnected.
    func markAttention(_ folderID: String, missing: Bool) {
        guard var folder = folders[folderID] else { return }
        let attention: FolderAttention = missing ? .needsReconnect : .disconnected
        guard folder.attention != attention else { return }
        folder.attention = attention
        folders[folderID] = folder
        try? deps.config.save(folder)
        emit(.foldersChanged)
        emit(.statusChanged)
    }

    func rescan(folderID: String) async {
        // A stopped engine leaves snapshots alone, so the next launch still sees what changed.
        guard started, let folder = folders[folderID], var snapshot = snapshots[folderID] else { return }
        guard let current = try? FolderSnapshot.scan(folder.path) else {
            rootChanged(folderID: folderID)
            return
        }
        let events = snapshot.update(to: current)
        snapshots[folderID] = snapshot
        guard !events.isEmpty else { return }
        try? deps.config.saveSnapshot(snapshot, folderID: folderID)
        var arrivals: [FolderEntry] = []
        for event in events {
            switch event {
            case .arrived(let entry):
                if deps.executor.suppression.isSuppressed(entry.identity, now: deps.now()) { continue }
                if stabilizing.contains(entry.identity) || items.values.contains(where: { $0.expected.identity == entry.identity }) { continue }
                arrivals.append(entry)
            case .renamedInPlace(let entry, let oldName):
                if deps.executor.suppression.isSuppressed(entry.identity, now: deps.now()) { continue }
                // A finished download or an atomic save renames an in-progress or hidden
                // file to its real name; that file has just arrived (Part 5 #47).
                if Eligibility.isInProgress(oldName) || oldName.hasPrefix(".") {
                    if stabilizing.contains(entry.identity) || items.values.contains(where: { $0.expected.identity == entry.identity }) { continue }
                    arrivals.append(entry)
                    continue
                }
                // Any other rename in place never starts processing (D9). A Finder rename of
                // a file Untitled named may be feedback (I5).
                learnFromFinderRename(folder: folder, entry: entry, oldName: oldName)
            case .removed:
                break
            }
        }
        scheduleArrivals(folderID: folderID, entries: arrivals)
    }

    /// Waits for a batch of arrivals to settle, then admits them in arrival order (F6).
    func scheduleArrivals(folderID: String, entries arrivals: [FolderEntry]) {
        guard !arrivals.isEmpty, let folder = folders[folderID] else { return }
        if nextArrivalNumber == 0 { nextArrivalNumber = (try? deps.history.nextArrival()) ?? 1 }
        for entry in arrivals where arrivalNumbers[entry.identity] == nil {
            arrivalNumbers[entry.identity] = nextArrivalNumber
            nextArrivalNumber += 1
        }
        for entry in arrivals { stabilizing.insert(entry.identity) }
        settlingFolders[folderID, default: 0] += 1
        let wait = Duration.milliseconds(Int(settings.stabilityWait * 1_000))
        let gate = StabilityGate(wait: wait, interval: deps.stabilityInterval)
        let path = folder.path
        Task { [weak self] in
            let stable = await withTaskGroup(of: (Int, FolderEntry, FileStatus?).self) { group in
                for (index, entry) in arrivals.enumerated() {
                    group.addTask {
                        let status = try? await gate.waitUntilStable(path: FileSystem.join(path, entry.name), identity: entry.identity)
                        return (index, entry, status)
                    }
                }
                var results: [(Int, FolderEntry, FileStatus?)] = []
                for await result in group { results.append(result) }
                return results.sorted { $0.0 < $1.0 }
            }
            await self?.admit(folderID: folderID, stable: stable.map { ($0.1, $0.2) })
        }
    }

    /// Eligibility and the burst guard for a batch of stable arrivals (3.6).
    func admit(folderID: String, stable: [(FolderEntry, FileStatus?)]) {
        guard started else {
            for (entry, _) in stable { stabilizing.remove(entry.identity) }
            return
        }
        defer {
            for (entry, _) in stable { stabilizing.remove(entry.identity) }
            settlingFolders[folderID, default: 1] -= 1
            if settlingFolders[folderID] == 0 { settlingFolders.removeValue(forKey: folderID) }
        }
        guard let folder = folders[folderID] else { return }
        let paused = pause.isPaused(at: deps.now())
        var renamedWhileSettling: [FolderEntry] = []
        defer {
            // A file renamed while it settled (a temporary file getting its real name) is
            // followed under its new name.
            if !renamedWhileSettling.isEmpty { scheduleArrivals(folderID: folderID, entries: renamedWhileSettling) }
        }
        for (entry, status) in stable {
            guard let status else {
                if let current = snapshots[folderID]?.entries[entry.identity], current.name != entry.name {
                    renamedWhileSettling.append(current)
                } else {
                    arrivalNumbers.removeValue(forKey: entry.identity)
                }
                continue
            }
            let path = FileSystem.join(folder.path, entry.name)
            guard let read = FileFactsReader.read(
                path: path, isTopLevel: true,
                seen: { identity, added in (try? self.deps.history.hasSeen(identity: identity, dateAdded: added)) ?? false },
                ignored: { identity in (try? self.deps.config.isIgnored(identity: identity)) ?? false }
            ), read.status.identity == entry.identity else { continue }
            let decision = Eligibility.evaluate(read.facts, folder: folder.policy, request: .automatic, paused: paused)
            switch decision {
            case .skip:
                arrivalNumbers.removeValue(forKey: entry.identity)
                continue
            case .process, .metadataOnly:
                break
            }
            let arrivalTime = deps.now()
            var guardState = burstGuards[folderID] ?? BurstGuard()
            let group = guardState.recordArrival(at: arrivalTime)
            burstGuards[folderID] = guardState
            var groupID: String?
            if let group {
                groupID = "\(folderID)-burst-\(group)"
                // Files of this folder still waiting join the burst (Part 5 #37).
                if burstCounts[groupID!] == nil {
                    for (id, waiting) in items where waiting.folderID == folderID && waiting.status == .pending
                        && waiting.burstGroup == nil && waiting.createdAt >= arrivalTime.addingTimeInterval(-Defaults.burstWindow) {
                        items[id]?.burstGroup = groupID
                        try? deps.history.save(items[id]!)
                        burstCounts[groupID!, default: 0] += 1
                    }
                }
                burstCounts[groupID!, default: 0] += 1
                deps.notifier.postBurst(groupID: groupID!, count: burstCounts[groupID!]!)
            }
            let arrival = arrivalNumbers.removeValue(forKey: entry.identity) ?? nextArrivalNumber
            nextArrivalNumber = max(nextArrivalNumber, arrival + 1)
            let item = QueueItem(arrival: arrival, folderID: folderID, directory: folder.path,
                                 expected: ExpectedFile(status: status, name: entry.name), dateAdded: read.facts.dateAdded,
                                 status: .pending, burstGroup: groupID, request: .automatic, createdAt: arrivalTime)
            items[item.id] = item
            try? deps.history.save(item)
            if let style = try? style(for: folder) {
                let instructions = PromptBuilder.instructions(style: style, language: style.nameLanguage ?? .english)
                let coordinator = self.coordinator
                Task { await coordinator.noteArrival(instructions: instructions) }
            }
        }
        emit(.queueChanged)
        // Woken after the deferred settling count drops (see `defer` above).
        Task { [weak self] in await self?.wakeWorker() }
    }

    // MARK: Worker (3.5 steps 4–9)

    /// Processes pending items one at a time, in arrival order.
    func drainQueue() async {
        guard started else { return }
        defer { setWorking(false) }
        while let next = items.values.filter({ $0.status == .pending && settlingFolders[$0.folderID ?? ""] == nil })
            .min(by: { $0.arrival < $1.arrival }) {
            if holdReason() != nil { return }
            setWorking(true)
            await process(next)
        }
        if modelStatus == .idle { emit(.statusChanged) }
    }

    func setWorking(_ value: Bool) {
        guard working != value else { return }
        working = value
        emit(.statusChanged)
    }

    func holdReason() -> HoldReason? {
        let reason = ProcessingGate.holdReason(pause: .none, power: deps.power.conditions(), settings: settings.processing, now: deps.now())
        return reason
    }

    func style(for folder: GrantedFolder) throws -> NamingStyle {
        if let stored = try deps.config.style(id: folder.styleID) { return stored }
        return Presets.all.first { $0.id == folder.styleID } ?? Presets.clean
    }

    func builder(style: NamingStyle) -> ProposalBuilder {
        ProposalBuilder(style: style, customKinds: (try? deps.config.customKinds()) ?? [], rules: (try? deps.config.rules()) ?? [],
                        destinations: (try? deps.config.destinations()) ?? [], folders: Array(folders.values), timeZone: deps.timeZone)
    }

    /// Builds a proposal for a file. Extracted text lives only inside this call (3.18).
    func makeProposal(path: String, facts: FileFacts, metadataOnly: MetadataOnlyReason?, style: NamingStyle,
                      sampling: Sampling, priority: RequestPriority) async -> (Proposal, String?) {
        let extraction = await deps.extractor.extract(path: path, facts: facts, metadataOnly: metadataOnly,
                                                      options: ReadOptions(pdfPages: settings.pdfPages, includeImageForModel: settings.imageInput))
        let builder = builder(style: style)
        let language = style.nameLanguage ?? extraction.language ?? .english
        let examples = ((try? deps.config.examples(styleID: style.id)) ?? ExampleList()).forPrompt
        let evidence = extraction.evidence(timeZone: deps.timeZone)
        let app = extraction.metadata.isScreenshot ? extraction.metadata.appAtCapture : nil
        let request = GenerationRequest(
            metadata: PromptBuilder.metadata(originalName: extraction.strippedOriginal, downloadDomain: extraction.metadata.downloadDomain,
                                             app: app, isScreenshot: extraction.metadata.isScreenshot,
                                             kindHint: FileExtension.typeKey(facts.name)?.uppercased(),
                                             candidates: extraction.candidates, labels: extraction.content.labels.map(\.identifier)),
            content: extraction.contentLines, image: extraction.content.image, examples: examples,
            schema: SchemaSpec(customKinds: builder.customKinds, candidates: extraction.candidates, subjectMaxWords: style.subjectWords),
            instructions: PromptBuilder.instructions(style: style, language: language), sampling: sampling, priority: priority
        )
        let availability = settings.basicNamingOnly ? ModelAvailability.basicOnly : deps.availability()
        let outcome: GenerationOutcome = extraction.metadataOnly || !availability.usesModel
            ? .basic(.unavailable(availability))
            : await coordinator.generate(request)
        var generated: GeneratedFields
        var path: NamingPath
        var reason: BasicReason?
        switch outcome {
        case .model(let fields):
            generated = fields
            path = .model
        case .basic(let basicReason):
            var input = extraction.basicInput
            input.fileExtension = FileExtension.typeKey(facts.name)
            generated = BasicNamer.fields(input)
            path = .basic
            reason = basicReason
            if case .unavailable = basicReason { reason = nil }
        }
        let proposal = builder.proposal(currentName: facts.name, generated: generated, path: path, basicReason: reason,
                                        evidence: evidence, language: language, app: app, original: extraction.strippedOriginal)
        return (proposal, extraction.metadata.downloadDomain)
    }

    func process(_ item: QueueItem) async {
        guard FileSystem.status(atPath: item.path)?.identity == item.expected.identity,
              let read = FileFactsReader.read(path: item.path, isTopLevel: true) else {
            drop(item, note: "Removed from Review: “\(item.expected.name)” is no longer there.")
            return
        }
        guard let folderID = item.folderID, let folder = folders[folderID], let style = try? style(for: folder) else {
            drop(item, note: nil)
            return
        }
        var metadataOnly: MetadataOnlyReason?
        if case .metadataOnly(let reason) = Eligibility.evaluate(read.facts, folder: folder.policy, request: .explicit, paused: false) {
            metadataOnly = reason
        }
        emit(.statusChanged)
        let (proposal, domain) = await makeProposal(path: item.path, facts: read.facts, metadataOnly: metadataOnly, style: style,
                                                    sampling: .greedy, priority: .background)
        guard var current = items[item.id] else { return }
        current.proposal = proposal
        recordFacts(proposal: proposal, name: item.expected.name, domain: domain)
        let burstActive = burstGuards[folderID]?.activeGroup(at: deps.now()) != nil
        if item.request == .automatic, folder.mode == .automatic, proposal.confidence == .high, current.burstGroup == nil, !burstActive {
            items[item.id] = current
            _ = await execute(itemID: item.id, method: .automatic, finalName: nil, moveEnabled: true, batchID: nil, edited: false)
        } else {
            current.status = .review
            if burstActive, current.burstGroup == nil, let group = burstGuards[folderID]?.activeGroup(at: deps.now()) {
                current.burstGroup = "\(folderID)-burst-\(group)"
            }
            items[item.id] = current
            try? deps.history.save(current)
            if current.burstGroup == nil, item.request == .automatic {
                deps.notifier.postReview(itemID: current.id, oldName: current.expected.name, proposedName: proposal.fileName)
            }
            emit(.queueChanged)
        }
    }

    func drop(_ item: QueueItem, note message: String?) {
        items.removeValue(forKey: item.id)
        try? deps.history.removeQueueItem(id: item.id)
        if let message { note(message) }
        emit(.queueChanged)
    }

    // MARK: Execute (3.5 step 9, 3.13)

    /// Renames (and moves) a queued item. Returns the history entry ID on success.
    func execute(itemID: String, method: OperationMethod, finalName: String?, moveEnabled: Bool, batchID: String?,
                 edited: Bool) async -> Int64? {
        guard let item = items[itemID], let proposal = item.proposal else { return nil }
        let folder = item.folderID.flatMap { folders[$0] }
        let style = (folder.flatMap { try? style(for: $0) }) ?? Presets.clean
        let builder = builder(style: style)
        let currentName = item.expected.name
        let names: @Sendable (Int?) -> String
        if let finalName {
            let separator = style.suffixSeparator
            let split = FileExtension.split(finalName)
            names = { n in
                guard let n else { return finalName }
                return split.base + separator + String(n) + (split.extension.map { "." + $0 } ?? "")
            }
        } else {
            names = { n in builder.name(for: proposal, currentName: currentName, collision: n) }
        }
        var destinationPath = item.directory
        var subfolders: [String] = []
        var missingDestination = false
        if moveEnabled, let destinationID = proposal.destinationID,
           let destination = builder.destinations.first(where: { $0.id == destinationID }),
           let target = folders[destination.folderID] {
            if FileSystem.status(atPath: target.path)?.isDirectory == true {
                destinationPath = target.path
                subfolders = proposal.subfolder
            } else {
                missingDestination = true
            }
        }
        let bookmark = try? deps.bookmarks.fileBookmark(for: URL(fileURLWithPath: item.path))
        let request = OperationRequest(
            directory: item.directory, expected: item.expected, destinationDirectory: destinationPath, subfolders: subfolders,
            names: names, grantedRoots: grantedRoots(), method: method,
            metadata: JournalMetadata(styleID: style.id, styleVersion: style.version, namingPath: finalName == nil ? proposal.path : .typed,
                                      confidence: proposal.confidence, batchID: batchID, bookmark: bookmark),
            marker: .renamed(originalName: currentName)
        )
        do {
            let outcome = try deps.executor.execute(request)
            try? deps.history.setDateAdded(item.dateAdded, for: outcome.entryID)
            items.removeValue(forKey: itemID)
            try? deps.history.removeQueueItem(id: itemID)
            lastOperationID = outcome.entryID
            if missingDestination, let ruleID = proposal.ruleID {
                ruleWarnings.insert(ruleID)
                try? deps.config.setSetting(ruleWarnings, key: "ruleWarnings")
                note("“\(FileSystem.name(outcome.newPath))” was renamed in place because its destination folder is missing.")
            }
            if method == .automatic { notifyRenamed(entryID: outcome.entryID, oldName: currentName, newName: FileSystem.name(outcome.newPath)) }
            if method == .review || method == .notification {
                acceptedInReview(folderID: item.folderID, finalName: FileSystem.name(outcome.newPath), style: style, edited: edited)
            }
            emit(.queueChanged)
            emit(.historyChanged)
            return outcome.entryID
        } catch {
            switch error {
            case .namedBySomeoneElse, .sourceMissing:
                drop(item, note: "“\(currentName)” was left alone: \(error.note.lowercased()).")
            default:
                var kept = item
                kept.status = .review
                items[itemID] = kept
                try? deps.history.save(kept)
                emit(.notice("Couldn't rename “\(currentName)”: \(error.note)."))
                emit(.queueChanged)
            }
            return nil
        }
    }

    func grantedRoots() -> [String] {
        folders.values.filter { $0.attention == nil }.map(\.path)
    }

    func notifyRenamed(entryID: Int64, oldName: String, newName: String) {
        for action in batcher.record(operationID: String(entryID), at: deps.now()) {
            switch action {
            case .postSingle:
                deps.notifier.postRenamed(operationID: entryID, oldName: oldName, newName: newName)
            case .removeSingles(let ids):
                deps.notifier.removeRenamed(operationIDs: ids.compactMap { Int64($0) })
            case .postSummary(let summaryID, let ids):
                deps.notifier.postSummary(summaryID: summaryID, operationIDs: ids.compactMap { Int64($0) })
            }
        }
    }

    // MARK: Maintenance

    func maintenance() async {
        let now = deps.now()
        if pause.option != nil, !pause.isPaused(at: now) {
            pause = .none
            try? deps.config.setSetting(pause, key: "pause")
            emit(.statusChanged)
        }
        // C5: watching resumes when a disconnected or missing folder comes back.
        for folder in folders.values where folder.attention != nil && folder.role == .watched && folder.mode != .off {
            if FileSystem.status(atPath: folder.path)?.isDirectory == true, folder.attention == .disconnected || folder.attention == .needsReconnect {
                if folder.attention == .disconnected { startWatching(folder) }
            }
        }
        purgeIfDue(force: false)
        if holdReason() == nil, items.values.contains(where: { $0.status == .pending }) { wakeWorker() }
    }

    /// Purges finished history older than the retention, once a day (L6).
    func purgeIfDue(force: Bool) {
        let now = deps.now()
        if !force, let last = lastPurge, now.timeIntervalSince(last) < 86_400 { return }
        lastPurge = now
        if let cutoff = Retention.cutoff(now: now, days: settings.historyRetentionDays) {
            _ = try? deps.history.purge(before: cutoff)
        }
    }
}

/// Forwards coordinator status to the engine without a strong cycle.
final class StatusRelay: @unchecked Sendable {
    // @unchecked: `engine` is set once during Engine.init, before any status is forwarded.
    weak var engine: Engine?

    func forward(_ status: GenerationStatus) {
        guard let engine else { return }
        Task { await engine.setModelStatus(status) }
    }
}

/// Facts of recently processed files, for the rule tester (K1).
public struct RecentFacts: Codable, Sendable, Hashable {
    public var name: String
    public var facts: RuleFacts
    public var matchedRuleID: String?
}
