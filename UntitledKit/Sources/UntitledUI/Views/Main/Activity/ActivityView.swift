#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledFS
import UntitledStore

/// Activity (3.15): history grouped by day, searchable by old or new name.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var entries: [JournalEntry] = []
    @State private var notes: [ActivityNote] = []

    var body: some View {
        List {
            ForEach(ActivityGrouping.byDay(entries, time: \.time, now: model.now(), calendar: model.calendar)) { group in
                Section(group.title) {
                    ForEach(group.items) { entry in
                        ActivityRow(entry: entry)
                    }
                }
            }
            if !notes.isEmpty && search.isEmpty {
                Section("Notes") {
                    ForEach(notes) { note in
                        HStack {
                            Label(note.message, systemImage: "info.circle")
                            Spacer()
                            Text(verbatim: RowText.relative(note.time, now: model.now(), calendar: model.calendar))
                                .appText(.time).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if entries.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("No Activity Yet", systemImage: "clock",
                                           description: Text("Files Untitled renames appear here, with Undo."))
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        .navigationTitle("Activity")
        .searchable(text: $search, prompt: "Search old or new names")
        .task(id: search) { await reload() }
        .onChange(of: model.recent) { Task { await reload() } }
    }

    private func reload() async {
        entries = await model.activity(search: search)
        notes = await model.notes()
    }
}

private struct ActivityRow: View {
    var entry: JournalEntry
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    private var undone: Bool { entry.state == .reverted }

    var body: some View {
        HStack(spacing: Spacing.m) {
            ThumbnailView(path: undone ? entry.oldPath : entry.newPath)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                FileNameText(name: entry.newName)
                    .strikethrough(undone)
                FileNameText(name: undone ? "Undone, back to \(entry.oldName)" : RowText.was(entry.oldName), style: .caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: RowText.clock(entry.time, calendar: model.calendar)).appText(.time).foregroundStyle(.secondary)
            if !undone {
                Button("Undo", systemImage: "arrow.uturn.backward") { Task { await model.undo(entryID: entry.id ?? -1) } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            Button("Show in Finder", systemImage: "folder") { router.showInFinder(undone ? entry.oldPath : entry.newPath) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .contextMenu {
            if !undone { Button("Undo") { Task { await model.undo(entryID: entry.id ?? -1) } } }
            Button("Show in Finder") { router.showInFinder(undone ? entry.oldPath : entry.newPath) }
            Button("Copy Name") { router.copyToPasteboard(undone ? entry.oldName : entry.newName) }
            Divider()
            Button("Never Rename Again") { Task { await model.neverRenameAgain(entryID: entry.id ?? -1) } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(RowText.renamedLabel(oldName: entry.oldName, newName: entry.newName, time: entry.time,
                                                 now: model.now(), calendar: model.calendar, undone: undone))
        .accessibilityAction(named: "Copy Name") { router.copyToPasteboard(entry.newName) }
        .accessibilityAction(named: "Never Rename Again") { Task { await model.neverRenameAgain(entryID: entry.id ?? -1) } }
    }
}
#endif
