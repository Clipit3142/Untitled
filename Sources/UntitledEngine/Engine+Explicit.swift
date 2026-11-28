import Foundation
public import UntitledCore
public import UntitledFS
import UntitledStore
import UntitledModel

/// A Quick Rename proposal for one file (3.15).
public struct ExplicitProposal: Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var currentName: String
    public var proposal: Proposal
    /// The editable base name, selected in the field; the extension is shown separately.
    public var baseName: String
    public var fileExtension: String?
    /// "Move to …" checkbox, on by default when a rule matches.
    public var destinationName: String?
}

public enum ExplicitError: Error, Sendable, Hashable {
    case outsideGrantedFolders(folder: String)
    case selectionSize(Int)
    case notRenamable(String)
    case missing

    public var explanation: String {
        switch self {
        case .outsideGrantedFolders: "Untitled can only rename files in folders you've given it access to."
        case .selectionSize(let count): "Select between 1 and 50 files (you selected \(count))."
        case .notRenamable(let reason): reason
        case .missing: "The file is no longer there."
        }
    }
}

extension Engine {
    func grantedFolder(containing path: String) -> GrantedFolder? {
        folders.values.filter { $0.attention == nil && FileSystem.isInside(path, root: $0.path) }
            .max { $0.path.count < $1.path.count }
    }

    /// Proposals for explicitly chosen files (Quick Rename, Shortcuts). Regenerate uses random sampling (3.8).
    /// `readOnly` allows files outside granted folders, for the "Copy name" fallback when the user
    /// declines access (M6): those proposals can be read, never applied.
    public func explicitProposals(paths: [String], regenerate: Bool = false, readOnly: Bool = false) async throws(ExplicitError) -> [ExplicitProposal] {
        guard Defaults.quickRenameSelection.contains(paths.count) else { throw .selectionSize(paths.count) }
        var results: [ExplicitProposal] = []
        for path in paths {
            let granted = grantedFolder(containing: path)
            guard granted != nil || readOnly else { throw .outsideGrantedFolders(folder: FileSystem.parent(path)) }
            let folder = granted ?? GrantedFolder(id: "", path: FileSystem.parent(path), role: .accessOnly,
                                                  styleID: defaultStyleID(), watchStart: deps.now())
            guard let read = FileFactsReader.read(path: path, isTopLevel: FileSystem.parent(path) == folder.path) else { throw .missing }
            let decision = Eligibility.evaluate(read.facts, folder: nil, request: .explicit, paused: false)
            var metadataOnly: MetadataOnlyReason?
            switch decision {
            case .skip(let reason): throw .notRenamable(Self.explain(reason))
            case .metadataOnly(let reason): metadataOnly = reason
            case .process: break
            }
            let style = (try? style(for: folder)) ?? Presets.clean
            let (proposal, _) = await makeProposal(path: path, facts: read.facts, metadataOnly: metadataOnly, style: style,
                                                   sampling: regenerate ? .random(seed: nil) : .greedy, priority: .userInitiated)
            let split = FileExtension.split(proposal.fileName)
            let destination = proposal.destinationID.flatMap { id in builder(style: style).destinations.first { $0.id == id } }
                .flatMap { folders[$0.folderID]?.displayName }
            results.append(ExplicitProposal(path: path, currentName: read.facts.name, proposal: proposal, baseName: split.base,
                                            fileExtension: FileExtension.split(read.facts.name).extension, destinationName: destination))
        }
        return results
    }

