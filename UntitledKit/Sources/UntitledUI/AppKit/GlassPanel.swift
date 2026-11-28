#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

/// A borderless floating panel whose content sits on system glass (NSGlassEffectView).
/// Used for exactly two of the three custom glass surfaces: the menu bar panel and Quick Rename (3.16).
final class GlassPanel: NSPanel {
    /// Called for Esc and for clicks outside, so the owner can close it (N2).
    var onDismiss: () -> Void = {}
    private var outsideClickMonitor: Any?
    private let acceptsKey: Bool

    init<Content: View>(rootView: Content, acceptsKey: Bool) {
        self.acceptsKey = acceptsKey
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow

        let glass = NSGlassEffectView()
        glass.cornerRadius = Radius.panel
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]
        glass.contentView = hosting
        contentView = glass
    }

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onDismiss()
    }

    /// Shows the panel at a frame computed by `PanelPlacement`, with the 0.35 s panel-open spring
    /// approximated by a short fade (AppKit), or no animation with Reduce Motion.
    func present(at frame: NSRect) {
        setFrame(frame, display: true)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        alphaValue = 0
        if acceptsKey { makeKeyAndOrderFront(nil) } else { orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.resolved(Motion.panelOpen, reduceMotion: reduceMotion).duration
            animator().alphaValue = 1
        }
        startMonitoringOutsideClicks()
    }

    func dismissPanel() {
        stopMonitoringOutsideClicks()
        orderOut(nil)
    }

    private func startMonitoringOutsideClicks() {
        stopMonitoringOutsideClicks()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDismiss() }
        }
    }

    private func stopMonitoringOutsideClicks() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// The content's preferred size, measured by SwiftUI.
    var fittingContentSize: NSSize {
        (contentView as? NSGlassEffectView)?.contentView?.fittingSize ?? NSSize(width: Metrics.menuBarPanelWidth, height: 300)
    }
}

extension ScreenRect {
    init(_ rect: NSRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    var nsRect: NSRect { NSRect(x: x, y: y, width: width, height: height) }
}
#endif
