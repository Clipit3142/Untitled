import Foundation
public import UntitledCore
public import UntitledFS
public import UntitledStore
public import UntitledModel
import UntitledExtract

/// An edit made in Review before accepting.
public enum ReviewEdit: Sendable, Hashable {
    case fields(NameFields)
    case typed(String)
}

public struct AcceptReport: Sendable, Hashable {
    public var renamed: [Int64] = []
    public var failed: [String] = []
    public var cancelledRemaining = 0
}

extension Engine {
    // MARK: Queue and Review (3.15)

    public func queue() -> [QueueItem] {
        items.values.sorted { $0.arrival < $1.arrival }
    }

    public func reviewItems() -> [QueueItem] {
        queue().filter { $0.status == .review }
    }

    /// Re-formats an item from edited fields; no model call (M2).
    public func updateFields(itemID: String, fields: NameFields) throws -> Proposal? {
        guard var item = items[itemID], var proposal = item.proposal, let folder = item.folderID.flatMap({ folders[$0] }) else { return nil }
        proposal.fields = fields
        proposal = builder(style: try style(for: folder)).reformatted(proposal, currentName: item.expected.name, downloadDomain: nil)
        item.proposal = proposal
        items[itemID] = item
        try deps.history.save(item)
        emit(.queueChanged)
        return proposal
    }

    /// What a typed name becomes; the notice is shown before saving (H9).
    public func previewTyped(itemID: String, name: String) -> TypedName.Result? {
        guard let item = items[itemID] else { return nil }
        let style = item.folderID.flatMap { folders[$0] }.flatMap { try? self.style(for: $0) } ?? Presets.clean
        return try? TypedName.prepare(name, fileExtension: FileExtension.split(item.expected.name).extension, extensionCase: style.extensionCase)
    }

    /// Accepts items, reporting progress; cancelling the calling task leaves the remaining files untouched (M4).
    public func accept(itemIDs: [String], edits: [String: ReviewEdit] = [:], moveEnabled: [String: Bool] = [:],
                       method: OperationMethod = .review,
                       progress: @Sendable (Int, Int) -> Void = { _, _ in }) async -> AcceptReport {
        var report = AcceptReport()
        let batchID = itemIDs.count > 1 ? UUID().uuidString : nil
        for (index, id) in itemIDs.enumerated() {
            if Task.isCancelled {
                report.cancelledRemaining = itemIDs.count - index
                break
            }
            guard let item = items[id], let original = item.proposal else { continue }
            var finalName: String?
            var edited = false
            switch edits[id] {
            case .fields(let fields):
                _ = try? updateFields(itemID: id, fields: fields)
                edited = fields != original.fields
            case .typed(let typed):
                if let prepared = previewTyped(itemID: id, name: typed) {
                    finalName = prepared.fileName
                    edited = prepared.fileName != original.fileName
                }
            case nil:
                break
            }
            let proposedName = items[id]?.proposal?.fileName ?? original.fileName
            if let entryID = await execute(itemID: id, method: method, finalName: finalName, moveEnabled: moveEnabled[id] ?? true,
                                           batchID: batchID, edited: edited) {
                report.renamed.append(entryID)
                if edited, let final = finalName ?? (try? deps.history.entry(entryID))?.newName {
                    learn(proposed: original, proposedName: proposedName, final: final, folderID: item.folderID)
                }
            } else {
                report.failed.append(item.expected.name)
            }
            progress(index + 1, itemIDs.count)
        }
        return report
    }

    /// Skip leaves the file alone and stops it from being proposed again.
    public func skip(itemIDs: [String]) {
        for id in itemIDs {
            guard let item = items[id] else { continue }
            try? deps.config.ignore(identity: item.expected.identity, name: item.expected.name, at: deps.now())
            drop(item, note: nil)
        }
    }

    // MARK: Learning (3.11)

