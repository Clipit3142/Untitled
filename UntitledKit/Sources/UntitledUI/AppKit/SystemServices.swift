#if canImport(AppKit) && canImport(FinderSync) && canImport(ServiceManagement)
import AppKit
import FinderSync
import ServiceManagement
import UniformTypeIdentifiers
import UntitledFS

/// Thin wrappers over system services the router hands to views.
@MainActor
enum SystemServices {
    /// The system folder picker, opened on a folder (B3, M6), returning a security-scoped bookmark.
    static func chooseFolder(startingAt start: URL?, prompt: String) async -> FolderChoice? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        panel.directoryURL = start
        NSApp.activate()
        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        return FolderChoice(url: url, bookmark: try? SecurityScopedBookmarks().folderBookmark(for: url))
    }

    static func showInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Saves the diagnostics report (names and paths already stripped, W2).
    static func exportDiagnostics(_ report: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Untitled Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? report.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Finder extension (B8)

    static var finderExtensionEnabled: Bool { FIFinderSyncController.isExtensionEnabled }

    static func openFinderExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    // MARK: Login item

    static func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled { try service.register() }
            if !enabled, service.status == .enabled { try service.unregister() }
        } catch {
            // The switch reflects the stored preference; System Settings shows the real state.
        }
    }

    // MARK: Folders granted by entitlement

    /// The user's real Downloads folder (granted by `files.downloads.read-write`, B4).
    static var downloadsFolder: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath()
    }

    /// The user's Desktop, where the picker opens (B3). Inside the sandbox the home directory is
    /// the container, so the real home comes from the account record.
    static var desktopFolder: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true).appendingPathComponent("Desktop", isDirectory: true)
    }

    // MARK: Single instance (A7)

    static let showMainWindowNotification = Notification.Name("com.yourcompany.Untitled.showMainWindow")

    /// True when another copy is already running: it is asked to come forward, and this copy quits.
    static func handOffToRunningCopy() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let first = others.first else { return false }
        DistributedNotificationCenter.default().postNotificationName(showMainWindowNotification, object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
        first.activate()
        return true
    }
}
#endif
