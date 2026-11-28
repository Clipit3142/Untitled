#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledFS

/// A row in Recent: thumbnail, new name, "was …" and time. Hover or focus shows Undo and
/// Show in Finder; the row drags out as the file itself (N3).
struct RecentRow: View {
    var entry: JournalEntry
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var undone: Bool { entry.state == .reverted }

    var body: some View {
        HStack(spacing: Spacing.s) {
            ThumbnailView(path: undone ? entry.oldPath : entry.newPath)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                RenameMomentText(oldName: entry.oldName, newName: entry.newName,
                                 animate: model.now().timeIntervalSince(entry.time) < 3)
                Text(verbatim: undone ? "Undone" : RowText.was(entry.oldName))
                    .appText(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Spacing.xs)
            if hovering || focused {
                HStack(spacing: Spacing.xs) {
                    if !undone {
                        Button("Undo", systemImage: "arrow.uturn.backward") { Task { await model.undo(entryID: entry.id ?? -1) } }
                    }
                    Button("Show in Finder", systemImage: "folder") { router.showInFinder(undone ? entry.oldPath : entry.newPath) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            } else {
                Text(verbatim: RowText.clock(entry.time, calendar: model.calendar))
                    .appText(.time).foregroundStyle(.secondary)
            }
        }
        .padding(EdgeInsets.row)
        .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: Radius.s))
        .contentShape(.rect)
        .focusable()
        .focused($focused)
        .onHover { hovering = $0 }
        .onDrag {
            let url = URL(fileURLWithPath: undone ? entry.oldPath : entry.newPath)
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RowText.renamedLabel(oldName: entry.oldName, newName: entry.newName, time: entry.time,
                                                 now: model.now(), calendar: model.calendar, undone: undone))
        .accessibilityAction(named: "Undo") { Task { await model.undo(entryID: entry.id ?? -1) } }
        .accessibilityAction(named: "Show in Finder") { router.showInFinder(undone ? entry.oldPath : entry.newPath) }
    }
}
#endif
