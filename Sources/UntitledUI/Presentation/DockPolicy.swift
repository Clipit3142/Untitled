/// Dock and ⌘-Tab presence (3.15, O1): shown while any window is open, gone within 1 s after
/// the last one closes, unless "Show in Dock" is on.
public struct DockPolicy: Sendable, Hashable {
    public enum Presence: Sendable, Hashable { case regular, accessory }

    /// How long after the last window closes the app leaves the Dock.
    public static let hideDelay: Double = 0.5

    public var showInDock: Bool
    public var openWindows: Int

    public init(showInDock: Bool, openWindows: Int = 0) {
        self.showInDock = showInDock
        self.openWindows = openWindows
    }

    public var presence: Presence { showInDock || openWindows > 0 ? .regular : .accessory }

    /// Leaving the Dock waits a moment, in case another window is about to open.
    public func delay(from old: Presence) -> Double {
        old == .regular && presence == .accessory ? Self.hideDelay : 0
    }
}
