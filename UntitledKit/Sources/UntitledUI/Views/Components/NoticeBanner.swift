#if canImport(SwiftUI)
import SwiftUI

/// Transient notices from the engine, shown at the bottom of a window or panel.
struct NoticeStack: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(model.notices) { notice in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Image(systemName: "info.circle")
                    Text(verbatim: notice.text).appText(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Dismiss", systemImage: "xmark") { model.dismiss(notice) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
                .padding(Spacing.s)
                .background(.quinary, in: .rect(cornerRadius: Radius.s))
                .accessibilityElement(children: .contain)
                .task {
                    try? await Task.sleep(for: .seconds(8))
                    model.dismiss(notice)
                }
            }
        }
    }
}
#endif