    /// Applies a Quick Rename: the proposal, or the name the user typed (sanitized only, H9).
    public func applyExplicit(_ proposal: ExplicitProposal, typedBase: String?, move: Bool, method: OperationMethod = .quickRename) async throws(ExplicitError) -> String {
        guard let folder = grantedFolder(containing: proposal.path) else { throw .outsideGrantedFolders(folder: FileSystem.parent(proposal.path)) }
        guard let status = FileSystem.status(atPath: proposal.path) else { throw .missing }
        let item = QueueItem(arrival: 0, folderID: folder.id, directory: FileSystem.parent(proposal.path),
                             expected: ExpectedFile(status: status, name: proposal.currentName), dateAdded: nil, status: .review,
                             proposal: proposal.proposal, request: .explicit, createdAt: deps.now())
        items[item.id] = item
        var finalName: String?
        var edited = false
        if let typedBase, typedBase != proposal.baseName {
            let style = (try? style(for: folder)) ?? Presets.clean
            guard let prepared = try? TypedName.prepare(typedBase, fileExtension: proposal.fileExtension, extensionCase: style.extensionCase) else {
                items.removeValue(forKey: item.id)
                throw .notRenamable("Type a name.")
            }
            finalName = prepared.fileName
            edited = true
        }
        guard let entryID = await execute(itemID: item.id, method: method, finalName: finalName, moveEnabled: move, batchID: nil, edited: edited),
              let entry = try? deps.history.entry(entryID) else {
            items.removeValue(forKey: item.id)
            throw .notRenamable("The file couldn't be renamed.")
        }
        if edited { learn(proposed: proposal.proposal, proposedName: proposal.proposal.fileName, final: entry.newName, folderID: folder.id) }
        if let style = try? style(for: folder) {
            var examples = (try? deps.config.examples(styleID: style.id)) ?? ExampleList()
            examples.add(entry.newName)
            try? deps.config.saveExamples(examples, styleID: style.id)
        }
        return entry.newPath
    }

    /// Shortcuts "Suggest Name": text only, nothing changes on disk (3.15).
    public func suggestName(path: String) async throws(ExplicitError) -> String {
        guard let proposal = try await explicitProposals(paths: [path]).first else { throw .missing }
        return proposal.proposal.fileName
    }

    /// Shortcuts "Rename File".
    public func renameFile(path: String) async throws(ExplicitError) -> String {
        guard let proposal = try await explicitProposals(paths: [path]).first else { throw .missing }
        return try await applyExplicit(proposal, typedBase: nil, move: true, method: .shortcut)
    }

    /// "Rename existing files…" and the Shortcuts action: proposals go to Review (3.15).
    @discardableResult
    public func renameExisting(folderID: String) throws(ExplicitError) -> Int {
        guard let folder = folders[folderID] else { throw .missing }
        var count = 0
        let names = ((try? FileSystem.entries(ofDirectory: folder.path)) ?? []).sorted()
        for name in names {
            let path = FileSystem.join(folder.path, name)
            guard let read = FileFactsReader.read(path: path, isTopLevel: true,
                                                   ignored: { identity in (try? self.deps.config.isIgnored(identity: identity)) ?? false }),
                  !read.facts.hasMarker, !read.facts.onIgnoreList else { continue }
            guard case .process = Eligibility.evaluate(read.facts, folder: nil, request: .explicit, paused: false),
                  !items.values.contains(where: { $0.expected.identity == read.status.identity }),
                  !stabilizing.contains(read.status.identity) else { continue }
            let arrival = (try? deps.history.nextArrival()) ?? Int64(items.count + 1)
            let item = QueueItem(arrival: arrival, folderID: folderID, directory: folder.path,
                                 expected: ExpectedFile(status: read.status, name: name), dateAdded: read.facts.dateAdded,
                                 status: .pending, request: .explicit, createdAt: deps.now())
            items[item.id] = item
            try? deps.history.save(item)
            count += 1
        }
        emit(.queueChanged)
        wakeWorker()
        return count
    }

    /// The style for files outside any watched folder: the first watched folder's, or Clean.
    func defaultStyleID() -> String {
        folders.values.filter { $0.role == .watched }.sorted { $0.displayName < $1.displayName }.first?.styleID ?? Presets.clean.id
    }

    static func explain(_ reason: SkipReason) -> String {
        switch reason {
        case .symlink, .alias: "Untitled doesn't rename aliases or symbolic links."
        case .package, .directory, .notRegularFile: "Untitled only renames files, not folders or packages."
        case .hidden, .systemFile: "Untitled doesn't rename hidden or system files."
        case .inProgress: "This file is still being downloaded or written."
        case .locked: "This file is locked."
        case .notWritable: "Untitled can't write in this folder."
        default: "Untitled can't rename this file."
        }
    }
}
