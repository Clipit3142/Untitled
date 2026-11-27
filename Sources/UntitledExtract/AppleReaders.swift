#if canImport(Vision) && canImport(PDFKit) && canImport(AppKit) && canImport(QuickLookThumbnailing)
public import Foundation
import AppKit
import CoreGraphics
import ImageIO
import NaturalLanguage
import PDFKit
import QuickLookThumbnailing
import Vision
import UntitledCore
public import UntitledModel

/// Downscales without decoding the full image, so a 100-megapixel photo stays far below
/// the 500 MB limit (E3).
enum ImageDownscaler {
    static func image(at url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func scaled(_ image: CGImage, maxPixels: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixels else { return image }
        let scale = Double(maxPixels) / Double(longest)
        let width = Int(Double(image.width) * scale)
        let height = Int(Double(image.height) * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

/// Vision text recognition (accurate, automatic language) and classification (3.7).
enum VisionReader {
    static func lines(in image: CGImage) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return RecognizedLine(text: text, height: Double(observation.boundingBox.height))
        }
    }

    static func labels(in image: CGImage) async throws -> [ImageLabel] {
        let request = ClassifyImageRequest()
        let observations = try await request.perform(on: image)
        return observations.filter { $0.confidence >= 0.1 }.prefix(5).map {
            ImageLabel(identifier: $0.identifier, confidence: Double($0.confidence))
        }
    }
}

/// PNG, JPEG, HEIC, TIFF, GIF and WebP.
public struct ImageReader: ContentReader {
    public init() {}

    public func canRead(extension ext: String) -> Bool { Eligibility.imageExtensions.contains(ext) }

    public func read(url: URL, options: ReadOptions) async throws -> ExtractedContent {
        guard let image = ImageDownscaler.image(at: url, maxPixels: Defaults.ocrMaxPixels) else { return .empty }
        let lines = try await VisionReader.lines(in: image)
        let labels = (try? await VisionReader.labels(in: image)) ?? []
        let forModel = options.includeImageForModel ? PromptImage(cgImage: ImageDownscaler.scaled(image, maxPixels: Defaults.modelImageMaxPixels)) : nil
        return ExtractedContent(lines: lines, labels: labels, image: forModel)
    }
}

/// PDFKit text from the first N pages; pages with almost no text are treated as scans,
/// rendered at 200 dpi and recognized. Password-protected PDFs are never unlocked or prompted.
public struct PDFReader: ContentReader {
    public init() {}

    public func canRead(extension ext: String) -> Bool { ext == "pdf" }

    public func read(url: URL, options: ReadOptions) async throws -> ExtractedContent {
        guard let document = PDFDocument(url: url) else { return .empty }
        if document.isEncrypted || document.isLocked {
            return ExtractedContent(pageCount: document.pageCount, passwordProtected: true)
        }
        var lines: [RecognizedLine] = []
        var isScan = false
        var firstPageImage: CGImage?
        for index in 0..<min(options.pdfPages, document.pageCount) {
            guard let page = document.page(at: index) else { continue }
            let text = page.string ?? ""
            if text.filter({ !$0.isWhitespace }).count < Defaults.scanPageCharacterThreshold {
                isScan = true
                if let image = Self.render(page) {
                    lines += try await VisionReader.lines(in: image)
                    if index == 0 { firstPageImage = image }
                }
            } else {
                lines += Self.lines(of: page)
            }
        }
        let forModel = options.includeImageForModel && isScan
            ? firstPageImage.map { PromptImage(cgImage: ImageDownscaler.scaled($0, maxPixels: Defaults.modelImageMaxPixels)) } : nil
        return ExtractedContent(lines: lines, pageCount: document.pageCount, isScan: isScan, image: forModel)
    }

    /// Lines with relative font size as height, so the title line can be found.
    static func lines(of page: PDFPage) -> [RecognizedLine] {
        guard let attributed = page.attributedString else {
            return (page.string ?? "").split(whereSeparator: \.isNewline).map { RecognizedLine(text: String($0)) }
        }
        var result: [RecognizedLine] = []
        let string = attributed.string as NSString
        var location = 0
        while location < string.length {
            let range = string.lineRange(for: NSRange(location: location, length: 0))
            let text = string.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
                result.append(RecognizedLine(text: text, height: font.map { Double($0.pointSize) / 100 }))
            }
            location = NSMaxRange(range)
        }
        return result
    }

    static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = Defaults.scanRenderDPI / 72
        var width = Int(bounds.width * scale)
        var height = Int(bounds.height * scale)
        let longest = max(width, height)
        if longest > Defaults.ocrMaxPixels {
            width = width * Defaults.ocrMaxPixels / longest
            height = height * Defaults.ocrMaxPixels / longest
        }
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}

/// RTF, DOC and DOCX, read as attributed strings (3.7). Plain text, Markdown and HTML use
/// `PlainTextReader`, which needs no main thread.
public struct AttributedStringReader: ContentReader {
    public init() {}

