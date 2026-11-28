public import Foundation
public import Observation

/// Sections of the main window's sidebar (3.15).
public enum MainSection: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case review, activity, folders, styles, rules

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .review: "Review"
        case .activity: "Activity"
        case .folders: "Folders"
        case .styles: "Styles"
        case .rules: "Rules"
        }
    }

    public var symbol: String {
        switch self {
        case .review: "tray.full"
        case .activity: "clock.arrow.circlepath"
        case .folders: "folder"
        case .styles: "textformat"
        case .rules: "arrow.triangle.branch"
        }
    }
}

/// A folder the user picked, with its security-scoped bookmark.
public struct FolderChoice: Sendable, Hashable {
    public var url: URL
    public var bookmark: Data?

    public init(url: URL, bookmark: Data?) {
        self.url = url
        self.bookmark = bookmark
    }
}

/// Navigation and system actions views ask for. The AppKit shell fills in the closures;
/// tests use the defaults, which record what was asked.
@MainActor
@Observable
public final class AppRouter {
    public var section: MainSection = .review

    @ObservationIgnored public var openMainWindow: (MainSection?) -> Void = { _ in }
    @ObservationIgnored public var openSettings: () -> Void = {}
    @ObservationIgnored public var openQuickRename: ([URL]) -> Void = { _ in }
    @ObservationIgnored public var showInFinder: (String) -> Void = { _ in }
    @ObservationIgnored public var closePanel: () -> Void = {}
    @ObservationIgnored public var chooseFolder: (_ startingAt: URL?, _ prompt: String) async -> FolderChoice? = { _, _ in nil }
    @ObservationIgnored public var copyToPasteboard: (String) -> Void = { _ in }
    @ObservationIgnored public var openURL: (URL) -> Void = { _ in }
    @ObservationIgnored public var exportDiagnostics: (String) -> Void = { _ in }
    /// Asks for notification permission; called only from onboarding step 6 (P1).
    @ObservationIgnored public var requestNotificationPermission: () async -> Bool = { false }
    @ObservationIgnored public var finderExtensionEnabled: () -> Bool = { false }
    @ObservationIgnored public var openFinderExtensionSettings: () -> Void = {}
    /// The Downloads folder, granted by entitlement (B4).
    @ObservationIgnored public var downloadsFolder: () -> URL? = { nil }
    @ObservationIgnored public var desktopFolder: () -> URL? = { nil }

    public init() {}

    public func show(_ section: MainSection) {
        self.section = section
        openMainWindow(section)
    }
}
