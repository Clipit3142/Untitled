public import Foundation
public import Observation
public import UntitledCore
import UntitledStore
import UntitledFS

/// The decisions made during onboarding (3.15): folders, style and mode. They are applied to
/// the engine as each step completes, so quitting keeps them (B7).
@MainActor
@Observable
public final class OnboardingModel {
    @ObservationIgnored let app: AppModel
    @ObservationIgnored let router: AppRouter
    public var styleID = Presets.clean.id
    public var mode = FolderMode.review
    public var notificationsAllowed: Bool?
    public var finderExtensionEnabled = false
    public private(set) var demoStarted: Date?
    public private(set) var demoRenamed: String?
    @ObservationIgnored var demoBaseline: Set<Int64> = []

    public init(app: AppModel, router: AppRouter) {
        self.app = app
        self.router = router
    }

    public var step: OnboardingFlow.Step { app.onboarding.step }

    public func next() async {
        if step == .mode { await applyStyleAndMode() }
        await app.updateOnboarding { $0.next() }
        if step == .demo { startDemo() }
    }

    public func back() async { await app.updateOnboarding { $0.back() } }

    public func skip() async { await app.updateOnboarding { $0.skip() } }

    public func finish() async { await app.updateOnboarding { $0.finish() } }

    // MARK: Step 3: folders

    public var desktopAdded: Bool { app.folders.contains { $0.role == .watched && !$0.isDownloads && $0.path == router.desktopFolder()?.path } }
    public var downloadsAdded: Bool { app.folders.contains { $0.isDownloads } }

    /// Opens the picker on Desktop. Another folder is added instead if picked, and the UI says so (B3).
    public func addDesktop() async {
        let desktop = router.desktopFolder()
        guard let choice = await router.chooseFolder(desktop, "Watch Desktop") else { return }
        await addWatched(choice)
        if let desktop, choice.url.standardizedFileURL.path != desktop.standardizedFileURL.path {
            app.post("You chose “\(choice.url.lastPathComponent)” instead of Desktop, so Untitled will watch that folder.")
        }
    }

    /// Downloads needs no picker: it is granted by entitlement (B4).
    public func addDownloads() async {
        guard !downloadsAdded, let downloads = router.downloadsFolder() else { return }
        let folder = GrantedFolderFactory.watched(path: downloads.path, bookmark: nil, mode: mode, styleID: styleID,
                                                  now: app.now(), isDownloads: true)
        try? await app.addFolder(folder)
    }

    public func addOther() async {
        guard let choice = await router.chooseFolder(nil, "Watch") else { return }
        await addWatched(choice)
    }

    func addWatched(_ choice: FolderChoice) async {
        guard !app.folders.contains(where: { $0.path == choice.url.path }) else { return }
        let folder = GrantedFolderFactory.watched(path: choice.url.path, bookmark: choice.bookmark, mode: mode, styleID: styleID, now: app.now())
        do {
            try await app.addFolder(folder)
        } catch {
            app.post(error.explanation)
        }
    }

    // MARK: Steps 4 and 5

    func applyStyleAndMode() async {
        for var folder in app.watchedFolders {
            folder.styleID = styleID
            folder.mode = mode
            await app.updateFolder(folder)
        }
    }

    // MARK: Step 6

    public func requestNotifications() async {
        notificationsAllowed = await router.requestNotificationPermission()
    }

    public func refreshFinderExtension() {
        finderExtensionEnabled = router.finderExtensionEnabled()
    }

    // MARK: Step 7: the live demo (B6)

    func startDemo() {
        demoStarted = app.now()
        demoBaseline = Set(app.recent.compactMap(\.id))
        demoRenamed = nil
    }

    /// Checks for a screenshot renamed since the demo started.
    public func checkDemo() {
        if demoStarted == nil { startDemo() }
        if let entry = app.recent.first(where: { entry in
            guard let id = entry.id else { return false }
            return !demoBaseline.contains(id) && entry.state == .done
        }) {
            demoRenamed = entry.newName
        }
    }

    public func showsSavedElsewhereTip(now: Date) -> Bool {
        guard let demoStarted else { return false }
        var demo = ScreenshotDemo(started: demoStarted)
        demo.renamedName = demoRenamed
        return demo.showsSavedElsewhereTip(now: now)
    }
}
