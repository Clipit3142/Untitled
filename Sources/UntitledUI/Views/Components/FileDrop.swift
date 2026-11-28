#if canImport(AppKit)
import Foundation
import AppKit
import UniformTypeIdentifiers

/// Reads file URLs from dropped item providers.
enum FileDrop {
    @MainActor
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await withCheckedContinuation({ (continuation: CheckedContinuation<URL?, Never>) in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }) {
                urls.append(url)
            }
        }
        return urls
    }
}
#endif
