#if canImport(AppKit) && canImport(SwiftUI) && canImport(FoundationModels) && canImport(Vision)
import AppKit
import Observation
import SwiftUI
import UntitledCore
import UntitledEngine
import UntitledExtract
import UntitledFS
import UntitledModel
import UntitledShared
import UntitledStore

/// The app's composition root: builds the engine with the Apple implementations, owns the status
/// item, panels and windows, and routes Finder, notification and Shortcuts requests.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    public static let shared = AppController()

    public private(set) var model: AppModel?
    let router = AppRouter()
    private let notifier = NotificationPresenter()
    private let power = PowerMonitor()
    private var thumbnails: ThumbnailLoader?
    private var statusItem: StatusItemController?
    private var windows: WindowManager?
    private var menuPanel: GlassPanel?
    private var quickPanel: GlassPanel?
    private var activationObserver: WorkspaceActivationObserver?
    private var pendingURLs: [URL] = []
    private var historyRecovered = false

    /// The app group shared with the Finder extension ($(TeamIdentifierPrefix)com.yourcompany.Untitled).
    var groupContainer: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "UntitledAppGroup") as? String else { return nil }
        return SharedHandoff.containerURL(groupIdentifier: group)
    }

    // MARK: Launch

    public func applicationWillFinishLaunching(_ notification: Notification) {
        if SystemServices.handOffToRunningCopy() {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make(target: self)
        notifier.activate { [weak self] action in
            Task { @MainActor in await self?.handle(action) }
        }
        DistributedNotificationCenter.default().addObserver(forName: SystemServices.showMainWindowNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windows?.showMain(section: nil) }
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try build()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Untitled couldn't open its data."
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        guard let model else { return }
        Task {
            await model.load()
            if historyRecovered {
                model.post("Untitled's history was damaged, so it was set aside and a new one was started. Your folders and settings are intact.")
            }
            publishGrantedFolders()
            if !model.onboarding.isComplete { showOnboarding() }
            let urls = pendingURLs
            pendingURLs = []
            for url in urls { await open(url) }
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windows?.showMain(section: nil) }
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        guard let engine = model?.engine else { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await engine.stop()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func build() throws {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Untitled", isDirectory: true)
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Thumbnails", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let config = try ConfigDatabase(url: support.appendingPathComponent("config.sqlite"))
        let (history, recovered) = try HistoryDatabase.openRecovering(url: support.appendingPathComponent("history.sqlite"))
        historyRecovered = recovered
        let timeline = AppTimeline()
        activationObserver = WorkspaceActivationObserver(timeline: timeline)
        let extractor = Extractor(readers: AppleReaders.all, screenshotDetector: AppleScreenshotDetector(), timeline: timeline,
                                  detectLanguage: AppleLanguageDetector.detect)
        let engine = Engine(Engine.Dependencies(
            config: config, history: history,
            executor: OperationExecutor(journal: history, coordinator: CoordinatedMove(), suppression: OwnOperationSuppression()),
            extractor: extractor, generator: AppleFieldGenerator(), notifier: notifier, power: power,
            bookmarks: SecurityScopedBookmarks(),
            watcherFactory: { folder in FSEventsFolderWatcher(path: folder.path, sinceEventID: nil, onEventID: { _ in }) },
            availability: { AppleFieldGenerator.availability() }
        ))
        let cache = ThumbnailCache(directory: caches)
        let model = AppModel(engine: engine, store: EnginePreferencesStore(engine: engine), thumbnails: cache)
        let thumbnails = ThumbnailLoader(cache: cache)
        self.model = model
        self.thumbnails = thumbnails
        windows = WindowManager(model: model, router: router, thumbnails: thumbnails)
        configureRouter()
        model.onPreferencesChanged = { [weak self] preferences in
            self?.notifier.update(preferences)
            self?.windows?.updateDock(showInDock: preferences.showInDock)
            SystemServices.setLaunchAtLogin(preferences.launchAtLogin)
        }
        model.onSharedStateChanged = { [weak self] in self?.publishGrantedFolders() }
        power.start { Task { await engine.powerChanged() } }

        let status = StatusItemController(model: model)
        status.onClick = { [weak self] in self?.toggleMenuPanel() }
        status.onDrop = { [weak self] urls in self?.showQuickRename(urls) }
        statusItem = status
    }

    /// The sidebar selection is restored at the next launch (O2).
    private func persistSection() {
        withObservationTracking {
            UserDefaults.standard.set(router.section.rawValue, forKey: "mainSection")
        } onChange: { [weak self] in
            Task { @MainActor in self?.persistSection() }
        }
    }

    private func configureRouter() {
        if let saved = UserDefaults.standard.string(forKey: "mainSection").flatMap(MainSection.init(rawValue:)) {
            router.section = saved
        }
        persistSection()
        router.openMainWindow = { [weak self] section in self?.windows?.showMain(section: section) }
        router.openSettings = { [weak self] in self?.windows?.showSettings() }
        router.openQuickRename = { [weak self] urls in self?.showQuickRename(urls) }
        router.showInFinder = { SystemServices.showInFinder($0) }
        router.closePanel = { [weak self] in self?.closeMenuPanel() }
        router.chooseFolder = { start, prompt in await SystemServices.chooseFolder(startingAt: start, prompt: prompt) }
        router.copyToPasteboard = { SystemServices.copy($0) }
        router.openURL = { SystemServices.open($0) }
        router.exportDiagnostics = { SystemServices.exportDiagnostics($0) }
        router.requestNotificationPermission = { [notifier] in await notifier.requestPermission() }
        router.finderExtensionEnabled = { SystemServices.finderExtensionEnabled }
        router.openFinderExtensionSettings = { SystemServices.openFinderExtensionSettings() }
        router.downloadsFolder = { SystemServices.downloadsFolder }
        router.desktopFolder = { SystemServices.desktopFolder }
    }

    /// The Finder extension shows its items only in granted folders (P4), and Restore Original Name
    /// only for renamed files.
    private func publishGrantedFolders() {
        guard let container = groupContainer, let model else { return }
        SharedHandoff.publishGrantedFolders(model.folders.filter { $0.attention == nil }.map(\.path), container: container)
        Task { SharedHandoff.publishRenamedPaths(await model.renamedPaths(), container: container) }
    }

    // MARK: Menu bar panel (N2)

    private func toggleMenuPanel() {
        if menuPanel?.isVisible == true {
            closeMenuPanel()
        } else {
            showMenuPanel()
        }
    }

    private func showMenuPanel() {
        guard let model, let thumbnails, let statusItem, let itemFrame = statusItem.buttonFrame,
              let screen = statusItem.screen ?? NSScreen.main else { return }
        let panel = menuPanel ?? GlassPanel(
            rootView: MenuBarPanelView().environment(model).environment(router).environment(thumbnails),
            acceptsKey: true
        )
        panel.onDismiss = { [weak self] in self?.closeMenuPanel() }
        menuPanel = panel
        let size = panel.fittingContentSize
        let frame = PanelPlacement.menuBarPanel(size: (size.width, size.height), statusItem: ScreenRect(itemFrame),
                                                visibleFrame: ScreenRect(screen.visibleFrame))
        panel.present(at: frame.nsRect)
        publishGrantedFolders()
    }

    private func closeMenuPanel() {
        menuPanel?.dismissPanel()
    }

    // MARK: Quick Rename (M5, M6)

    func showQuickRename(_ urls: [URL]) {
        guard let model, let thumbnails, !urls.isEmpty else { return }
        closeMenuPanel()
        quickPanel?.dismissPanel()
        let quick = QuickRenameModel(paths: urls.map(\.path), app: model, router: router)
        let panel = GlassPanel(
            rootView: QuickRenameView(quick: quick) { [weak self] in self?.quickPanel?.dismissPanel() }
                .environment(model).environment(router).environment(thumbnails),
            acceptsKey: true
        )
        panel.onDismiss = { [weak self] in self?.quickPanel?.dismissPanel() }
        quickPanel = panel
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = panel.fittingContentSize
        let frame = PanelPlacement.quickRename(size: (Metrics.quickRenameWidth, max(size.height, 180)), visibleFrame: ScreenRect(screen.visibleFrame))
        NSApp.activate()
        panel.present(at: frame.nsRect)
    }

    // MARK: Onboarding

    private func showOnboarding() {
        guard let model else { return }
        windows?.showOnboarding(OnboardingModel(app: model, router: router))
    }

    // MARK: untitled:// requests from the Finder extension (P4, P5)

    public func application(_ application: NSApplication, open urls: [URL]) {
        guard model?.loaded == true else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        Task { for url in urls { await open(url) } }
    }

    /// Unknown, forged or stale request IDs do nothing (P5).
    private func open(_ url: URL) async {
        guard let container = groupContainer, let request = SharedHandoff.take(url: url, container: container), let model else { return }
        switch request.action {
        case .rename:
            showQuickRename(request.paths.map { URL(fileURLWithPath: $0) })
        case .restoreOriginalName:
            for path in request.paths { _ = await model.restoreOriginalName(path: path) }
        }
    }

    // MARK: Notification actions (P2)

    private func handle(_ action: NotificationPresenter.Action) async {
        guard let model else { return }
        switch action {
        case .undo(let id): await model.undo(entryID: id)
        case .showInFinder(let id):
            if let entry = await model.entry(id: id) { SystemServices.showInFinder(entry.state == .reverted ? entry.oldPath : entry.newPath) }
        case .undoAll(let ids): await model.undo(entryIDs: ids)
        case .accept(let itemID): _ = await model.accept([itemID], method: .notification)
        case .edit(let itemID, let name):
            _ = await model.accept([itemID], edits: name.isEmpty ? [:] : [itemID: .typed(name)], method: .notification)
        case .skip(let itemID): await model.skip([itemID])
        case .openReview: windows?.showMain(section: .review)
        }
    }

    // MARK: Menu actions

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: NSAttributedString(string: Licenses.aboutCredits)])
    }

    @objc func showSettings(_ sender: Any?) { windows?.showSettings() }

    @objc func showMainWindow(_ sender: Any?) { windows?.showMain(section: nil) }
}
#endif
