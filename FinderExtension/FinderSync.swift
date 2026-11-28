import Cocoa
import FinderSync
import UntitledShared

/// The Finder extension (3.15): active in granted folders only, with "Rename with Untitled…" for
/// 1–50 items and "Restore Original Name" for renamed files. Requests go through the app-group
/// container and an `untitled://` URL that carries only the request ID (P4, P5).
final class FinderSync: FIFinderSync {
    private let container: URL? = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "UntitledAppGroup") as? String else { return nil }
        return SharedHandoff.containerURL(groupIdentifier: group)
    }()
    private var refreshTimer: Timer?

    override init() {
        super.init()
        refreshDirectories()
        // The app republishes granted folders as they change; pick that up without a restart.
        refreshTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(refreshDirectories),
                                            userInfo: nil, repeats: true)
    }

    @objc private func refreshDirectories() {
        guard let container else { return }
        let urls = Set(SharedHandoff.grantedFolders(container: container).map { URL(fileURLWithPath: $0, isDirectory: true) })
        if urls != FIFinderSyncController.default().directoryURLs {
            FIFinderSyncController.default().directoryURLs = urls
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems, let container else { return nil }
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard (1...50).contains(items.count), items.allSatisfy({ SharedHandoff.isGranted(path: $0.path, container: container) }) else {
            return nil
        }
        let menu = NSMenu(title: "")
        menu.addItem(withTitle: "Rename with Untitled…", action: #selector(rename(_:)), keyEquivalent: "")
        if items.allSatisfy({ SharedHandoff.canRestore(path: $0.path, container: container) }) {
            menu.addItem(withTitle: "Restore Original Name", action: #selector(restore(_:)), keyEquivalent: "")
        }
        return menu
    }

    @objc private func rename(_ sender: AnyObject?) { send(.rename) }

    @objc private func restore(_ sender: AnyObject?) { send(.restoreOriginalName) }

    /// Works when Untitled isn't running: opening the URL launches it (P4).
    private func send(_ action: SharedHandoff.Request.Action) {
        guard let container else { return }
        let paths = (FIFinderSyncController.default().selectedItemURLs() ?? []).map(\.path)
        let request = SharedHandoff.Request(action: action, paths: paths)
        do {
            try SharedHandoff.write(request, container: container)
            NSWorkspace.shared.open(request.url)
        } catch {
            NSSound.beep()
        }
    }
}