    func learn(proposed: Proposal, proposedName: String, final: String, folderID: String?) {
        guard let folder = folderID.flatMap({ folders[$0] }), let style = try? style(for: folder) else { return }
        let formatted = FormattedName(base: FileExtension.split(proposedName).base, fileName: proposedName, parts: proposed.parts,
                                      missingRequiredTokens: [], subjectWordsBefore: 0, subjectWordsRemovedByGuards: 0, droppedTokens: [])
        let patterns = EditAnalyzer.patterns(proposed: formatted, final: final, style: style, language: proposed.language)
        guard !patterns.isEmpty else { return }
        try? deps.config.addLearningEvents(patterns.map { EditEvent(pattern: $0, styleID: style.id, date: deps.now()) })
        emit(.suggestionsChanged)
    }

    /// Finder renames of a marked file within 7 days of Untitled's rename count as edits (I5).
    func learnFromFinderRename(folder: GrantedFolder, entry: FolderEntry, oldName: String) {
        let path = FileSystem.join(folder.path, entry.name)
        guard let marker = Marker.read(atPath: path), marker.state == .renamed,
              let last = try? deps.history.latestDone(identity: entry.identity), last.newName == oldName,
              deps.now().timeIntervalSince(last.time) <= Defaults.finderEditWindow,
              let style = try? style(for: folder) else { return }
        let formatted = FormattedName(base: FileExtension.split(oldName).base, fileName: oldName, parts: [],
                                      missingRequiredTokens: [], subjectWordsBefore: 0, subjectWordsRemovedByGuards: 0, droppedTokens: [])
        let patterns = EditAnalyzer.patterns(proposed: formatted, final: entry.name, style: style, language: style.nameLanguage ?? .english)
        guard !patterns.isEmpty else { return }
        try? deps.config.addLearningEvents(patterns.map { EditEvent(pattern: $0, styleID: style.id, date: deps.now()) })
        emit(.suggestionsChanged)
    }

    func acceptedInReview(folderID: String?, finalName: String, style: NamingStyle, edited: Bool) {
        var examples = (try? deps.config.examples(styleID: style.id)) ?? ExampleList()
        examples.add(finalName)
        try? deps.config.saveExamples(examples, styleID: style.id)
        guard let folderID, var folder = folders[folderID] else { return }
        folder.offer.recordAccepted(edited: edited)
        if folder.offer.shouldOffer(mode: folder.mode) {
            folder.offer.offered = true
            emit(.automaticOffer(folderID: folderID))
        }
        folders[folderID] = folder
        try? deps.config.save(folder)
    }

    public func pendingSuggestions() -> [Suggestion] {
        let events = (try? deps.config.learningEvents()) ?? []
        let answers = (try? deps.config.suggestionAnswers()) ?? SuggestionAnswers()
        return SuggestionEngine.pending(events: events, answers: answers, now: deps.now())
    }

    public func answer(_ answer: SuggestionEngine.Answer, to suggestion: Suggestion) throws {
        var answers = try deps.config.suggestionAnswers()
        let style = try deps.config.style(id: suggestion.styleID) ?? Presets.all.first { $0.id == suggestion.styleID } ?? Presets.clean
        if let changed = SuggestionEngine.answer(answer, to: suggestion, answers: &answers, style: style, now: deps.now()) {
            try saveStyle(changed)
        }
        try deps.config.saveSuggestionAnswers(answers)
        emit(.suggestionsChanged)
    }

    // MARK: Styles (H8)

    /// Saves a style and re-formats queued proposals that use it, without calling the model.
    @discardableResult
    public func saveStyle(_ style: NamingStyle) throws -> Duration {
        try deps.config.save(style)
        let clock = ContinuousClock()
        let start = clock.now
        let builder = builder(style: style)
        for (id, item) in items {
            guard let proposal = item.proposal, let folder = item.folderID.flatMap({ folders[$0] }), folder.styleID == style.id else { continue }
            var updated = item
            updated.proposal = builder.reformatted(proposal, currentName: item.expected.name, downloadDomain: nil)
            items[id] = updated
        }
        let elapsed = clock.now - start
        for item in items.values where item.proposal?.styleID == style.id { try? deps.history.save(item) }
        emit(.queueChanged)
        return elapsed
    }

