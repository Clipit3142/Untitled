public import Foundation
public import Observation
public import UntitledCore
public import UntitledEngine
public import UntitledStore
import UntitledFS

/// Quick Rename (3.15, M5, M6): proposals for chosen files, editable base names, Return applies,
/// Esc changes nothing, ⌘R regenerates.
@MainActor
@Observable
public final class QuickRenameModel {
    public enum Phase: Sendable, Hashable {
        case loading
        case ready
        /// Some files are outside the granted folders: ask for this folder first.
        case needsAccess(folder: String)
        /// Access was declined: names can only be copied (M6).
        case copyOnly
        case failed(String)
        case finished
    }

    public struct Entry: Sendable, Identifiable {
        public var id: String { path }
        public var path: String
        public var proposal: ExplicitProposal?
        /// The editable base name; starts as the proposal's base name.
        public var baseName = ""
        public var moveEnabled = true
        public var error: String?
        public var renamedPath: String?

        public var currentName: String { FileSystem.name(path) }
        public var fileExtension: String? { proposal?.fileExtension }
        public var isEdited: Bool { proposal.map { $0.baseName != baseName } ?? false }
    }

    public let paths: [String]
    @ObservationIgnored let app: AppModel
    @ObservationIgnored let router: AppRouter
    public private(set) var entries: [Entry]
    public private(set) var phase: Phase = .loading
    /// Folders the user declined to grant during this Quick Rename.
    @ObservationIgnored var declined: Set<String> = []

    public init(paths: [String], app: AppModel, router: AppRouter) {
        self.paths = paths
        self.app = app
        self.router = router
        entries = paths.map { Entry(path: $0) }
    }

    /// The first folder holding a selected file that Untitled can't write in.
    public var ungrantedFolder: String? {
        paths.map(FileSystem.parent).first { folder in !app.isGranted(path: FileSystem.join(folder, "x")) }
    }

    // MARK: Loading

    public func load(regenerate: Bool = false) async {
        guard Defaults.quickRenameSelection.contains(paths.count) else {
            phase = .failed(ExplicitError.selectionSize(paths.count).explanation)
            return
        }
        if let folder = ungrantedFolder, !declined.contains(folder) {
            phase = .needsAccess(folder: folder)
            return
        }
        phase = .loading
        let readOnly = ungrantedFolder != nil
        do {
            let proposals = try await app.explicitProposals(paths: paths, regenerate: regenerate, readOnly: readOnly)
            for proposal in proposals {
                guard let index = entries.firstIndex(where: { $0.path == proposal.path }) else { continue }
                entries[index].proposal = proposal
                entries[index].baseName = proposal.baseName
                entries[index].moveEnabled = proposal.destinationName != nil
                entries[index].error = nil
            }
            phase = readOnly ? .copyOnly : .ready
        } catch {
            phase = .failed(error.explanation)
        }
    }

    /// Asks for the folder in the system picker, opened on that folder (M6). A different folder
    /// is added too, and the notice says so (B3).
    public func requestAccess() async {
        guard case .needsAccess(let folder) = phase else { return }
        let choice = await router.chooseFolder(URL(fileURLWithPath: folder, isDirectory: true),
                                               "Allow Untitled to rename files in this folder")
        guard let choice else {
            declined.insert(folder)
            await load()
            return
        }
        let chosen = choice.url.path
        let grant = GrantedFolderFactory.accessOnly(path: chosen, bookmark: choice.bookmark, now: app.now())
        do {
            try await app.addFolder(grant)
        } catch {
            app.post(error.explanation)
        }
        if chosen != folder {
            app.post("You chose “\(FileSystem.name(chosen))”, so Untitled can rename files there. Files in “\(FileSystem.name(folder))” still need access.")
            declined.insert(folder)
        }
        await load()
    }

    // MARK: Editing

    public func setBaseName(_ name: String, for path: String) {
        guard let index = entries.firstIndex(where: { $0.path == path }) else { return }
        entries[index].baseName = name
    }

    public func setMove(_ enabled: Bool, for path: String) {
        guard let index = entries.firstIndex(where: { $0.path == path }) else { return }
        entries[index].moveEnabled = enabled
    }

    /// What a typed name becomes once sanitized; shown before saving when it differs (H9).
    public func typedNotice(for path: String) -> String? {
        guard let entry = entries.first(where: { $0.path == path }), entry.isEdited else { return nil }
        guard let result = try? TypedName.prepare(entry.baseName, fileExtension: entry.fileExtension, extensionCase: .keep) else {
            return "Type a name."
        }
        return result.changed ? "Will be saved as “\(result.fileName)”." : nil
    }

    // MARK: Actions

    /// Return: applies every proposal, or the typed names as typed (sanitized only).
    @discardableResult
    public func apply() async -> Bool {
        guard phase == .ready else { return false }
        var allDone = true
        for index in entries.indices where entries[index].renamedPath == nil {
            guard let proposal = entries[index].proposal else { continue }
            let typed = entries[index].isEdited ? entries[index].baseName : nil
            do {
                entries[index].renamedPath = try await app.applyExplicit(proposal, typedBase: typed, move: entries[index].moveEnabled)
                entries[index].error = nil
            } catch {
                entries[index].error = error.explanation
                allDone = false
            }
        }
        if allDone { phase = .finished }
        return allDone
    }

    /// ⌘R: new proposals with random sampling (3.8). Typed edits are replaced.
    public func regenerate() async {
        guard phase == .ready || phase == .copyOnly else { return }
        await load(regenerate: true)
    }

    /// The names to copy when access was declined (M6): one per line.
    public var namesToCopy: String {
        entries.compactMap { entry in
            entry.proposal.map { $0.baseName + ($0.fileExtension.map { "." + $0 } ?? "") }
        }.joined(separator: "\n")
    }

    public func copyNames() {
        router.copyToPasteboard(namesToCopy)
    }
}

/// Builds granted folders for the picker flows.
public enum GrantedFolderFactory {
    public static func accessOnly(path: String, bookmark: Data?, now: Date) -> GrantedFolder {
        GrantedFolder(path: path, bookmark: bookmark, role: .accessOnly, mode: .off, watchStart: now)
    }

    public static func watched(path: String, bookmark: Data?, mode: FolderMode, styleID: String, now: Date, isDownloads: Bool = false) -> GrantedFolder {
        GrantedFolder(id: isDownloads ? "downloads" : UUID().uuidString, path: path, bookmark: bookmark, role: .watched, mode: mode,
                      styleID: styleID, watchStart: now, isDownloads: isDownloads)
    }
}
