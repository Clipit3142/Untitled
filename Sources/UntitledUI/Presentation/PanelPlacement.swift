/// A rectangle in screen points, bottom-left origin as in AppKit. Plain doubles keep this testable everywhere.
public struct ScreenRect: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }

    public func contains(_ other: ScreenRect) -> Bool {
        other.minX >= minX && other.maxX <= maxX && other.minY >= minY && other.maxY <= maxY
    }
}

/// Where the panels go (3.15, N2).
public enum PanelPlacement {
    /// The menu bar panel hangs below its status item, centered on it, and is pushed back
    /// inside the visible frame of the screen the item is on, so it never appears off-screen.
    public static func menuBarPanel(size: (width: Double, height: Double), statusItem: ScreenRect, visibleFrame: ScreenRect) -> ScreenRect {
        let margin = Metrics.screenMargin
        let width = min(size.width, visibleFrame.width - 2 * margin)
        let height = min(size.height, visibleFrame.height - 2 * margin)
        var x = statusItem.midX - width / 2
        x = max(visibleFrame.minX + margin, min(x, visibleFrame.maxX - margin - width))
        var top = min(statusItem.minY - Metrics.panelGap, visibleFrame.maxY)
        if top - height < visibleFrame.minY + margin { top = visibleFrame.minY + margin + height }
        return ScreenRect(x: x, y: top - height, width: width, height: height)
    }

    /// Quick Rename sits in the upper third of the active screen, horizontally centered.
    public static func quickRename(size: (width: Double, height: Double), visibleFrame: ScreenRect) -> ScreenRect {
        let margin = Metrics.screenMargin
        let width = min(size.width, visibleFrame.width - 2 * margin)
        let height = min(size.height, visibleFrame.height - 2 * margin)
        let x = visibleFrame.midX - width / 2
        // The panel's center sits at one third from the top, without crossing the top margin.
        let center = visibleFrame.maxY - visibleFrame.height / 3
        let top = min(visibleFrame.maxY - margin, center + height / 2)
        let y = max(visibleFrame.minY + margin, top - height)
        return ScreenRect(x: x, y: y, width: width, height: height)
    }
}
