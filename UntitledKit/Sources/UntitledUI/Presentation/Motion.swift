/// The motion vocabulary of 3.16. Views turn these into SwiftUI animations; nothing exceeds 0.5 s (S1).
public struct MotionCurve: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        /// A smooth spring with no bounce.
        case smooth
        /// A quick spring for small controls.
        case snappy
        /// A spring with a slight bounce, for panels opening.
        case bouncy
        /// Fades out, used for the old name leaving.
        case easeOut
        /// A plain crossfade: the only motion left with Reduce Motion (S2).
        case crossfade
    }

    public var kind: Kind
    public var duration: Double
    public var bounce: Double

    public init(_ kind: Kind, duration: Double, bounce: Double = 0) {
        self.kind = kind
        self.duration = duration
        self.bounce = bounce
    }
}

public enum Motion {
    /// Standard transitions: ~0.3 s smooth spring.
    public static let standard = MotionCurve(.smooth, duration: 0.3)
    /// Small controls: ~0.2 s snappy spring.
    public static let control = MotionCurve(.snappy, duration: 0.2)
    /// Panels opening: 0.35 s with a slight bounce.
    public static let panelOpen = MotionCurve(.bouncy, duration: 0.35, bounce: 0.12)
    /// The rename moment: the old name blurs and fades…
    public static let renameOut = MotionCurve(.easeOut, duration: 0.2)
    /// …while the new one rises into place.
    public static let renameIn = MotionCurve(.smooth, duration: 0.25)
    /// The row then glides into Recent or Activity.
    public static let rowGlide = MotionCurve(.smooth, duration: 0.3)
    /// Counts roll.
    public static let countRoll = MotionCurve(.snappy, duration: 0.2)
    /// New rows slide in from the top with a fade.
    public static let rowInsert = MotionCurve(.smooth, duration: 0.3)
    /// The action bar morphing in and out of the Review list.
    public static let actionBar = MotionCurve(.smooth, duration: 0.3)
    /// The longest crossfade allowed with Reduce Motion.
    public static let reducedCrossfadeLimit = 0.2
    /// The upper bound for every animation.
    public static let limit = 0.5
    /// Seconds per frame of the working glyph (it animates only while working).
    public static let glyphFrameInterval = 0.25

    public static let all: [String: MotionCurve] = [
        "standard": standard, "control": control, "panelOpen": panelOpen, "renameOut": renameOut,
        "renameIn": renameIn, "rowGlide": rowGlide, "countRoll": countRoll, "rowInsert": rowInsert,
        "actionBar": actionBar,
    ]

    /// With Reduce Motion, every animation becomes a crossfade of at most 0.2 s (S2).
    public static func resolved(_ curve: MotionCurve, reduceMotion: Bool) -> MotionCurve {
        guard reduceMotion else { return curve }
        return MotionCurve(.crossfade, duration: min(curve.duration, reducedCrossfadeLimit))
    }

    /// Whether movement (offsets, blur, shimmer, glyph frames) may be used at all.
    public static func allowsMovement(reduceMotion: Bool) -> Bool { !reduceMotion }
}
