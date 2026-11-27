import Foundation
import Testing
@testable import NomenCore

/// H1, H3, H4, G4, J4 and determinism of the formatter.
struct FormatterPropertyTests {
    // MARK: Random styles and fields

    static func randomStyle(_ g: inout SeededGenerator) -> NamingStyle {
        var style = NamingStyle()
        var kinds: [TokenKind] = [.date, .kind, .source, .subject, .app, .original]
        kinds.shuffle(using: &g)
        let count = Int.random(in: 1...kinds.count, using: &g)
        var template = kinds.prefix(count).map { TemplateToken($0, required: Bool.random(using: &g)) }
        if !template.contains(where: { $0.kind != .date }) { template.append(.subject(required: true)) }
        if Int.random(in: 0..<4, using: &g) == 0 {
            let texts = ["ACME", "ACME_", "Projekt X", "★ Notes", "2026", "東京", "a/b:c", "\u{202E}evil"]
            template.insert(.text(texts.randomElement(using: &g)!), at: Int.random(in: 0...template.count, using: &g))
        }
        style.template = template
        style.screenshotTemplate = template.shuffled(using: &g)
        style.partSeparator = PartSeparator.allCases.randomElement(using: &g)!
        style.caseMode = CaseMode.allCases.randomElement(using: &g)!
        style.wordSeparator = style.caseMode.forcesNoWordSeparator ? .none
            : [WordSeparator.space, .hyphen, .underscore, .dot].randomElement(using: &g)!
        style.dateFormat = DateFormat.allCases.randomElement(using: &g)!
        style.timeFormat = style.dateFormat.hasDay ? TimeFormat.allCases.randomElement(using: &g)! : .off
        style.maxLength = Int.random(in: 20...150, using: &g)
        style.subjectWords = Int.random(in: 1...12, using: &g)
        style.nameLanguage = Bool.random(using: &g) ? nil : NameLanguage.allCases.randomElement(using: &g)
        style.characters = CharacterOptions(
            removeAccents: Bool.random(using: &g), asciiOnly: Int.random(in: 0..<5, using: &g) == 0,
            windowsSafe: Bool.random(using: &g), allowEmoji: Bool.random(using: &g)
        )
        style.extensionCase = Bool.random(using: &g) ? .keep : .lowercase
        style.vocabulary = Bool.random(using: &g) ? WordLists.builtInVocabulary : [VocabularyRule(from: "bill", to: "Invoice"), VocabularyRule(from: "mobile", to: "Mobile Phone")]
        style.neverInclude = Bool.random(using: &g) ? [] : [["acme", "secret", "subscription", "Straße", "iphone"].randomElement(using: &g)!]
        style.removeFillerWords = Bool.random(using: &g)
        return style
    }

    static func randomFields(_ g: inout SeededGenerator) -> NameFields {
        func text() -> String? {
            switch Int.random(in: 0..<6, using: &g) {
            case 0: return nil
            case 1: return g.troublesomeString(maxLength: 80)
            case 2: return String(repeating: g.word() + " ", count: Int.random(in: 1...40, using: &g))
            default: return g.phrase(maxWords: 8)
            }
        }
        let kinds: [KindRef] = BuiltInKind.allCases.map { .builtIn($0) } + [.other, .custom(id: "c1"), .custom(id: "missing")]
        var date: DateValue?
        if Int.random(in: 0..<5, using: &g) > 0 {
            let hasTime = Bool.random(using: &g)
            date = DateValue(year: Int.random(in: 1990...2099, using: &g), month: Int.random(in: 1...12, using: &g),
                             day: Int.random(in: 1...28, using: &g),
                             hour: hasTime ? Int.random(in: 0...23, using: &g) : nil,
                             minute: hasTime ? Int.random(in: 0...59, using: &g) : nil)
        }
        return NameFields(kind: kinds.randomElement(using: &g)!, source: text(), subject: text() ?? "", date: date,
                          dateSource: .content, app: text(), original: text())
    }

    static func randomContext(_ g: inout SeededGenerator) -> FormatContext {
        let extensions: [String?] = [nil, "pdf", "PDF", "JPG", "tar.gz", "TAR.BZ2", "docx", "key", "001", "HEIC"]
        return FormatContext(
            language: NameLanguage.allCases.randomElement(using: &g)!,
            customKinds: [CustomKind(id: "c1", label: "Kontrakt Spezial")],
            fileExtension: extensions.randomElement(using: &g)!,
            isScreenshot: Bool.random(using: &g),
            collisionNumber: Bool.random(using: &g) ? nil : Int.random(in: 2...99, using: &g)
        )
    }

