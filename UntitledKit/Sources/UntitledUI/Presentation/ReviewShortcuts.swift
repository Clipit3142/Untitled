/// Keyboard shortcuts of the Review list (3.15, M1), listed once so the views and the
/// Help menu agree.
public enum ReviewShortcut: String, Sendable, Hashable, CaseIterable {
    case previous, next, accept, skip, edit, quickLook, selectAll, acceptSelected

    /// The key, as SwiftUI's KeyEquivalent character or a named key.
    public var key: String {
        switch self {
        case .previous: "↑"
        case .next: "↓"
        case .accept: "↩"
        case .skip: "⌫"
        case .edit: "e"
        case .quickLook: "space"
        case .selectAll: "a"
        case .acceptSelected: "↩"
        }
    }

    public var usesCommand: Bool { self == .skip || self == .selectAll || self == .acceptSelected }

    public var displayText: String {
        switch self {
        case .previous: "↑"
        case .next: "↓"
        case .accept: "Return"
        case .skip: "⌘⌫"
        case .edit: "E"
        case .quickLook: "Space"
        case .selectAll: "⌘A"
        case .acceptSelected: "⌘Return"
        }
    }

    public var title: String {
        switch self {
        case .previous: "Previous"
        case .next: "Next"
        case .accept: "Accept"
        case .skip: "Skip"
        case .edit: "Edit Name"
        case .quickLook: "Quick Look"
        case .selectAll: "Select All"
        case .acceptSelected: "Accept Selected"
        }
    }
}
