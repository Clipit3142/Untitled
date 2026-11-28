#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import Observation

/// The menu bar item (3.15): a monochrome template glyph whose shape shows the state, animated
/// only while working (never with Reduce Motion), accepting file drops for Quick Rename.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private var frame = 0
    private var animationTask: Task<Void, Never>?
    var onClick: () -> Void = {}
    var onDrop: ([URL]) -> Void = { _ in }

    init(model: AppModel) {
        self.model = model
        super.init()
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityRole(.button)
        // Drops onto the status item: its window forwards dragging messages to its delegate.
        button.window?.registerForDraggedTypes([.fileURL])
        button.window?.delegate = self
        observe()
    }

    /// The status item's frame on screen, for placing the panel.
    var buttonFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    var screen: NSScreen? { statusItem.button?.window?.screen }

    @objc private func clicked() { onClick() }

    private func observe() {
        withObservationTracking {
            render(model.glyphState)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func render(_ state: GlyphState) {
        statusItem.button?.image = Self.image(for: state, frame: frame)
        statusItem.button?.setAccessibilityLabel(state.accessibilityLabel)
        statusItem.button?.toolTip = model.statusText
        let animates = state.animates(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if animates, animationTask == nil {
            animationTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Motion.glyphFrameInterval))
                    guard let self else { return }
                    self.frame += 1
                    self.statusItem.button?.image = Self.image(for: .working, frame: self.frame)
                }
            }
        } else if !animates {
            animationTask?.cancel()
            animationTask = nil
            frame = 0
        }
    }

    /// Draws the glyph as a vector template image, crisp at any scale (R5).
    nonisolated static func image(for state: GlyphState, frame: Int) -> NSImage {
        let size = NSSize(width: GlyphPath.size, height: GlyphPath.size)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let shapes = GlyphPath.shapes(for: state, frame: frame)
            let base = shapes.prefix(GlyphPath.base.count)
            let badge = shapes.dropFirst(GlyphPath.base.count)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            NSColor.black.set()
            for shape in base { stroke(shape, in: context) }
            // Knock out a ring around the badge, then draw it, then erase its cut-outs.
            context.setBlendMode(.clear)
            for shape in badge where shape.knockout > 0 && !shape.erases {
                stroke(shape, in: context, extra: 2 * shape.knockout)
                if shape.filled { fill(shape, in: context) }
            }
            context.setBlendMode(.normal)
            for shape in badge where !shape.erases {
                if shape.filled { fill(shape, in: context) }
                stroke(shape, in: context)
            }
            context.setBlendMode(.clear)
            for shape in badge where shape.erases {
                if shape.filled { fill(shape, in: context) }
                stroke(shape, in: context)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityLabel
        return image
    }

    private nonisolated static func path(_ shape: GlyphPath.Shape) -> CGPath {
        let path = CGMutablePath()
        for element in shape.elements {
            switch element {
            case .move(let x, let y): path.move(to: CGPoint(x: x, y: y))
            case .line(let x, let y): path.addLine(to: CGPoint(x: x, y: y))
            case .close: path.closeSubpath()
            case .ellipse(let x, let y, let w, let h): path.addEllipse(in: CGRect(x: x, y: y, width: w, height: h))
            }
        }
        return path
    }

    private nonisolated static func stroke(_ shape: GlyphPath.Shape, in context: CGContext, extra: Double = 0) {
        context.addPath(path(shape))
        context.setLineWidth(shape.lineWidth + extra)
        context.strokePath()
    }

    private nonisolated static func fill(_ shape: GlyphPath.Shape, in context: CGContext) {
        context.addPath(path(shape))
        context.fillPath()
    }

    // MARK: Drops (3.15: dropping files on the status item opens Quick Rename)

    @objc func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        statusItem.button?.highlight(true)
        return .copy
    }

    @objc func draggingExited(_ sender: (any NSDraggingInfo)?) {
        statusItem.button?.highlight(false)
    }

    @objc func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        statusItem.button?.highlight(false)
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }
}
#endif
