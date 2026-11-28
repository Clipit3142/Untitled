#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A file thumbnail, loaded off the main thread and cached (W3). Never glass (3.16).
struct ThumbnailView: View {
    var path: String
    var size: Double = Metrics.rowThumbnail
    @Environment(ThumbnailLoader.self) private var loader
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (path as NSString).pathExtension) ?? .data))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: Radius.thumbnail))
        .accessibilityHidden(true)
        .task(id: path) {
            image = await loader.thumbnail(path: path, size: size)
        }
    }
}
#endif
