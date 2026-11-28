#if canImport(SwiftUI)
import SwiftUI

/// The rename moment (3.16): the old name blurs and fades in 0.2 s while the new one rises into
/// place in 0.25 s. With Reduce Motion it is a crossfade.
struct RenameMomentText: View {
    var oldName: String
    var newName: String
    var animate: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showNew = false

    var body: some View {
        ZStack(alignment: .leading) {
            FileNameText(name: oldName)
                .opacity(showNew ? 0 : 1)
                .blur(radius: showNew && !reduceMotion ? 4 : 0)
                .animation(Animation(Motion.resolved(Motion.renameOut, reduceMotion: reduceMotion)), value: showNew)
                .accessibilityHidden(true)
            FileNameText(name: newName)
                .opacity(showNew ? 1 : 0)
                .offset(y: showNew || reduceMotion ? 0 : 6)
                .animation(Animation(Motion.resolved(Motion.renameIn, reduceMotion: reduceMotion)), value: showNew)
        }
        .onAppear { showNew = !animate }
        .task {
            guard animate else { return }
            showNew = true
        }
    }
}
#endif
