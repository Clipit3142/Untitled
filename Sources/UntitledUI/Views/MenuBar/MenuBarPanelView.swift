#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UniformTypeIdentifiers
import UntitledCore

/// The menu bar panel's content (3.15). It sits on the panel's glass; nothing inside is glass (3.16).
struct MenuBarPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            PanelHeader()
            if model.reviewCount > 0 { ReviewButton() }
            if let folderID = model.automaticOffers.first, let folder = model.folder(id: folderID) {
                AutomaticOfferCard(folder: folder)
            }
            if let suggestion = model.suggestions.first { SuggestionCard(suggestion: suggestion) }
            RecentSection()
            NoticeStack()
            Divider()
            PanelFooter()
        }
        .padding(Spacing.l)
        .frame(width: Metrics.menuBarPanelWidth)
        .overlay {
            if dropTargeted { DropZone().transition(.opacity) }
        }
        .animation(MotionReader(reduceMotion: reduceMotion).animation(Motion.standard), value: dropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            Task { router.openQuickRename(await FileDrop.urls(from: providers)) }
            return true
        }
        .onExitCommand { router.closePanel() }
    }
}

private struct PanelHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Spacing.s) {
            StatusPill(text: model.statusText, symbol: model.glyphState.pillSymbol)
            Spacer(minLength: Spacing.s)
            if model.pauseState.option != nil {
                Button("Resume", systemImage: "play.fill") { Task { await model.resume() } }
                    .accessibilityIdentifier("resume")
            } else {
                Menu {
                    Button("For 1 Hour") { Task { await model.pause(.oneHour) } }
                    Button("Until Tomorrow") { Task { await model.pause(.untilTomorrow) } }
                    Button("Indefinitely") { Task { await model.pause(.indefinitely) } }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .menuStyle(.button)
                .fixedSize()
                .accessibilityIdentifier("pauseMenu")
            }
        }
    }
}

private struct ReviewButton: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.show(.review)
            router.closePanel()
        } label: {
            HStack {
                Label("Needs Review", systemImage: "tray.full")
                Spacer()
                Text(model.reviewCount, format: .number)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, Spacing.s)
                    .background(.quaternary, in: .capsule)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Needs review, \(model.reviewCount) files")
        .accessibilityIdentifier("needsReview")
    }
}

private struct RecentSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Recent").appText(.caption).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if model.recent.isEmpty {
                Text("Renamed files appear here.").appText(.secondary).foregroundStyle(.secondary)
                    .padding(.vertical, Spacing.s)
            } else {
                ForEach(model.recent) { entry in
                    RecentRow(entry: entry)
                        .transition(MotionReader(reduceMotion: reduceMotion).transition(.move(edge: .top).combined(with: .opacity)))
                }
            }
        }
        .animation(MotionReader(reduceMotion: reduceMotion).animation(Motion.rowInsert), value: model.recent.map(\.id))
    }
}

private struct PanelFooter: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack {
            Button("Open Untitled") {
                router.openMainWindow(nil)
                router.closePanel()
            }
            .keyboardShortcut("o")
            Spacer()
            Button("Settings…") {
                router.openSettings()
                router.closePanel()
            }
            .keyboardShortcut(",")
        }
    }
}

private struct DropZone: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.m)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .foregroundStyle(.tint)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9), in: .rect(cornerRadius: Radius.m))
            .overlay {
                Label("Drop to rename with Untitled", systemImage: "square.and.arrow.down")
                    .appText(.headline)
            }
            .padding(Spacing.s)
            .accessibilityLabel("Drop files to rename them")
    }
}
#endif