    // MARK: Folders

    public func allFolders() -> [GrantedFolder] {
        folders.values.sorted { $0.displayName < $1.displayName }
    }

    /// Adds a granted folder. Volumes other than APFS and Mac OS Extended are refused (C6);
    /// project-like folders need `confirmedProject` (C7).
    public func addFolder(_ folder: GrantedFolder, confirmedProject: Bool = false) throws {
        if case .unsupported(let reason) = VolumePolicy.check(path: folder.path) { throw FolderError.unsupportedVolume(reason) }
        if folder.role == .watched, !confirmedProject, !ProjectFolderDetector.markers(in: folder.path).isEmpty {
            throw FolderError.projectFolder(ProjectFolderDetector.markers(in: folder.path))
        }
        var stored = folder
        stored.projectConfirmed = confirmedProject
        folders[folder.id] = stored
        try deps.config.save(stored)
        if started, stored.role == .watched, stored.mode != .off { startWatching(stored) }
        emit(.foldersChanged)
        emit(.statusChanged)
    }

    public func updateFolder(_ folder: GrantedFolder) throws {
        let previous = folders[folder.id]
        if previous?.bookmark != folder.bookmark || previous?.path != folder.path { closeAccess(folder.id) }
        folders[folder.id] = folder
        try deps.config.save(folder)
        if folder.role == .watched, folder.mode != .off {
            if previous?.path != folder.path { stopWatching(folder.id) }
            if started { startWatching(folder) }
        } else {
            stopWatching(folder.id)
        }
        emit(.foldersChanged)
        emit(.statusChanged)
    }

    public func removeFolder(id: String) throws {
        stopWatching(id)
        closeAccess(id)
        folders.removeValue(forKey: id)
        try deps.config.deleteFolder(id: id)
        emit(.foldersChanged)
        emit(.statusChanged)
    }

    public func ruleHasWarning(_ ruleID: String) -> Bool { ruleWarnings.contains(ruleID) }

    public func clearRuleWarning(_ ruleID: String) {
        ruleWarnings.remove(ruleID)
        try? deps.config.setSetting(ruleWarnings, key: "ruleWarnings")
    }

    // MARK: Pause (3.15, N4)

