#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledCore
import UntitledFS
import UntitledStore

/// Folders (3.15): granted folders grouped by role.
struct FoldersView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var projectConfirmation: GrantedFolder?

    var body: some View {
        Form {
            ForEach(FolderRole.allCases, id: \.self) { role in
                let folders = model.folders(role: role)
                if !folders.isEmpty {
                    Section(role.title) {
                        ForEach(folders) { folder in
                            FolderRow(folder: folder)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Folders")
        .toolbar {
            Menu("Add Folder", systemImage: "plus") {
                Button("Watch a Folder…") { Task { await add(role: .watched) } }
                Button("Add a Destination…") { Task { await add(role: .destination) } }
            }
        }
        .alert("Watch This Folder?", isPresented: Binding(get: { projectConfirmation != nil }, set: { if !$0 { projectConfirmation = nil } }),
               presenting: projectConfirmation) { folder in
            Button("Watch Anyway") { Task { try? await model.addFolder(folder, confirmedProject: true) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This folder looks like a code project. Renaming files in it can break the project.")
        }
    }

    private func add(role: FolderRole) async {
        guard let choice = await router.chooseFolder(nil, role == .watched ? "Watch" : "Add") else { return }
        let folder = role == .watched
            ? GrantedFolderFactory.watched(path: choice.url.path, bookmark: choice.bookmark, mode: .review, styleID: Presets.clean.id, now: model.now())
            : GrantedFolder(path: choice.url.path, bookmark: choice.bookmark, role: .destination, mode: .off, watchStart: model.now())
        do {
            try await model.addFolder(folder)
        } catch {
            if case .projectFolder = error { projectConfirmation = folder } else { model.post(error.explanation) }
        }
    }
}

extension FolderRole {
    var title: String {
        switch self {
        case .watched: "Watched"
        case .destination: "Destinations"
        case .accessOnly: "Access Only"
        }
    }
}

extension FolderMode {
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .review: "Review"
        case .off: "Off"
        }
    }
}

private struct FolderRow: View {
    var folder: GrantedFolder
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var weekly = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Label(folder.displayName, systemImage: folder.isDownloads ? "arrow.down.circle" : "folder")
                    .appText(.headline)
                if let attention = folder.attention {
                    Label(attention == .disconnected ? "Disconnected" : "Needs Attention", systemImage: "exclamationmark.triangle")
                        .appText(.caption)
                }
                Spacer()
                if folder.role == .watched {
                    Text("\(weekly) this week").appText(.time).foregroundStyle(.secondary)
                }
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Show in Finder") { router.showInFinder(folder.path) }
                    if folder.role == .watched {
                        Button("Rename Existing Files…") { Task { _ = await model.renameExisting(folderID: folder.id) } }
                    }
                    if folder.attention == .needsReconnect { Button("Reconnect…") { Task { await reconnect() } } }
                    Divider()
                    Button("Remove", role: .destructive) { Task { await model.removeFolder(id: folder.id) } }
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if folder.attention == .needsReconnect {
                Button("Reconnect…") { Task { await reconnect() } }
            }
            if folder.role == .watched {
                Picker(selection: binding(\.mode)) {
                    ForEach(FolderMode.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    SettingLabel(.folderMode)
                }
                Picker(selection: binding(\.styleID)) {
                    ForEach(model.styles) { Text($0.name).tag($0.id) }
                } label: {
                    SettingLabel(.folderStyle)
                }
                Toggle(isOn: binding(\.onlyGenericNames)) { SettingLabel(.onlyGenericNames) }
                if model.automaticOffers.contains(folder.id) { AutomaticOfferCard(folder: folder) }
            }
        }
        .padding(.vertical, Spacing.xs)
        .task(id: model.recent) { weekly = await model.weeklyCount(folderID: folder.id) }
    }

    private func binding<Value: Equatable & Sendable>(_ keyPath: WritableKeyPath<GrantedFolder, Value> & Sendable) -> Binding<Value> {
        Binding(get: { folder[keyPath: keyPath] }, set: { value in
            var copy = folder
            copy[keyPath: keyPath] = value
            Task { await model.updateFolder(copy) }
        })
    }

    private func reconnect() async {
        guard let choice = await router.chooseFolder(URL(fileURLWithPath: FileSystem.parent(folder.path), isDirectory: true),
                                                     "Reconnect “\(folder.displayName)”") else { return }
        var copy = folder
        copy.path = choice.url.path
        copy.bookmark = choice.bookmark
        copy.attention = nil
        await model.updateFolder(copy)
    }
}

/// A setting's title with its one-line explanation (O4).
struct SettingLabel: View {
    var descriptor: SettingDescriptor

    init(_ key: SettingKey) { descriptor = SettingsCatalog.descriptor(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(descriptor.title)
            Text(descriptor.explanation).appText(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
