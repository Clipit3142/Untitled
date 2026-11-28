#if canImport(SwiftUI)
import SwiftUI

/// The status pill: a plain capsule, never glass inside the glass panel (3.15, Part 5 #19).
struct StatusPill: View {
    var text: String
    var symbol: String

    var body: some View {
        Label {
            Text(verbatim: text).appText(.pill).lineLimit(1)
        } icon: {
            Image(systemName: symbol)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .background(.quaternary, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityIdentifier("statusPill")
    }
}

extension GlyphState {
    /// The SF Symbol shown in the pill for each state; shape, not color, tells them apart.
    var pillSymbol: String {
        switch self {
        case .idle: "eye"
        case .working: "sparkles"
        case .needsReview: "circle.fill"
        case .paused: "pause.circle"
        case .problem: "exclamationmark.triangle"
        }
    }
}
#endif
