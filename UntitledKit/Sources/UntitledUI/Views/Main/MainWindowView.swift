#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledFS

/// The main window: a standard sidebar split view (3.15). Minimum 880 × 580.
struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @Bindable var router: AppRouter

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: Binding(get: { Optional(router.section) }, set: { router.section = $0 ?? .review })) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(section == .review ? model.reviewCount : 0)
                    .tag(section)
                    .accessibilityIdentifier("sidebar.\(section.rawValue)")
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } detail: {
            detail
                .overlay(alignment: .bottom) {
                    NoticeStack().padding(Spacing.l).frame(maxWidth: 520)
                }
        }
        .toolbar {
            // ⌘Z in the main window undoes the last operation (3.14).
            ToolbarItem(placement: .navigation) {
                Button("Undo Last Rename", systemImage: "arrow.uturn.backward") { Task { await model.undoLast() } }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(model.recent.allSatisfy { $0.state != .done })
            }
        }
        .frame(minWidth: Metrics.mainWindowMinWidth, minHeight: Metrics.mainWindowMinHeight)
    }

    @ViewBuilder
    private var detail: some View {
        switch router.section {
        case .review: ReviewView()
        case .activity: ActivityView()
        case .folders: FoldersView()
        case .styles: StylesView()
        case .rules: RulesView()
        }
    }
}
#endif
