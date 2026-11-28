#if canImport(SwiftUI)
import SwiftUI
import UntitledCore
import UntitledStore

/// A pending learning suggestion (3.11). Nothing changes until "Always".
struct SuggestionCard: View {
    var suggestion: Suggestion
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label {
                Text(verbatim: suggestion.question).appText(.body).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lightbulb")
            }
            HStack {
                Button("Always") { Task { await model.answer(.always, to: suggestion) } }
                    .buttonStyle(.borderedProminent)
                Button("Not Now") { Task { await model.answer(.notNow, to: suggestion) } }
                Spacer()
                Button("Never Ask") { Task { await model.answer(.neverAsk, to: suggestion) } }
                    .buttonStyle(.borderless)
            }
        }
        .padding(Spacing.m)
        .background(.quinary, in: .rect(cornerRadius: Radius.m))
        .accessibilityElement(children: .contain)
    }
}

/// The one-time offer to switch a folder to Automatic (O6).
struct AutomaticOfferCard: View {
    var folder: GrantedFolder
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label {
                Text("You've accepted most names in \(folder.displayName). Rename new files there automatically?")
                    .appText(.body).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "wand.and.stars")
            }
            HStack {
                Button("Go Automatic") { Task { await model.answerAutomaticOffer(folderID: folder.id, switchToAutomatic: true) } }
                    .buttonStyle(.borderedProminent)
                Button("Keep Reviewing") { Task { await model.answerAutomaticOffer(folderID: folder.id, switchToAutomatic: false) } }
            }
        }
        .padding(Spacing.m)
        .background(.quinary, in: .rect(cornerRadius: Radius.m))
        .accessibilityElement(children: .contain)
    }
}
#endif
