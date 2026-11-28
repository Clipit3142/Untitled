import Foundation
import Testing
@testable import UntitledExtract
import UntitledCore
import UntitledFS
#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import ImageIO
import UniformTypeIdentifiers
#endif

/// The fixtures carry the key phrase "Alpine Ledger" (built by make_fixtures.py).
enum Fixtures {
    static let phrase = "alpine ledger"

    static var directory: URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    }

    static func path(_ name: String) -> String { directory.appendingPathComponent(name).path }

    static func extract(_ path: String, readers: [any ContentReader], pdfPages: Int = Defaults.pdfPagesRead) async throws -> ExtractionResult {
        let facts = try #require(FileFactsReader.read(path: path, isTopLevel: true)?.facts)
        return await Extractor(readers: readers).extract(path: path, facts: facts, metadataOnly: nil, options: ReadOptions(pdfPages: pdfPages))
    }

    static func text(_ result: ExtractionResult) -> String {
        result.content.lines.map(\.text).joined(separator: " ").lowercased()
    }
}

@Suite("Extraction fixtures (E1)")
struct PlainFixtureTests {
    @Test("Text, Markdown and HTML yield the key phrase on every platform", arguments: ["document.txt", "document.md", "document.html"])
    func plainText(name: String) async throws {
        let result = try await Fixtures.extract(Fixtures.path(name), readers: [PlainTextReader()])
        #expect(Fixtures.text(result).contains(Fixtures.phrase), "\(name)")
        #expect(!result.metadataOnly)
    }

    @Test("A fixture exists for every allowed type that can be generated")
    func fixturesPresent() {
        let expected = ["image.png", "image.jpg", "image.tiff", "image.gif", "image.webp", "document.pdf", "five-pages.pdf",
                        "scanned.pdf", "protected.pdf", "document.txt", "document.md", "document.html", "document.rtf",
                        "document.doc", "document.docx", "sheet.xlsx", "slides.pptx"]
        for name in expected {
            #expect(FileManager.default.fileExists(atPath: Fixtures.path(name)), "\(name)")
        }
    }
}

#if canImport(PDFKit) && canImport(Vision) && canImport(AppKit) && canImport(QuickLookThumbnailing)
@Suite("Extraction on macOS (E1, E2)")
struct AppleFixtureTests {
    @Test("Every allowed type yields text containing the key phrase", arguments: [
        "image.png", "image.jpg", "image.tiff", "image.gif", "image.webp", "document.pdf", "scanned.pdf",
        "document.txt", "document.md", "document.html", "document.rtf", "document.doc", "document.docx", "sheet.xlsx", "slides.pptx",
    ])
    func everyType(name: String) async throws {
        let result = try await Fixtures.extract(Fixtures.path(name), readers: AppleReaders.all)
        #expect(Fixtures.text(result).contains(Fixtures.phrase), "\(name): \(Fixtures.text(result).prefix(200))")
    }

    @Test("HEIC, made from the PNG fixture with ImageIO")
    func heic() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("untitled-heic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("image.heic")
        let source = try #require(CGImageSourceCreateWithURL(Fixtures.directory.appendingPathComponent("image.png") as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let destination = try #require(CGImageDestinationCreateWithURL(output as CFURL, UTType.heic.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let result = try await Fixtures.extract(output.path, readers: AppleReaders.all)
        #expect(Fixtures.text(result).contains(Fixtures.phrase))
    }

    @Test("Pages, Numbers and Keynote fixtures yield the key phrase")
    func iWork() async throws {
        for name in ["document.pages", "sheet.numbers", "slides.key"] {
            let path = Fixtures.directory.appendingPathComponent("iwork").appendingPathComponent(name).path
            guard FileManager.default.fileExists(atPath: path) else {
                Issue.record("Missing \(name): save it from the app into Tests/UntitledExtractTests/Fixtures/iwork/ with the text “Alpine Ledger”.")
                continue
            }
            let result = try await Fixtures.extract(path, readers: AppleReaders.all)
            #expect(Fixtures.text(result).contains(Fixtures.phrase), "\(name)")
        }
    }

    @Test("Only the configured number of PDF pages is read (E2)")
    func pdfPageLimit() async throws {
        let path = Fixtures.path("five-pages.pdf")
        let two = try await Fixtures.extract(path, readers: AppleReaders.all, pdfPages: 2)
        #expect(!Fixtures.text(two).contains(Fixtures.phrase))
        #expect(two.content.pageCount == 5)
        let three = try await Fixtures.extract(path, readers: AppleReaders.all, pdfPages: 3)
        #expect(Fixtures.text(three).contains(Fixtures.phrase))
    }

    @Test("Password-protected PDFs never prompt and get metadata-only proposals (E2)")
    func protectedPDF() async throws {
        let result = try await Fixtures.extract(Fixtures.path("protected.pdf"), readers: AppleReaders.all)
        #expect(result.metadataOnly)
        #expect(result.content.lines.isEmpty)
    }
}
#endif