    /// Checks every guarantee a formatted name must meet.
    static func violations(_ name: FormattedName, style: NamingStyle, context: FormatContext) -> [String] {
        var problems: [String] = []
        if !Sanitizer.isValidFileName(name.fileName, windowsSafe: style.characters.windowsSafe) { problems.append("invalid file name") }
        if name.base.isEmpty { problems.append("empty base") }
        if name.base.count > style.maxLength { problems.append("base longer than max length (\(name.base.count) > \(style.maxLength))") }
        if name.fileName.utf8.count > 255 { problems.append("more than 255 bytes") }
        if let last = name.base.last, Sanitizer.separatorCharacters.contains(last) { problems.append("ends with a separator") }
        if let first = name.base.first, Sanitizer.separatorCharacters.contains(first) { problems.append("starts with a separator") }
        let expectedExt = FileExtension.render(context.fileExtension, case: style.extensionCase)
        if let ext = expectedExt {
            if !name.fileName.hasSuffix("." + ext) { problems.append("extension not preserved") }
        } else if name.fileName != name.base {
            problems.append("extension added")
        }
        if let n = context.collisionNumber, !name.base.hasSuffix(style.suffixSeparator + String(n)) {
            problems.append("collision suffix missing")
        }
        if style.characters.asciiOnly, !name.base.unicodeScalars.allSatisfy(\.isASCII) { problems.append("non-ASCII with ASCII only") }
        if !style.characters.allowEmoji, name.base.contains(where: { $0.isEmojiGrapheme }) { problems.append("emoji not allowed") }
        let banned = NeverInclude(style.neverInclude)
        if banned.containsBannedWord(name.base) { problems.append("never-include word present") }
        return problems
    }

    // MARK: H1 / H3

    /// H1: 1,000,000 random combinations of style options and fields produce valid names.
    /// H3: no base name exceeds the max length (including any suffix), and none ends with a separator.
    @Test func millionRandomCombinationsProduceValidNames() {
        var g = SeededGenerator(seed: 0x4831_4831)
        var checked = 0
        for _ in 0..<1_000_000 {
            let style = Self.randomStyle(&g)
            guard StyleValidator.isValid(style) else { continue }
            let fields = Self.randomFields(&g)
            let context = Self.randomContext(&g)
            let name = NameFormatter.format(fields, style: style, context: context)
            let problems = Self.violations(name, style: style, context: context)
            if !problems.isEmpty {
                Issue.record("\(problems) for \(name.fileName) — style \(style.caseMode) \(style.partSeparator) max \(style.maxLength)")
                return
            }
            checked += 1
        }
        #expect(checked >= 900_000)
    }

    @Test func formattingIsDeterministic() {
        var g = SeededGenerator(seed: 99)
        for _ in 0..<5_000 {
            let style = Self.randomStyle(&g)
            let fields = Self.randomFields(&g)
            let context = Self.randomContext(&g)
            #expect(NameFormatter.format(fields, style: style, context: context) == NameFormatter.format(fields, style: style, context: context))
        }
    }

    // MARK: H4

    static let fullFields = NameFields(
        kind: .builtIn(.bookingConfirmation), source: "Swiss International Air Lines",
        subject: "flight zurich lisbon return december holidays", date: DateValue(year: 2026, month: 11, day: 27, hour: 14, minute: 5),
        dateSource: .content, app: "Microsoft Outlook", original: "travel documents final"
    )

    static func allOptionalStyle(maxLength: Int) -> NamingStyle {
        var style = Presets.clean
        style.template = [.date(), .original(), .text("TRIP"), .app(), .source(), .kind(), .subject(required: true)]
        style.timeFormat = .dotted
        style.maxLength = maxLength
        style.subjectWords = 6
        return style
    }

    @Test func dropsOptionalTokensInTheSpecifiedOrder() {
        let order: [TokenKind] = [.original, .text, .app, .source, .kind, .date]
        var previous: [TokenKind] = []
        for maxLength in stride(from: 150, through: 20, by: -1) {
            let style = Self.allOptionalStyle(maxLength: maxLength)
            let name = NameFormatter.format(Self.fullFields, style: style, context: FormatContext(fileExtension: "pdf"))
            let dropped = name.droppedTokens.filter { order.contains($0) }
            // Dropped tokens always form a prefix of the order.
            #expect(dropped == Array(order.prefix(dropped.count)), "max \(maxLength): \(dropped)")
            // Shorter limits never bring a dropped token back.
            #expect(previous.allSatisfy { dropped.contains($0) }, "max \(maxLength)")
            previous = dropped
            #expect(name.base.count <= maxLength)
        }
    }

