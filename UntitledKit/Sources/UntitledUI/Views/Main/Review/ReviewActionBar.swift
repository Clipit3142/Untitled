#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

/// The floating action bar for several selected items: one of the three custom glass surfaces
/// (3.16), in a container so it can morph. Controls use standard styles; Accept is prominent.
struct ReviewActionBar: View {
    var count: Int
    var accept: () -> Void
    var skip: () -> Void
    var changeStyle: (String) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: Spacing.m) {
                Button("Accept \(count)", action: accept)
                    .buttonStyle(.borderedProminent)
                Button("Skip", action: skip)
                Menu("Change Style") {
                    ForEach(model.styles) { style in
                        Button(style.name) { changeStyle(style.id) }
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .glassEffect(.regular, in: .capsule)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(count) items selected")
    }
}
#endif
