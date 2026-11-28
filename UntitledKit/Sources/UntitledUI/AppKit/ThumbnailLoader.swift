#if canImport(AppKit) && canImport(QuickLookThumbnailing)
import AppKit
import Observation
import QuickLookThumbnailing
import UntitledFS

/// Thumbnails for rows, cached in Caches with least-recently-used eviction at 200 MB (W3).
@MainActor
@Observable
final class ThumbnailLoader {
    @ObservationIgnored private let cache: ThumbnailCache?
    @ObservationIgnored private let memory = NSCache<NSString, NSImage>()

    init(cache: ThumbnailCache?) {
        self.cache = cache
        memory.countLimit = 300
    }

    func thumbnail(path: String, size: Double) async -> NSImage? {
        guard let status = FileSystem.status(atPath: path) else { return nil }
        // The key changes when the file changes, so stale thumbnails are never shown.
        let key = "\(path)|\(status.modification)|\(Int(size))"
        if let image = memory.object(forKey: key as NSString) { return image }
        let cache = self.cache
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let data: Data? = await Task.detached(priority: .utility) {
            if let stored = cache?.data(for: key) { return stored }
            let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: size, height: size),
                                                       scale: scale, representationTypes: .thumbnail)
            guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
                  let png = NSBitmapImageRep(cgImage: representation.cgImage).representation(using: .png, properties: [:]) else { return nil }
            cache?.store(png, for: key)
            return png
        }.value
        guard let data, let image = NSImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }
}
#endif
