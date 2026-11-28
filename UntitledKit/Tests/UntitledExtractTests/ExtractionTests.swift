import Foundation
import Testing
@testable import UntitledExtract
import UntitledCore
import UntitledFS
import UntitledModel

private func temporaryFile(_ name: String, _ contents: String) -> String {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("untitled-extract-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent(name).path
    _ = FileManager.default.createFile(atPath: path, contents: Data(contents.utf8))
    return path
}

struct ExtractionTests {
    @Test func titleLineIsTheTallestLine() {
        let lines = [RecognizedLine(text: "Page 1", height: 0.01), RecognizedLine(text: "Flight booking", height: 0.06),
                     RecognizedLine(text: "Passenger details", height: 0.03)]
        #expect(ExtractionAnalysis.titleLine(lines) == "Flight booking")
        #expect(ExtractionAnalysis.titleLine([RecognizedLine(text: "12"), RecognizedLine(text: "Invoice November")]) == "Invoice November")
    }

    @Test func languageGuess() {
        #expect(LanguageGuesser.guess("Rechnung für die Wohnung und das Auto, Betrag fällig") == .german)
        #expect(LanguageGuesser.guess("Facture pour le mois de novembre, montant à payer et la date") == .french)
        #expect(LanguageGuesser.guess("Your invoice for the month and the total amount") == .english)
        #expect(LanguageGuesser.guess("請求書のお知らせ、ご確認ください") == .japanese)
        #expect(LanguageGuesser.guess("청구서 안내 드립니다") == .korean)
        #expect(LanguageGuesser.guess("12345") == nil)
    }

    @Test func plainTextMarkdownAndHTML() async throws {
        let markdown = temporaryFile("notes.md", "Intro line\n# Lisbon trip plan\nDay 1 museum\n")
        let content = try await PlainTextReader().read(url: URL(fileURLWithPath: markdown), options: ReadOptions())
        #expect(content.lines.first?.text == "Lisbon trip plan")
        let html = temporaryFile("page.html", "<html><head><title>Order 42 shipped</title><style>p{}</style></head><body><p>Your parcel &amp; receipt</p><script>evil()</script></body></html>")
        let page = try await PlainTextReader().read(url: URL(fileURLWithPath: html), options: ReadOptions())
        #expect(page.text.contains("Order 42 shipped"))
        #expect(page.text.contains("Your parcel & receipt"))
        #expect(!page.text.contains("evil") && !page.text.contains("p{}"))
    }

    @Test func downloadDomainFromWhereFroms() throws {
        let path = temporaryFile("statement.pdf", "%PDF")
        let plist = try PropertyListSerialization.data(fromPropertyList: ["https://www.swisscom.ch/bill/123.pdf", "https://www.swisscom.ch/"], format: .binary, options: 0)
        try ExtendedAttributes.set("com.apple.metadata:kMDItemWhereFroms", data: plist, atPath: path)
        #expect(ExtractionAnalysis.downloadDomain(whereFroms: ExtractionAnalysis.whereFroms(plist)) == "www.swisscom.ch")
        #expect(ExtractionAnalysis.downloadDomain(whereFroms: ["https://mail.google.com/mail/u/0", "https://bank.example/doc"]) == "bank.example")
    }

    @Test func extractorBuildsEvidence() async throws {
        let path = temporaryFile("download.txt", "SWISSCOM INVOICE\nInvoice date 27 November 2026\nMobile subscription\n")
        let plist = try PropertyListSerialization.data(fromPropertyList: ["https://www.swisscom.ch/x"], format: .binary, options: 0)
        try ExtendedAttributes.set("com.apple.metadata:kMDItemWhereFroms", data: plist, atPath: path)
        let facts = FileFacts(name: "download.txt", dateAdded: Date(timeIntervalSince1970: 1_790_000_000), size: 60)
        let result = await Extractor(readers: [PlainTextReader()]).extract(path: path, facts: facts, metadataOnly: nil, options: ReadOptions())
        #expect(result.metadata.downloadDomain == "www.swisscom.ch")
        #expect(result.candidates.map(\.value) == [DateValue(year: 2026, month: 11, day: 27)])
        #expect(result.titleLine == "SWISSCOM INVOICE")
        #expect(!result.metadataOnly)
        let evidence = result.evidence(timeZone: TimeZone(identifier: "UTC")!)
        #expect(evidence.textCharacterCount >= 20)
        #expect(result.contentLines.contains { $0.hasDateCandidate })
        let metadataOnly = await Extractor(readers: [PlainTextReader()]).extract(path: path, facts: facts, metadataOnly: .dataless, options: ReadOptions())
        #expect(metadataOnly.metadataOnly && metadataOnly.content.lines.isEmpty)
    }

    /// E5 (logic): the app at capture time is right for 50 scripted screenshots taken while
    /// switching apps, with the file written seconds after capture.
    @Test func appAtCaptureTime() async {
        let timeline = AppTimeline()
        let apps = ["Safari", "Mail", "Xcode", "Notes", "Finder"]
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var expected: [(Date, String)] = []
        for index in 0..<50 {
            let switchTime = start.addingTimeInterval(Double(index) * 10)
            let app = apps[index % apps.count]
            timeline.record(app: app, at: switchTime)
            let capture = switchTime.addingTimeInterval(3)
            expected.append((capture, app))
            // With the floating thumbnail, the file appears ~5 s later, after the next switch.
            timeline.record(app: apps[(index + 1) % apps.count], at: capture.addingTimeInterval(4))
        }
        #expect(expected.count == 50)
        for (capture, app) in expected {
            #expect(timeline.app(at: capture) == app)
        }
        // Entries older than ten minutes are forgotten.
        timeline.record(app: "Late", at: start.addingTimeInterval(2_000))
        #expect(timeline.app(at: start.addingTimeInterval(10)) == nil)
    }

    @Test func screenshotNamesGiveCaptureTimeAndApp() async throws {
        let zone = TimeZone(identifier: "Europe/Zurich")!
        let timeline = AppTimeline()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let switchTime = calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 14, minute: 4))!
        timeline.record(app: "Safari", at: switchTime)
        timeline.record(app: "Finder", at: switchTime.addingTimeInterval(80))
        let name = "Screenshot 2026-11-27 at 14.05.00.png"
        let path = temporaryFile(name, "png bytes")
        let facts = FileFacts(name: name, size: 9)
        let extractor = Extractor(readers: [], screenshotDetector: NameScreenshotDetector(timeZone: zone), timeline: timeline, timeZone: zone)
        let result = await extractor.extract(path: path, facts: facts, metadataOnly: nil, options: ReadOptions())
        #expect(result.metadata.isScreenshot)
        #expect(result.metadata.captureDate == DateValue(year: 2026, month: 11, day: 27, hour: 14, minute: 5))
        #expect(result.metadata.appAtCapture == "Safari")
        #expect(result.strippedOriginal == nil)
    }
}
