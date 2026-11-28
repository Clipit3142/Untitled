#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import QuickLook
import UntitledCore
import UntitledEngine
import UntitledStore

/// Review (3.15): proposals waiting for the user. Keys: ↑↓, Return accept, ⌘⌫ skip, E edit,
/// Space Quick Look, ⌘A, ⌘Return accept selected (M1).
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = Set<String>()
    @State private var bulk: BulkAccept?
    @State private var editRequest = 0
    @State private var quickLookURL: URL?

    var body: some View {
        Group {
            if model.reviewItems.isEmpty {
                ContentUnavailableView("Nothing to Review", systemImage: "checkmark.circle",
                                       description: Text("New names that need your approval appear here."))
            } else {
                list
            }
        }
        .navigationTitle("Review")
        .inspector(isPresented: .constant(true)) {
            ReviewInspector(item: singleSelection, editRequest: editRequest)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Skip", systemImage: "forward") { skip(Array(selection)) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(selection.isEmpty)
                Button("Accept", systemImage: "checkmark") { accept(Array(selection)) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(selection.isEmpty)
            }
        }
        .sheet(item: $bulk) { bulk in BulkAcceptSheet(bulk: bulk) }
        .quickLookPreview($quickLookURL)
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(model.reviewItems) { item in
                ReviewRow(item: item, destination: model.destinationName(item.proposal?.destinationID))
                    .tag(item.id)
                    .transition(MotionReader(reduceMotion: reduceMotion).transition(.move(edge: .top).combined(with: .opacity)))
            }
        }
        .animation(MotionReader(reduceMotion: reduceMotion).animation(Motion.rowInsert), value: model.reviewItems.map(\.id))
        .onKeyPress(.return) {
            accept(Array(selection))
            return .handled
        }
        .onKeyPress(.space) {
            if let item = singleSelection { quickLookURL = URL(fileURLWithPath: item.path) }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "eE")) { _ in
            editRequest += 1
            return .handled
        }
        .overlay(alignment: .bottom) {
            if selection.count > 1 {
                ReviewActionBar(count: selection.count, accept: { accept(Array(selection)) }, skip: { skip(Array(selection)) },
                                changeStyle: { styleID in Task { await model.changeStyle(of: Array(selection), to: styleID) } })
                    .padding(Spacing.l)
                    .transition(MotionReader(reduceMotion: reduceMotion).transition(.move(edge: .bottom).combined(with: .opacity)))
            }
        }
        .animation(MotionReader(reduceMotion: reduceMotion).animation(Motion.actionBar), value: selection.count > 1)
    }

    private var singleSelection: QueueItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return model.reviewItems.first { $0.id == id }
    }

    private func accept(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let ordered = model.reviewItems.map(\.id).filter(ids.contains)
        if ordered.count > 20 {
            bulk = BulkAccept(ids: ordered)
        } else {
            Task {
                _ = await model.accept(ordered)
                selection.subtract(ordered)
            }
        }
    }

    private func skip(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        Task {
            await model.skip(ids)
            selection.subtract(ids)
        }
    }
}

/// A large accept with progress and Cancel; cancelling leaves the remaining files untouched (M4).
struct BulkAccept: Identifiable {
    let id = UUID()
    let ids: [String]
}

private struct BulkAcceptSheet: View {
    var bulk: BulkAccept
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var done = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Renaming \(bulk.ids.count) files…").appText(.headline)
            ProgressView(value: Double(done), total: Double(bulk.ids.count))
            Text("\(done) of \(bulk.ids.count)").appText(.time).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { task?.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 360)
        .task {
            let progress = ProgressRelay()
            let work = Task {
                _ = await model.accept(bulk.ids, progress: { finished, _ in progress.report(finished) })
                progress.finish()
            }
            task = work
            for await value in progress.stream { done = value }
            await work.value
            dismiss()
        }
    }
}

/// Carries progress from the engine back to the main actor.
final class ProgressRelay: Sendable {
    let stream: AsyncStream<Int>
    private let continuation: AsyncStream<Int>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .bufferingNewest(1))
        self.stream = stream
        self.continuation = continuation
    }

    func report(_ value: Int) { continuation.yield(value) }

    func finish() { continuation.finish() }
}
#endif
