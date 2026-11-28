public import UntitledEngine

/// The menu bar glyph states (3.15). They differ by shape, never by color alone (N1).
public enum GlyphState: String, Sendable, Hashable, CaseIterable {
    case idle, working, needsReview, paused, problem

    /// Problem beats paused, which beats working, which beats a waiting review.
    public static func state(status: EngineStatus, reviewCount: Int, isWorking: Bool) -> GlyphState {
        switch status {
        case .needsAttention: return .problem
        case .paused, .held: return .paused
        case .working: return .working
        default: break
        }
        if isWorking { return .working }
        return reviewCount > 0 ? .needsReview : .idle
    }

    /// What VoiceOver reads for the status item.
    public var accessibilityLabel: String {
        switch self {
        case .idle: "Untitled"
        case .working: "Untitled, naming files"
        case .needsReview: "Untitled, files need review"
        case .paused: "Untitled, paused"
        case .problem: "Untitled, a folder needs attention"
        }
    }

    /// The mark added to the base glyph.
    public var badge: GlyphPath.Badge {
        switch self {
        case .idle: .none
        case .working: .sparkle
        case .needsReview: .dot
        case .paused: .slash
        case .problem: .exclamation
        }
    }

    /// Only the working glyph animates, and never with Reduce Motion (3.16, S2).
    public func animates(reduceMotion: Bool) -> Bool { self == .working && !reduceMotion }
}

/// The glyph as vector drawing commands in an 18 × 18 point box, origin at the top left.
/// AppKit turns this into a template image; tests render it to SVG (R5).
public struct GlyphPath: Sendable, Hashable {
    public enum Badge: String, Sendable, Hashable { case none, sparkle, dot, slash, exclamation }

    public enum Element: Sendable, Hashable {
        case move(Double, Double)
        case line(Double, Double)
        case close
        /// A full ellipse in the rectangle x, y, width, height.
        case ellipse(Double, Double, Double, Double)
    }

    public struct Shape: Sendable, Hashable {
        public var elements: [Element]
        public var lineWidth: Double
        public var filled: Bool
        /// Clears what is under the shape first (a knockout), so marks stay readable on the base.
        public var knockout: Double

        public init(_ elements: [Element], lineWidth: Double = 1.5, filled: Bool = false, knockout: Double = 0) {
            self.elements = elements
            self.lineWidth = lineWidth
            self.filled = filled
            self.knockout = knockout
        }
    }

    public static let size: Double = 18

    /// The base: a page with a folded corner and a name line, the "untitled document".
    public static let base: [Shape] = [
        Shape([.move(4, 2), .line(10.5, 2), .line(14, 5.5), .line(14, 16), .line(4, 16), .close]),
        Shape([.move(10.5, 2), .line(10.5, 5.5), .line(14, 5.5)], lineWidth: 1.2),
        Shape([.move(6.5, 12), .line(11.5, 12)], lineWidth: 1.5),
    ]

    /// The badge for a state, drawn in the lower right with a knockout ring.
    public static func badge(_ badge: Badge, frame: Int = 0) -> [Shape] {
        switch badge {
        case .none:
            return []
        case .dot:
            return [Shape([.ellipse(11, 11, 6, 6)], filled: true, knockout: 1.5)]
        case .slash:
            return [Shape([.move(2, 16.5), .line(16, 1.5)], lineWidth: 1.6, knockout: 1.4)]
        case .exclamation:
            return [Shape([.move(14, 9.5), .line(14, 13.8)], lineWidth: 1.8, knockout: 1.6),
                    Shape([.ellipse(13.05, 15.2, 1.9, 1.9)], filled: true, knockout: 1.2)]
        case .sparkle:
            // A four-point star whose size pulses over three frames while working.
            let scale = [1.0, 0.75, 0.5][((frame % 3) + 3) % 3]
            let cx = 14.0, cy = 14.0, r = 3.6 * scale, w = 1.1 * scale
            return [Shape([.move(cx, cy - r), .line(cx + w, cy - w), .line(cx + r, cy), .line(cx + w, cy + w),
                           .line(cx, cy + r), .line(cx - w, cy + w), .line(cx - r, cy), .line(cx - w, cy - w), .close],
                          filled: true, knockout: 1.3)]
        }
    }

    public static func shapes(for state: GlyphState, frame: Int = 0) -> [Shape] {
        base + badge(state.badge, frame: frame)
    }

    /// SVG for tests and for reviewing the glyphs at 1x and 2x.
    public static func svg(for state: GlyphState, frame: Int = 0, scale: Double = 1) -> String {
        func path(_ elements: [Element]) -> String {
            elements.map { element in
                switch element {
                case .move(let x, let y): "M\(x) \(y)"
                case .line(let x, let y): "L\(x) \(y)"
                case .close: "Z"
                case .ellipse(let x, let y, let w, let h):
                    "M\(x) \(y + h / 2) a\(w / 2) \(h / 2) 0 1 0 \(w) 0 a\(w / 2) \(h / 2) 0 1 0 \(-w) 0"
                }
            }.joined(separator: " ")
        }
        let pixels = size * scale
        var body = ""
        var maskShapes = ""
        for shape in badge(state.badge, frame: frame) where shape.knockout > 0 {
            maskShapes += "<path d=\"\(path(shape.elements))\" fill=\"\(shape.filled ? "black" : "none")\" stroke=\"black\" stroke-width=\"\(shape.lineWidth + 2 * shape.knockout)\" stroke-linecap=\"round\"/>"
        }
        for shape in base {
            body += "<path d=\"\(path(shape.elements))\" fill=\"none\" stroke=\"black\" stroke-width=\"\(shape.lineWidth)\" stroke-linejoin=\"round\" stroke-linecap=\"round\" mask=\"url(#k)\"/>"
        }
        for shape in badge(state.badge, frame: frame) {
            body += "<path d=\"\(path(shape.elements))\" fill=\"\(shape.filled ? "black" : "none")\" stroke=\"black\" stroke-width=\"\(shape.filled ? 0 : shape.lineWidth)\" stroke-linecap=\"round\"/>"
        }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(pixels)" height="\(pixels)" viewBox="0 0 \(size) \(size)">\
        <defs><mask id="k"><rect width="\(size)" height="\(size)" fill="white"/>\(maskShapes)</mask></defs>\(body)</svg>
        """
    }
}
