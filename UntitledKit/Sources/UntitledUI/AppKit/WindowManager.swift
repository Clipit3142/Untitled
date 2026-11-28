#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

/// Owns the main, Settings and onboarding windows, and the Dock presence that follows them (O1).
/// Window frames are saved by name, so size and position are restored (O2).
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let router: AppRouter
    private let thumbnails: ThumbnailLoader
    private var main: NSWindow?
    private var settings: NSWindow?
    private var onboarding: NSWindow?
    private var dock = DockPolicy(showInDock: false)
    private var dockTask: Task<Void, Never>?

    init(model: AppModel, router: AppRouter, thumbnails: ThumbnailLoader) {
        self.model = model
        self.router = router
        self.thumbnails = thumbnails
    }

    private func environment<Content: View>(_ view: Content) -> some View {
        view.environment(model).environment(router).environment(thumbnails)
    }

    func showMain(section: MainSection?) {
        if let section { router.section = section }
        let window = main ?? makeWindow(
            title: "Untitled", autosave: "UntitledMainWindow",
            content: environment(MainWindowView(router: router)),
            style: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            minSize: NSSize(width: Metrics.mainWindowMinWidth, height: Metrics.mainWindowMinHeight)
        )
        main = window
        present(window)
    }

    func showSettings() {
        let window = settings ?? makeWindow(
            title: "Untitled Settings", autosave: "UntitledSettingsWindow",
            content: environment(SettingsView()),
            style: [.titled, .closable, .fullSizeContentView], minSize: NSSize(width: 520, height: 300)
        )
        settings = window
        present(window)
    }

    func showOnboarding(_ onboardingModel: OnboardingModel) {
        let window = onboarding ?? makeWindow(
            title: "Welcome to Untitled", autosave: "UntitledOnboardingWindow",
            content: environment(OnboardingView(onboarding: onboardingModel) { [weak self] in self?.onboarding?.close() }),
            style: [.titled, .closable, .fullSizeContentView], minSize: NSSize(width: 600, height: 520)
        )
        onboarding = window
        present(window)
    }

    func updateDock(showInDock: Bool) {
        dock.showInDock = showInDock
        applyDock()
    }

    private func makeWindow<Content: View>(title: String, autosave: String, content: Content, style: NSWindow.StyleMask,
                                           minSize: NSSize) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = style
        window.minSize = minSize
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.delegate = self
        if !window.setFrameUsingName(autosave) { window.center() }
        window.setFrameAutosaveName(autosave)
        return window
    }

    private func present(_ window: NSWindow) {
        dock.openWindows = [main, settings, onboarding].compactMap { $0 }.filter { $0.isVisible || $0 === window }.count
        applyDock()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        dock.openWindows = [main, settings, onboarding].compactMap { $0 }.filter { $0.isVisible && $0 !== closing }.count
        applyDock()
    }

    /// Leaves the Dock within 1 s after the last window closes, unless Show in Dock is on (O1).
    private func applyDock() {
        let target = dock.presence
        let current: DockPolicy.Presence = NSApp.activationPolicy() == .regular ? .regular : .accessory
        dockTask?.cancel()
        guard target != current else { return }
        let delay = dock.delay(from: current)
        dockTask = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            NSApp.setActivationPolicy(target == .regular ? .regular : .accessory)
        }
    }
}
#endif
