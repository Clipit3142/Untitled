#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledStore

/// A Review row: thumbnail, proposed name, original name, a destination chip, and a "Low" badge
/// with icon and text (color is never the only signal, 3.17).
struct ReviewRow: View {
    var item: QueueItem
    var destination: String?

    private var proposedName: String { item.proposal?.fileName ?? item.expected.name }
    private var isLow: Bool { item.proposal?.confidence == .low }

    var body: some View {
        HStack(spacing: Spacing.m) {
            ThumbnailView(path: item.path)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                FileNameText(name: proposedName)
                FileNameText(name: RowText.was(item.expected.name), style: .caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.s)
            if let destination {
                Label(destination, systemImage: "folder")
                    .appText(.caption)
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.xxs)
                    .background(.quinary, in: .capsule)
            }
            if isLow {
                Label("Low", systemImage: "exclamationmark.circle")
                    .appText(.caption)
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.xxs)
                    .overlay { Capsule().strokeBorder(.secondary) }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RowText.reviewLabel(proposedName: proposedName, currentName: item.expected.name,
                                                lowConfidence: isLow, destination: destination))
    }
}
#endif