    @Test func trimsSubjectWordsBeforeTouchingRequiredTokens() {
        var style = Presets.clean
        style.template = [.date(required: true), .kind(required: true), .subject(required: true)]
        style.maxLength = 40
        style.subjectWords = 12
        let name = NameFormatter.format(Self.fullFields, style: style, context: FormatContext(fileExtension: "pdf"))
        // Date and the full kind stay; the subject loses words from the end.
        #expect(name.base.hasPrefix("2026-11-27 Booking Confirmation Flight"))
        #expect(name.base.count <= 40)
    }

    @Test func trimsWordsFromTheLongestNonDateTokenThenCutsCharacters() {
        var style = Presets.clean
        style.template = [.date(required: true), .source(required: true), .subject(required: true)]
        style.maxLength = 30
        let name = NameFormatter.format(Self.fullFields, style: style, context: FormatContext(fileExtension: "pdf"))
        #expect(name.base == "2026-11-27 Swiss Flight")
        style.maxLength = 20
        let shorter = NameFormatter.format(Self.fullFields, style: style, context: FormatContext(fileExtension: "pdf"))
        #expect(shorter.base.hasPrefix("2026-11-27 "))
        #expect(shorter.base.count <= 20)
    }

    @Test func datesAreNeverCut() {
        var g = SeededGenerator(seed: 4)
        for _ in 0..<20_000 {
            let style = Self.randomStyle(&g)
            guard StyleValidator.isValid(style), style.template.contains(where: { $0.kind == .date }) else { continue }
            var fields = Self.randomFields(&g)
            fields.date = DateValue(year: 2026, month: 11, day: 27)
            let context = Self.randomContext(&g)
            let name = NameFormatter.format(fields, style: style, context: context)
            guard let datePart = name.parts.first(where: { $0.token == .date }) else { continue }
            let language = context.language
            var rendered = DateRenderer.words(fields.date!, format: style.dateFormat, time: .off, language: language)
            if style.caseMode == .uppercase { rendered = rendered.map { $0.uppercased() } }
            if style.caseMode == .lowercase { rendered = rendered.map { $0.lowercased() } }
            let digits = rendered.joined().filter(\.isNumber)
            let dateDigits = datePart.text.filter { $0.isNumber }
            #expect(dateDigits.hasPrefix(digits), "\(datePart.text) vs \(rendered)")
        }
    }

    @Test func timeIsDroppedBeforeTheDateWouldBeCut() {
        var style = Presets.clean
        style.template = [.date(required: true), .subject(required: true)]
        style.dateFormat = .dayMonthNameYear
        style.timeFormat = .dotted
        style.partSeparator = .spacedEnDash
        style.maxLength = 20
        let fields = NameFields(subject: "x", date: DateValue(year: 2026, month: 11, day: 27, hour: 14, minute: 5))
        let name = NameFormatter.format(fields, style: style, context: FormatContext(language: .korean, collisionNumber: 99))
        #expect(name.base.count <= 20)
        #expect(name.base.contains("2026년 11월 27일"))
    }

    // MARK: G4

    /// G4: never-include words never appear, in any token or casing.
    @Test func neverIncludeWordsNeverAppear() {
        var g = SeededGenerator(seed: 0x4734)
        let candidates = ["acme", "Swisscom", "invoice", "subscription", "secret", "iphone", "straße", "東京", "réservation"]
        for _ in 0..<50_000 {
            var style = Self.randomStyle(&g)
            style.neverInclude = Array(candidates.shuffled(using: &g).prefix(Int.random(in: 1...3, using: &g)))
            style.template.append(.text("ACME Straße"))
            guard StyleValidator.isValid(style) else { continue }
            var fields = Self.randomFields(&g)
            fields.subject = "ACME-Corp invoice Swisscom's subscription SECRET Straße 東京 Réservation " + fields.subject
            fields.source = "acme"
            fields.app = "Swisscom App"
            let context = Self.randomContext(&g)
            let name = NameFormatter.format(fields, style: style, context: context)
            let parts = NeverInclude.parts(name.base.lowercased())
            for banned in style.neverInclude {
                for key in NeverInclude.parts(banned) {
                    #expect(!parts.contains(key), "“\(banned)” in \(name.base)")
                }
            }
        }
    }

    // MARK: J4

