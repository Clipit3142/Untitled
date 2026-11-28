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
        /// Clears a ring this wide around the shape in the base, so marks stay readable on it.
        public var knockout: Double
        /// Erases from the badge instead of drawing (the "!" cut out of the warning triangle).
        public var erases: Bool

        public init(_ elements: [Element], lineWidth: Double = 1.5, filled: Bool = false, knockout: Double = 0, erases: Bool = false) {
            self.elements = elements
            self.lineWidth = lineWidth
            self.filled = filled
            self.knockout = knockout
            self.erases = erases
        }
    }

    public static let size: Double = 18

    /// The base: a page with a folded corner and a name line, the "untitled document".
    public static let base: [Shape] = [
        Shape([.move(3, 1.75), .line(9.25, 1.75), .line(12.75, 5.25), .line(12.75, 16.25), .line(3, 16.25), .close]),
        Shape([.move(9.25, 1.75), .line(9.25, 5.25), .line(12.75, 5.25)], lineWidth: 1.2),
        Shape([.move(5.5, 11.5), .line(9.5, 11.5)], lineWidth: 1.5),
    ]

    /// The badge for a state, drawn in the lower right with a knockout ring.
    public static func badge(_ badge: Badge, frame: Int = 0) -> [Shape] {
        switch badge {
        case .none:
            return []
        case .dot:
            return [Shape([.ellipse(10.75, 10.25, 6.5, 6.5)], lineWidth: 0.5, filled: true, knockout: 1.8)]
        case .slash:
            return [Shape([.move(1.5, 17), .line(16.5, 1)], lineWidth: 1.7, knockout: 1.3)]
        case .exclamation:
            // A warning triangle with the exclamation mark cut out.
            return [Shape([.move(13.75, 8.25), .line(17.75, 16.75), .line(9.75, 16.75), .close], lineWidth: 1, filled: true, knockout: 1.4),
                    Shape([.move(13.75, 11.25), .line(13.75, 13.6)], lineWidth: 1.3, erases: true),
                    Shape([.ellipse(13.05, 14.55, 1.4, 1.4)], lineWidth: 0.2, filled: true, erases: true)]
        case .sparkle:
            // A four-point star whose size pulses over three frames while working.
            let scale = [1.0, 0.8, 0.6][((frame % 3) + 3) % 3]
            let cx = 13.5, cy = 12.75, r = 4.25 * scale, w = 1.25 * scale
            return [Shape([.move(cx, cy - r), .line(cx + w, cy - w), .line(cx + r, cy), .line(cx + w, cy + w),
                           .line(cx, cy + r), .line(cx - w, cy + w), .line(cx - r, cy), .line(cx - w, cy - w), .close],
                          lineWidth: 0.6, filled: true, knockout: 1.3)]
        }
    }

    public static func shapes(for state: GlyphState, frame: Int = 0) -> [Shape] {
        base + badge(state.badge, frame: frame)
    }

    /// SVG for tests and for reviewing the glyphs at 1x and 2x.
    public static func svg(for state: GlyphState, frame: Int = 0, scale: Double = 1, color: String = "black") -> String {
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
        func draw(_ shape: Shape, color: String, extra: Double = 0, mask: String? = nil) -> String {
            let fill = shape.filled ? color : "none"
            let maskAttribute = mask.map { " mask=\"url(#\($0))\"" } ?? ""
            return "<path d=\"\(path(shape.elements))\" fill=\"\(fill)\" stroke=\"\(color)\" stroke-width=\"\(shape.lineWidth + extra)\" stroke-linejoin=\"round\" stroke-linecap=\"round\"\(maskAttribute)/>"
        }
        let badgeShapes = badge(state.badge, frame: frame)
        let knockouts = badgeShapes.filter { !$0.erases && $0.knockout > 0 }.map { draw($0, color: "black", extra: 2 * $0.knockout) }.joined()
        let erasers = badgeShapes.filter(\.erases).map { draw($0, color: "black") }.joined()
        let white = "<rect width=\"\(size)\" height=\"\(size)\" fill=\"white\"/>"
        // Mask IDs are unique per glyph, so several glyphs can share one document.
        let k = "k-\(state.rawValue)-\(frame)", e = "e-\(state.rawValue)-\(frame)"
        let body = base.map { draw($0, color: color, mask: k) }.joined()
            + badgeShapes.filter { !$0.erases }.map { draw($0, color: color, mask: e) }.joined()
        // Masks in user space: the default bounding-box units clip strokes and hide the flat name line.
        let units = "maskUnits=\"userSpaceOnUse\" x=\"0\" y=\"0\" width=\"\(size)\" height=\"\(size)\""
        let pixels = size * scale
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(pixels)" height="\(pixels)" viewBox="0 0 \(size) \(size)">\
        <defs><mask id="\(k)" \(units)>\(white)\(knockouts)</mask><mask id="\(e)" \(units)>\(white)\(erasers)</mask></defs>\(body)</svg>
        """
    }
}
