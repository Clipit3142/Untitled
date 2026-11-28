#if canImport(SwiftUI)
import SwiftUI

/// The placeholder shown while a proposal is generated (Quick Rename). No shimmer with Reduce Motion (S2).
struct ShimmerPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.s)
            .fill(.quaternary)
            .frame(height: 22)
            .overlay {
                if !reduceMotion {
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .offset(x: phase ? 260 : -260)
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: phase)
                }
            }
            .clipShape(.rect(cornerRadius: Radius.s))
            .onAppear { phase = true }
            .accessibilityLabel("Generating a name")
    }
}
#endif