    public func pause(_ option: PauseOption) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = deps.timeZone
        pause = .paused(option, now: deps.now(), calendar: calendar)
        try? deps.config.setSetting(pause, key: "pause")
        emit(.statusChanged)
    }

    public func resume() {
        pause = .none
        try? deps.config.setSetting(pause, key: "pause")
        emit(.statusChanged)
        wakeWorker()
    }

    public func pauseState() -> PauseState { pause }

    public func updateSettings(_ new: EngineSettings) {
        settings = new
        try? deps.config.setSetting(new, key: "engineSettings")
        emit(.statusChanged)
        wakeWorker()
    }

    public func currentSettings() -> EngineSettings { settings }

    /// Re-checks power conditions now (the app calls this on power notifications).
    public func powerChanged() {
        emit(.statusChanged)
        if holdReason() == nil { wakeWorker() }
    }

    // MARK: Status (3.15)

    public func status() -> EngineStatus {
        let now = deps.now()
        if pause.isPaused(at: now) { return .paused(until: pause.until) }
        if let hold = holdReason() { return .held(hold) }
        if case .waitingForAppleIntelligence = modelStatus { return .waitingForAppleIntelligence }
        if let attention = folders.values.first(where: { $0.attention != nil && $0.role == .watched }) {
            return .needsAttention(folderName: attention.displayName)
        }
        let watched = folders.values.filter { $0.role == .watched && $0.mode != .off }.map(\.displayName).sorted()
        if watched.isEmpty { return .notWatching }
        if settings.basicNamingOnly || !deps.availability().usesModel { return .basicNaming(folderNames: watched) }
        return .watching(folderNames: watched)
    }

    public func reviewCount() -> Int { items.values.filter { $0.status == .review }.count }

    /// Whether a file is being named right now.
    public func isWorking() -> Bool { working }

    /// The model's current state, for the Apple Intelligence settings and the status pill.
    public func modelAvailability() -> ModelAvailability {
        settings.basicNamingOnly ? .basicOnly : deps.availability()
    }

    // MARK: Rule tester (K1)

    func recordFacts(proposal: Proposal, name: String, domain: String?) {
        let facts = RuleFacts(kind: proposal.fields.kind, source: proposal.fields.source, downloadDomain: domain,
                              isScreenshot: proposal.isScreenshot, app: proposal.fields.app, fileName: name, originalName: name)
        recentFacts.append(RecentFacts(name: name, facts: facts, matchedRuleID: proposal.ruleID))
        if recentFacts.count > 50 { recentFacts.removeFirst(recentFacts.count - 50) }
        try? deps.config.setSetting(recentFacts, key: "recentFacts")
    }

    /// Which of the last 50 processed files a rule would match (3.12).
    public func testRule(_ rule: Rule) -> [(name: String, matches: Bool)] {
        recentFacts.map { ($0.name, RuleEngine.matches(rule, facts: $0.facts)) }
    }

    public func recentProcessedFacts() -> [RecentFacts] { recentFacts }

    // MARK: Diagnostics (W2)

    /// A diagnostics report with counts and settings only: no names, paths or content.
    public func diagnosticsReport() -> String {
        let history = deps.history
        var lines = ["Untitled diagnostics", "Generated: \(ISO8601DateFormatter().string(from: deps.now()))"]
        lines.append("Folders: \(folders.count) (watched: \(folders.values.filter { $0.role == .watched }.count), needing attention: \(folders.values.filter { $0.attention != nil }.count))")
        lines.append("Folder modes: " + FolderMode.allCases.map { mode in "\(mode.rawValue)=\(folders.values.filter { $0.mode == mode }.count)" }.joined(separator: ", "))
        lines.append("Queue: pending=\(items.values.filter { $0.status == .pending }.count), review=\(items.values.filter { $0.status == .review }.count)")
        lines.append("History entries: \(history.operationCount)")
        lines.append("Planned entries: \((try? history.plannedEntries().count) ?? -1)")
        lines.append("Model availability: \(deps.availability().rawValue)")
        lines.append("Basic naming only: \(settings.basicNamingOnly)")
        lines.append("Image input: \(settings.imageInput)")
        lines.append("Stability wait: \(settings.stabilityWait) s, PDF pages: \(settings.pdfPages)")
        lines.append("Retention: \(settings.historyRetentionDays.map { "\($0) days" } ?? "forever")")
        lines.append("Pause: \(pause.option?.rawValue ?? "none")")
        lines.append("Power: low power \(deps.power.conditions().lowPowerMode), thermal \(deps.power.conditions().thermal.rawValue), battery \(deps.power.conditions().onBattery)")
        lines.append("Rules: \(((try? deps.config.rules()) ?? []).count), rule warnings: \(ruleWarnings.count)")
        lines.append("Styles: \(((try? deps.config.styles()) ?? []).count)")
        return lines.joined(separator: "\n")
    }
}

public enum FolderError: Error, Sendable, Hashable {
    case unsupportedVolume(String)
    case projectFolder([String])

    public var explanation: String {
        switch self {
        case .unsupportedVolume(let reason): reason
        case .projectFolder(let markers):
            "This folder looks like a code project (it contains \(markers.joined(separator: ", "))). Renaming files in it can break the project. Watch it anyway?"
        }
    }
}
