public import Foundation
public import UntitledCore
public import UntitledModel

/// A recognized line of text with its height, for finding the title line (3.7).
public struct RecognizedLine: Sendable, Hashable {
    public var text: String
    /// Relative height (0…1 of the page or image); nil when unknown.
    public var height: Double?

    public init(text: String, height: Double? = nil) {
        self.text = text
        self.height = height
    }
}

/// What reading a file produced. Held in memory only and discarded after the proposal (3.7, 3.18).
public struct ExtractedContent: Sendable {
    public var lines: [RecognizedLine]
    public var labels: [ImageLabel]
    public var pageCount: Int?
    public var isScan: Bool
    public var image: PromptImage?
    public var passwordProtected: Bool

    public init(lines: [RecognizedLine] = [], labels: [ImageLabel] = [], pageCount: Int? = nil, isScan: Bool = false,
                image: PromptImage? = nil, passwordProtected: Bool = false) {
        self.lines = lines
        self.labels = labels
        self.pageCount = pageCount
        self.isScan = isScan
        self.image = image
        self.passwordProtected = passwordProtected
    }

    public var text: String { lines.map(\.text).joined(separator: "\n") }

    public static let empty = ExtractedContent()
}

/// Metadata read for every file (3.7 "All files").
public struct FileMetadata: Sendable, Hashable {
    public var downloadDomain: String?
    public var dateAdded: Date?
    public var creationDate: Date?
    public var captureDate: DateValue?
    public var isScreenshot: Bool
    public var appAtCapture: String?
    public var size: Int64

    public init(downloadDomain: String? = nil, dateAdded: Date? = nil, creationDate: Date? = nil, captureDate: DateValue? = nil,
                isScreenshot: Bool = false, appAtCapture: String? = nil, size: Int64 = 0) {
        self.downloadDomain = downloadDomain
        self.dateAdded = dateAdded
        self.creationDate = creationDate
        self.captureDate = captureDate
        self.isScreenshot = isScreenshot
        self.appAtCapture = appAtCapture
        self.size = size
    }
}

/// Reads one kind of file.
public protocol ContentReader: Sendable {
    func canRead(extension: String) -> Bool
    func read(url: URL, options: ReadOptions) async throws -> ExtractedContent
}

public struct ReadOptions: Sendable, Hashable {
    public var pdfPages: Int
    public var includeImageForModel: Bool

    public init(pdfPages: Int = Defaults.pdfPagesRead, includeImageForModel: Bool = false) {
        self.pdfPages = min(max(pdfPages, Defaults.pdfPagesRange.lowerBound), Defaults.pdfPagesRange.upperBound)
        self.includeImageForModel = includeImageForModel
    }
}

/// Everything later stages need from a file: the evidence for validation and the lines for
/// the prompt and Basic naming.
public struct ExtractionResult: Sendable {
    public var content: ExtractedContent
    public var metadata: FileMetadata
    public var language: NameLanguage?
    public var candidates: [DateCandidate]
    public var titleLine: String?
    public var strippedOriginal: String?
    public var metadataOnly: Bool

    /// Lines for the prompt, flagged for budget trimming (3.8).
    public var contentLines: [ContentLine] {
        let tallest = content.lines.compactMap(\.height).max() ?? 0
        let snippets = candidates.map(\.snippet)
        return content.lines.map { line in
            ContentLine(text: line.text,
                        isTitleSized: line.text == titleLine || (tallest > 0 && (line.height ?? 0) >= tallest * 0.8),
                        hasDateCandidate: snippets.contains { line.text.contains($0) })
        }
    }