    public func canRead(extension ext: String) -> Bool { ["rtf", "doc", "docx"].contains(ext) }

    public func read(url: URL, options: ReadOptions) async throws -> ExtractedContent {
        let type: NSAttributedString.DocumentType
        switch url.pathExtension.lowercased() {
        case "rtf": type = .rtf
        case "doc": type = .docFormat
        default: type = .officeOpenXML
        }
        let attributed = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
        var lines: [RecognizedLine] = []
        let string = attributed.string as NSString
        var location = 0
        while location < string.length, lines.count < 400 {
            let range = string.lineRange(for: NSRange(location: location, length: 0))
            let text = string.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
                lines.append(RecognizedLine(text: text, height: font.map { Double($0.pointSize) / 100 }))
            }
            location = NSMaxRange(range)
        }
        return ExtractedContent(lines: lines)
    }
}

/// XLSX, PPTX, Pages, Numbers and Keynote: a 1,024 px Quick Look thumbnail, recognized and
/// also offered to the model as an image (3.7).
public struct QuickLookReader: ContentReader {
    public init() {}

    public func canRead(extension ext: String) -> Bool { ["xlsx", "pptx", "pages", "numbers", "key"].contains(ext) }

    public func read(url: URL, options: ReadOptions) async throws -> ExtractedContent {
        let size = CGSize(width: Defaults.quickLookThumbnailPixels, height: Defaults.quickLookThumbnailPixels)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 1, representationTypes: .thumbnail)
        let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        let image = representation.cgImage
        let lines = try await VisionReader.lines(in: image)
        return ExtractedContent(lines: lines, image: options.includeImageForModel ? PromptImage(cgImage: image) : nil)
    }
}

/// Spotlight's screen-capture attribute, the "Screenshot" image comment, then the name (3.7).
public struct AppleScreenshotDetector: ScreenshotDetecting {
    let fallback: NameScreenshotDetector

    public init(timeZone: TimeZone = .current) {
        fallback = NameScreenshotDetector(timeZone: timeZone)
    }

    public func detect(path: String, name: String) -> ScreenshotEvidence? {
        let url = URL(fileURLWithPath: path)
        let byName = fallback.detect(path: path, name: name)
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let flag = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool, flag {
            let created = MDItemCopyAttribute(item, kMDItemContentCreationDate) as? Date
            return ScreenshotEvidence(captureDate: created ?? byName?.captureDate, captureDateValue: created == nil ? byName?.captureDateValue : nil)
        }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           (exif[kCGImagePropertyExifUserComment] as? String) == "Screenshot" {
            return byName ?? ScreenshotEvidence(captureDate: nil, captureDateValue: nil)
        }
        return byName
    }
}

/// Feeds app activations into the timeline. Never saved (3.7).
@MainActor
public final class WorkspaceActivationObserver {
    private var token: (any NSObjectProtocol)?

    public init(timeline: AppTimeline) {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let name = app?.localizedName, app?.bundleIdentifier != Bundle.main.bundleIdentifier {
                timeline.record(app: name, at: Date())
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication?.localizedName {
            timeline.record(app: front, at: Date())
        }
    }
}

public enum AppleLanguageDetector {
    /// The dominant language with NaturalLanguage, mapped to a name language (3.7).
    public static func detect(_ text: String) -> NameLanguage? {
        guard !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(4_000)))
        return recognizer.dominantLanguage.flatMap { NameLanguage(languageTag: $0.rawValue) }
    }
}

public enum AppleReaders {
    /// Every reader, in priority order.
    public static var all: [any ContentReader] {
        [ImageReader(), PDFReader(), AttributedStringReader(), QuickLookReader(), PlainTextReader()]
    }
}
#endif
