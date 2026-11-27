public import Foundation
public import UntitledCore
import UntitledModel
import UntitledFS
import Synchronization

/// Detects screenshots: Spotlight's screen-capture attribute, then the "Screenshot" image
/// comment, then localized default names (3.7).
public protocol ScreenshotDetecting: Sendable {
    func detect(path: String, name: String) -> ScreenshotEvidence?
}

public struct ScreenshotEvidence: Sendable, Hashable {
    public var captureDate: Date?
    public var captureDateValue: DateValue?
}

/// Name-based detection only (portable fallback and last signal).
public struct NameScreenshotDetector: ScreenshotDetecting {
    public let timeZone: TimeZone
    public init(timeZone: TimeZone = .current) { self.timeZone = timeZone }

    public func detect(path: String, name: String) -> ScreenshotEvidence? {
        guard let match = ScreenshotName.parse(name), !match.isRecording else { return nil }
        return ScreenshotEvidence(captureDate: match.captureDate.flatMap { $0.date(in: timeZone) }, captureDateValue: match.captureDate)
    }
}

/// App activations of the last 10 minutes, in memory only (3.7). Gives the frontmost app at
/// capture time, because macOS writes a screenshot seconds after capture.
public final class AppTimeline: Sendable {
    private let activations = Mutex<[(date: Date, app: String)]>([])
    private let window: TimeInterval

    public init(window: TimeInterval = Defaults.appTimelineWindow) {
        self.window = window
    }

    public func record(app: String, at date: Date) {
        activations.withLock { list in
            list.append((date, app))
            list.removeAll { $0.date < date.addingTimeInterval(-window) }
        }
    }

    /// The app that was frontmost at `date`.
    public func app(at date: Date) -> String? {
        activations.withLock { list in list.last { $0.date <= date }?.app }
    }
}

/// Reads a file's content and metadata (3.7).
public struct Extractor: Sendable {
    let readers: [any ContentReader]
    let screenshotDetector: any ScreenshotDetecting
    let timeline: AppTimeline?
    let detectLanguage: @Sendable (String) -> NameLanguage?
    let timeZone: TimeZone

    public init(readers: [any ContentReader], screenshotDetector: any ScreenshotDetecting = NameScreenshotDetector(),
                timeline: AppTimeline? = nil, detectLanguage: @escaping @Sendable (String) -> NameLanguage? = LanguageGuesser.guess,
                timeZone: TimeZone = .current) {
        self.readers = readers
        self.screenshotDetector = screenshotDetector
        self.timeline = timeline
        self.detectLanguage = detectLanguage
        self.timeZone = timeZone
    }

    /// Reads a file. `metadataOnly` skips content (disallowed types, dataless files, files
    /// over the size limit); password-protected PDFs also end up metadata-only.
    public func extract(path: String, facts: FileFacts, metadataOnly: MetadataOnlyReason?, options: ReadOptions) async -> ExtractionResult {
        let name = facts.name
        var metadata = FileMetadata(dateAdded: facts.dateAdded, size: facts.size)
        if let data = ExtendedAttributes.get("com.apple.metadata:kMDItemWhereFroms", atPath: path) {
            metadata.downloadDomain = ExtractionAnalysis.downloadDomain(whereFroms: ExtractionAnalysis.whereFroms(data))
        }
        if let status = FileSystem.status(atPath: path), status.identity.birth > 0 {
            metadata.creationDate = Date(timeIntervalSince1970: Double(status.identity.birth) / 1e9)
        }
        if let screenshot = screenshotDetector.detect(path: path, name: name) {
            metadata.isScreenshot = true
            metadata.captureDate = screenshot.captureDateValue
                ?? screenshot.captureDate.map { DateValue(date: $0, timeZone: timeZone) }
            if let captured = screenshot.captureDate ?? screenshot.captureDateValue?.date(in: timeZone) {
                metadata.appAtCapture = timeline?.app(at: captured)
            }
        }

        var content = ExtractedContent.empty
        var isMetadataOnly = metadataOnly != nil
        if !isMetadataOnly, let ext = FileExtension.typeKey(name), let reader = readers.first(where: { $0.canRead(extension: ext) }) {
            do {
                content = try await reader.read(url: URL(fileURLWithPath: path), options: options)
                if content.passwordProtected { isMetadataOnly = true }
            } catch {
                isMetadataOnly = true
            }
        }
        let text = content.text
        let language = detectLanguage(text)
        let candidates = DateCandidateParser.candidates(in: text, language: language)
        return ExtractionResult(
            content: content, metadata: metadata, language: language, candidates: candidates,
            titleLine: ExtractionAnalysis.titleLine(content.lines),
            strippedOriginal: GenericNameDetector().strippedOriginal(name), metadataOnly: isMetadataOnly
        )
    }
}

extension DateValue {
    /// The absolute time of this date in a time zone (midnight when there is no time).
    public func date(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour ?? 0, minute: minute ?? 0))
    }
}

/// Plain text, Markdown and HTML, without platform frameworks.
public struct PlainTextReader: ContentReader {
    public init() {}

    public func canRead(extension ext: String) -> Bool {
        ["txt", "md", "markdown", "html", "htm"].contains(ext)
    }

    public func read(url: URL, options: ReadOptions) async throws -> ExtractedContent {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_576) ?? Data()
        var text = String(decoding: data, as: UTF8.self)
        if ["html", "htm"].contains(url.pathExtension.lowercased()) { text = Self.stripHTML(text) }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.map { RecognizedLine(text: String($0)) }
        // A Markdown heading is the title line.
        if let heading = lines.first(where: { $0.text.hasPrefix("#") }) {
            let title = RecognizedLine(text: heading.text.drop { $0 == "#" || $0 == " " }.description, height: 1)
            return ExtractedContent(lines: [title] + lines.filter { $0 != heading })
        }
        return ExtractedContent(lines: lines)
    }

    static func stripHTML(_ html: String) -> String {
        var text = html
        for tag in ["script", "style", "head"] {
            while let start = text.range(of: "<\(tag)", options: .caseInsensitive),
                  let end = text.range(of: "</\(tag)>", options: .caseInsensitive, range: start.upperBound..<text.endIndex) {
                if tag == "head", let title = text[start.lowerBound..<end.upperBound].range(of: "<title>", options: .caseInsensitive),
                   let titleEnd = text[title.upperBound..<end.upperBound].range(of: "</title>", options: .caseInsensitive) {
                    let titleText = String(text[title.upperBound..<titleEnd.lowerBound])
                    text.replaceSubrange(start.lowerBound..<end.upperBound, with: titleText + "\n")
                } else {
                    text.replaceSubrange(start.lowerBound..<end.upperBound, with: " ")
                }
            }
        }
        for block in ["</p>", "<br>", "<br/>", "<br />", "</div>", "</h1>", "</h2>", "</h3>", "</li>", "</tr>", "</title>"] {
            text = text.replacingOccurrences(of: block, with: "\n", options: .caseInsensitive)
        }
        var result = ""
        var inTag = false
        for character in text {
            if character == "<" { inTag = true; continue }
            if character == ">" { inTag = false; continue }
            if !inTag { result.append(character) }
        }
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
        for (entity, value) in entities { result = result.replacingOccurrences(of: entity, with: value) }
        return result
    }
}