    /// Evidence for validation (3.9).
    public func evidence(timeZone: TimeZone) -> Evidence {
        Evidence(
            text: content.text,
            downloadDomain: metadata.downloadDomain,
            appName: metadata.appAtCapture,
            dateCandidates: candidates,
            captureDate: metadata.captureDate,
            dateAdded: metadata.dateAdded.map { DateValue(date: $0, timeZone: timeZone, includeTime: false) },
            creationDate: metadata.creationDate.map { DateValue(date: $0, timeZone: timeZone, includeTime: false) },
            isScreenshot: metadata.isScreenshot,
            topLabelConfidence: content.labels.map(\.confidence).max(),
            titleLine: titleLine,
            metadataOnly: metadataOnly
        )
    }

    public var basicInput: BasicInput {
        BasicInput(lines: contentLines, titleLine: titleLine, downloadDomain: metadata.downloadDomain, app: metadata.appAtCapture,
                   candidates: candidates, labels: content.labels, fileExtension: nil, isScreenshot: metadata.isScreenshot,
                   isScan: content.isScan, strippedOriginal: strippedOriginal)
    }
}

public enum ExtractionAnalysis {
    /// The tallest recognized line; without heights, the first line with at least three letters (3.7).
    public static func titleLine(_ lines: [RecognizedLine]) -> String? {
        let meaningful = lines.filter { $0.text.filter(\.isLetter).count >= 3 }
        if let tallest = meaningful.filter({ $0.height != nil }).max(by: { ($0.height ?? 0) < ($1.height ?? 0) }) {
            return tallest.text.trimmingCharacters(in: .whitespaces)
        }
        return meaningful.first?.text.trimmingCharacters(in: .whitespaces)
    }

    /// The download domain from the "where from" metadata macOS records for downloads.
    public static func downloadDomain(whereFroms: [String]) -> String? {
        for value in whereFroms {
            guard let url = URL(string: value), let host = url.host, !host.isEmpty else { continue }
            if host.hasSuffix("mail.google.com") || host.hasSuffix("outlook.live.com") { continue }
            return host.lowercased()
        }
        return nil
    }

    /// Decodes `com.apple.metadata:kMDItemWhereFroms` (a property list array of strings).
    public static func whereFroms(_ data: Data) -> [String] {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String]) ?? []
    }
}

/// A portable language guess from common words and scripts, used when the NaturalLanguage
/// framework is unavailable (Linux tests). The app uses NLLanguageRecognizer.
public enum LanguageGuesser {
    static let markers: [NameLanguage: Set<String>] = [
        .english: ["the", "and", "of", "to", "your", "invoice", "with", "for", "is", "date", "total", "amount"],
        .german: ["der", "die", "und", "das", "ist", "nicht", "mit", "sie", "rechnung", "datum", "betrag", "für"],
        .french: ["le", "la", "les", "et", "des", "est", "pour", "vous", "facture", "date", "montant", "une"],
        .italian: ["il", "di", "che", "e", "per", "una", "sono", "fattura", "importo", "della", "gli", "non"],
        .spanish: ["el", "de", "que", "y", "los", "las", "para", "factura", "importe", "una", "por", "con"],
        .portuguese: ["o", "de", "que", "e", "os", "para", "uma", "fatura", "valor", "não", "com", "do"],
        .dutch: ["de", "het", "een", "en", "van", "is", "niet", "factuur", "bedrag", "voor", "met", "uw"],
    ]

    public static func guess(_ text: String) -> NameLanguage? {
        var kana = 0, han = 0, hangul = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF: kana += 1
            case 0x4E00...0x9FFF: han += 1
            case 0xAC00...0xD7AF: hangul += 1
            default: break
            }
        }
        if hangul > 3 { return .korean }
        if kana > 3 { return .japanese }
        if han > 3 { return .chineseSimplified }
        let words = WordTokenizer.words(text.lowercased()).prefix(2_000)
        var scores: [NameLanguage: Int] = [:]
        for word in words {
            for (language, set) in markers where set.contains(word) { scores[language, default: 0] += 1 }
        }
        guard let best = scores.max(by: { $0.value == $1.value ? $0.key.rawValue > $1.key.rawValue : $0.value < $1.value }), best.value >= 2 else {
            return nil
        }
        return best.key
    }
}