    @Test(arguments: [
        ("IMG_1234.JPG", ExtensionCase.keep, "JPG"),
        ("IMG_1234.JPG", .lowercase, "jpg"),
        ("backup.tar.gz", .keep, "tar.gz"),
        ("BACKUP.TAR.GZ", .keep, "TAR.GZ"),
        ("BACKUP.TAR.GZ", .lowercase, "tar.gz"),
        ("data.tar.zst", .keep, "tar.zst"),
        ("logs.tar.xz", .keep, "tar.xz"),
        ("old.tar.bz2", .keep, "tar.bz2"),
        ("archive.001", .keep, "001"),
        ("Keynote.key", .keep, "key"),
    ])
    func extensionsArePreserved(name: String, extensionCase: ExtensionCase, expected: String) {
        let split = FileExtension.split(name)
        var style = Presets.clean
        style.extensionCase = extensionCase
        let formatted = NameFormatter.format(PresetTests.referenceFields, style: style,
                                             context: FormatContext(fileExtension: split.extension))
        #expect(formatted.fileName.hasSuffix("." + expected))
        #expect(formatted.fileName == formatted.base + "." + expected)
    }

    @Test(arguments: ["README", "Report v1.2", "notes.", "photo.jpeg copy", "x.toolongextension123"])
    func namesWithoutAnExtensionStayWithoutOne(name: String) {
        let split = FileExtension.split(name)
        #expect(split.extension == nil)
        let formatted = NameFormatter.format(PresetTests.referenceFields, style: Presets.clean,
                                             context: FormatContext(fileExtension: split.extension))
        #expect(formatted.fileName == formatted.base)
        #expect(!formatted.fileName.contains("."))
    }

    // MARK: Fallback

    @Test func emptyNameBecomesFileInTheNameLanguage() {
        var style = Presets.clean
        style.template = [.subject(required: true)]
        let empty = NameFields(subject: "")
        #expect(NameFormatter.format(empty, style: style, context: FormatContext(language: .german, fileExtension: "pdf")).fileName == "Datei.pdf")
        #expect(NameFormatter.format(empty, style: style, context: FormatContext(language: .japanese, fileExtension: "pdf")).fileName == "ファイル.pdf")
        style.characters.asciiOnly = true
        #expect(NameFormatter.format(empty, style: style, context: FormatContext(language: .japanese, fileExtension: "pdf")).fileName == "File.pdf")
        style.characters.asciiOnly = false
        style.neverInclude = ["datei"]
        #expect(NameFormatter.format(empty, style: style, context: FormatContext(language: .german, fileExtension: "pdf")).fileName == "File.pdf")
    }

    @Test func otherKindRendersNothingAndCountsAsMissingWhenRequired() {
        var style = Presets.clean
        style.template = [.date(required: true), .kind(required: true), .subject(required: true)]
        let fields = NameFields(kind: .other, subject: "beach sunset", date: DateValue(year: 2026, month: 11, day: 27))
        let name = NameFormatter.format(fields, style: style, context: FormatContext(fileExtension: "png"))
        #expect(name.fileName == "2026-11-27 Beach Sunset.png")
        #expect(name.missingRequiredTokens == [.kind])
    }

    @Test func subjectWordsRepeatingKindOrSourceAreRemoved() {
        let fields = NameFields(kind: .builtIn(.invoice), source: "Swisscom", subject: "Swisscom invoice mobile plan",
                                date: DateValue(year: 2026, month: 11, day: 27))
        let name = NameFormatter.format(fields, style: Presets.clean, context: FormatContext(fileExtension: "pdf"))
        #expect(name.fileName == "2026-11-27 Swisscom Invoice Mobile Plan.pdf")
    }

    @Test func vocabularyAppliesToSourceSubjectAndKind() {
        var style = Presets.clean
        style.vocabulary = [VocabularyRule(from: "Bill", to: "Invoice"), VocabularyRule(from: "Rechnung", to: "Faktura")]
        let fields = NameFields(kind: .builtIn(.invoice), source: "Swisscom", subject: "phone bill november",
                                date: DateValue(year: 2026, month: 11, day: 27))
        let english = NameFormatter.format(fields, style: style, context: FormatContext(fileExtension: "pdf"))
        #expect(english.fileName == "2026-11-27 Swisscom Invoice Phone November.pdf")
        let german = NameFormatter.format(fields, style: style, context: FormatContext(language: .german, fileExtension: "pdf"))
        #expect(german.fileName == "2026-11-27 Swisscom Faktura Phone Invoice November.pdf")
    }
}
