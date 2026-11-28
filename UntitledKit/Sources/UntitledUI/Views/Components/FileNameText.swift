#if canImport(SwiftUI)
import SwiftUI

/// A file name that truncates in the middle, so the extension stays visible; the full name is a
/// tooltip and what VoiceOver reads (3.16).
struct FileNameText: View {
    var name: String
    var style: AppTextStyle = .fileName

    var body: some View {
        Text(verbatim: name)
            .appText(style)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(name)
            .accessibilityLabel(Text(verbatim: name))
    }
}
#endif
