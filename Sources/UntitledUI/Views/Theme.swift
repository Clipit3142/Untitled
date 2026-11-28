#if canImport(SwiftUI)
public import SwiftUI

extension Animation {
    /// The SwiftUI animation for a motion curve (3.16).
    public init(_ curve: MotionCurve) {
        switch curve.kind {
        case .smooth: self = .smooth(duration: curve.duration)
        case .snappy: self = .snappy(duration: curve.duration)
        case .bouncy: self = .bouncy(duration: curve.duration, extraBounce: curve.bounce)
        case .easeOut: self = .easeOut(duration: curve.duration)
        case .crossfade: self = .easeInOut(duration: curve.duration)
        }
    }
}

/// Reads Reduce Motion once and hands out the right animation (S2).
struct MotionReader {
    var reduceMotion: Bool

    func animation(_ curve: MotionCurve) -> Animation {
        Animation(Motion.resolved(curve, reduceMotion: reduceMotion))
    }

    /// Movement transitions become plain opacity with Reduce Motion.
    func transition(_ moving: AnyTransition) -> AnyTransition {
        reduceMotion ? .opacity : moving
    }
}

/// One text style per role; call sites never set fonts by hand (design-system rules).
struct AppTextStyle {
    var font: Font
    var design: Font.Design = .default
    var weight: Font.Weight = .regular
    var monospacedDigits = false

    static let title = AppTextStyle(font: .title2, weight: .semibold)
    static let headline = AppTextStyle(font: .headline)
    static let body = AppTextStyle(font: .body)
    static let fileName = AppTextStyle(font: .body, weight: .medium)
    static let secondary = AppTextStyle(font: .callout)
    static let caption = AppTextStyle(font: .caption)
    static let time = AppTextStyle(font: .caption, monospacedDigits: true)
    static let pill = AppTextStyle(font: .callout, weight: .medium)
}

extension View {
    func appText(_ style: AppTextStyle) -> some View {
        font(style.font.weight(style.weight))
            .monospacedDigit(style.monospacedDigits)
    }
}

private extension View {
    @ViewBuilder
    func monospacedDigit(_ enabled: Bool) -> some View {
        if enabled { self.monospacedDigit() } else { self }
    }
}

extension EdgeInsets {
    static var row: EdgeInsets { EdgeInsets(top: Spacing.xs, leading: Spacing.s, bottom: Spacing.xs, trailing: Spacing.s) }
}
#endif
