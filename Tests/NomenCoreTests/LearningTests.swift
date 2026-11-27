import Foundation
import Testing
import NomenTestSupport
@testable import NomenCore

/// I1–I4 (learning from edits), H10 (example-name inference) and B5 (learn from folder).
struct LearningTests {
    static let now = Date(timeIntervalSince1970: 1_795_000_000)
    static let day: TimeInterval = 86_400

    // MARK: I1

    @Test func suggestionsNeedTwoOccurrencesWithinThirtyDays() {
        let pattern = EditPattern.wordReplaced(from: "Bill", to: "Invoice")
        var events = [EditEvent(pattern: pattern, styleID: "s", date: Self.now.addingTimeInterval(-40 * Self.day))]
        #expect(SuggestionEngine.pending(events: events, answers: SuggestionAnswers(), now: Self.now).isEmpty)
        events.append(EditEvent(pattern: pattern, styleID: "s", date: Self.now.addingTimeInterval(-1 * Self.day)))
        #expect(SuggestionEngine.pending(events: events, answers: SuggestionAnswers(), now: Self.now).isEmpty,
                "the first occurrence is outside the 30-day window")
        events.append(EditEvent(pattern: pattern, styleID: "s", date: Self.now))
        let pending = SuggestionEngine.pending(events: events, answers: SuggestionAnswers(), now: Self.now)
        #expect(pending.count == 1)
        #expect(pending.first?.question == "You changed ‘Bill’ to ‘Invoice’ twice. Always do this?")
        // Another style does not count.
        let other = [EditEvent(pattern: pattern, styleID: "a", date: Self.now), EditEvent(pattern: pattern, styleID: "b", date: Self.now)]
        #expect(SuggestionEngine.pending(events: other, answers: SuggestionAnswers(), now: Self.now).isEmpty)
    }

    // MARK: I2

    @Test func decliningEverySuggestionLeavesTheStyleByteIdentical() throws {
        var g = SeededGenerator(seed: 0x4932)
        let style = Presets.clean
        let before = try JSONEncoder.sorted.encode(style)
        var answers = SuggestionAnswers()
        var events: [EditEvent] = []
        var current = style
        let fields = PresetTests.referenceFields
        for index in 0..<500 {
            let date = Self.now.addingTimeInterval(Double(index) * 600)
            let proposed = NameFormatter.format(fields, style: current, context: PresetTests.context)
            let edits = ["2026-11-27 swisscom invoice mobile subscription november.pdf", "2026-11-27 Swisscom Bill Mobile.pdf",
                         "20261127_Swisscom_Invoice.pdf", "Swisscom Invoice 2026-11-27.pdf", "Invoice Mobile.pdf",
                         "2026-11-27 Swisscom Invoice Mobile Subscription.pdf", g.phrase(maxWords: 6) + ".pdf"]
            let final = edits.randomElement(using: &g)!
            for pattern in EditAnalyzer.patterns(proposed: proposed, final: final, style: current, language: .english) {
                events.append(EditEvent(pattern: pattern, styleID: current.id, date: date))
            }
            for suggestion in SuggestionEngine.pending(events: events, answers: answers, now: date) {
                let answer: SuggestionEngine.Answer = Bool.random(using: &g) ? .notNow : .neverAsk
                if let changed = SuggestionEngine.answer(answer, to: suggestion, answers: &answers, style: current, now: date) {
                    current = changed
                }
            }
        }
        #expect(try JSONEncoder.sorted.encode(current) == before)
    }

    // MARK: I3

    @Test func neverAskSuppressesUntilReset() {
        let pattern = EditPattern.caseChange(.lowercase)
        var events = [EditEvent(pattern: pattern, styleID: "s", date: Self.now), EditEvent(pattern: pattern, styleID: "s", date: Self.now)]
        var answers = SuggestionAnswers()
        let suggestion = SuggestionEngine.pending(events: events, answers: answers, now: Self.now)[0]
        _ = SuggestionEngine.answer(.neverAsk, to: suggestion, answers: &answers, style: Presets.clean, now: Self.now)
        for offset in 1...20 { events.append(EditEvent(pattern: pattern, styleID: "s", date: Self.now.addingTimeInterval(Double(offset) * 3_600))) }
        #expect(SuggestionEngine.pending(events: events, answers: answers, now: Self.now.addingTimeInterval(21 * 3_600)).isEmpty)
        // Reset clears learned answers.
        #expect(!SuggestionEngine.pending(events: events, answers: SuggestionAnswers(), now: Self.now.addingTimeInterval(21 * 3_600)).isEmpty)
    }

    @Test func notNowWaitsForANewOccurrence() {
        let pattern = EditPattern.fillerRemoved
        var events = [EditEvent(pattern: pattern, styleID: "s", date: Self.now), EditEvent(pattern: pattern, styleID: "s", date: Self.now)]
        var answers = SuggestionAnswers()
        let suggestion = SuggestionEngine.pending(events: events, answers: answers, now: Self.now)[0]
        _ = SuggestionEngine.answer(.notNow, to: suggestion, answers: &answers, style: Presets.clean, now: Self.now)
        #expect(SuggestionEngine.pending(events: events, answers: answers, now: Self.now).isEmpty)
        events.append(EditEvent(pattern: pattern, styleID: "s", date: Self.now.addingTimeInterval(60)))
        #expect(SuggestionEngine.pending(events: events, answers: answers, now: Self.now.addingTimeInterval(60)).count == 1)
    }

    @Test func onlyAlwaysChangesTheStyle() {
        let pattern = EditPattern.wordReplaced(from: "Bill", to: "Invoice")
        let events = [EditEvent(pattern: pattern, styleID: "s", date: Self.now), EditEvent(pattern: pattern, styleID: "s", date: Self.now)]
        var answers = SuggestionAnswers()
        let suggestion = SuggestionEngine.pending(events: events, answers: answers, now: Self.now)[0]
        let changed = SuggestionEngine.answer(.always, to: suggestion, answers: &answers, style: Presets.clean, now: Self.now)
        #expect(changed?.vocabulary.contains(VocabularyRule(from: "Bill", to: "Invoice")) == true)
        #expect(changed?.version == Presets.clean.version + 1)
    }

    // MARK: I4

    @Test func examplesKeepTwentyAndUseTheNewestFive() {
        var list = ExampleList()
        for index in 1...30 { list.add("Name \(index)") }
        #expect(list.names.count == 20)
        #expect(list.names.first == "Name 11")
        #expect(list.forPrompt == ["Name 26", "Name 27", "Name 28", "Name 29", "Name 30"])
        list.remove("Name 30")
        #expect(list.forPrompt == ["Name 25", "Name 26", "Name 27", "Name 28", "Name 29"])
        list.add("Name 12")
        #expect(list.forPrompt.last == "Name 12")
        #expect(list.names.count == 19)
    }

    // MARK: Edit analysis

    @Test func detectsEditPatterns() {
        let proposed = NameFormatter.format(PresetTests.referenceFields, style: Presets.clean, context: PresetTests.context)
        func patterns(_ final: String) -> [String] {
            EditAnalyzer.patterns(proposed: proposed, final: final, style: Presets.clean, language: .english).map(\.key)
        }
        #expect(patterns("2026-11-27 swisscom invoice mobile subscription november.pdf").contains("case:lowercase"))
        #expect(patterns("2026-11-27 Swisscom Bill Mobile Subscription November.pdf").contains("replace:invoice→bill"))
        #expect(patterns("20261127 Swisscom Invoice Mobile Subscription November.pdf").contains("dateFormat:20261127"))
        #expect(patterns("Swisscom Invoice Mobile Subscription November 2026-11-27.pdf").contains("datePosition:end"))
        #expect(patterns("2026-11-27 Invoice Mobile Subscription November.pdf").contains("removed:source"))
        #expect(patterns("2026-11-27 Swisscom Invoice.pdf").contains { $0.hasPrefix("shortened:") })
        #expect(patterns(proposed.fileName).isEmpty)
    }

    // MARK: H10 and B5

    struct InferenceCase: Sendable {
        var style: NamingStyle
        var names: [String]
    }

    static func inferenceStyles(seed: UInt64, count: Int) -> [NamingStyle] {
        var g = SeededGenerator(seed: seed)
        let separatorPairs: [(PartSeparator, WordSeparator)] = [
            (.space, .space), (.underscore, .underscore), (.hyphen, .hyphen), (.dot, .dot),
            (.spacedEnDash, .space), (.spacedHyphen, .space), (.underscore, .space),
        ]
        let templates: [[TokenKind]] = [
            [.date, .source, .kind, .subject], [.date, .kind, .subject], [.date, .subject],
            [.source, .kind, .subject, .date], [.kind, .subject, .date], [.subject, .date],
            [.kind, .subject, .source, .date], [.date, .kind, .subject, .source],
        ]
        var styles: [NamingStyle] = []
        while styles.count < count {
            var style = NamingStyle()
            let (part, word) = separatorPairs.randomElement(using: &g)!
            let tokens = templates.randomElement(using: &g)!
            let explicitParts = part == .spacedEnDash || part == .spacedHyphen
            // A source after the subject can only be told apart with explicit part separators.
            if tokens.firstIndex(of: .source).map({ $0 > tokens.firstIndex(of: .kind) ?? 0 }) == true, !explicitParts { continue }
            style.partSeparator = part
            style.wordSeparator = word
            style.caseMode = [.title, .sentence, .lowercase, .uppercase, .camel, .pascal].randomElement(using: &g)!
            if style.caseMode.forcesNoWordSeparator {
                if part == .space || explicitParts { continue }
                style.wordSeparator = .none
            }
            style.dateFormat = [.iso, .compact, .yearMonth, .dotted, .dayMonthYearDash, .monthDayYearDash, .dayMonthNameYear].randomElement(using: &g)!
            if style.dateFormat == .dayMonthNameYear, !(part == .space || explicitParts) || style.wordSeparator != .space { continue }
            style.timeFormat = style.dateFormat.hasDay && style.dateFormat != .dayMonthNameYear && Bool.random(using: &g)
                ? [.dotted, .compact].randomElement(using: &g)! : .off
            style.template = tokens.map { TemplateToken($0, required: true) }
            style.maxLength = 150
            style.subjectWords = 6
            style.vocabulary = []
            guard StyleValidator.isValid(style) else { continue }
            styles.append(style)
        }
        return styles
    }

    static func sampleNames(for style: NamingStyle, count: Int, seed: UInt64) -> [String] {
        var g = SeededGenerator(seed: seed)
        let sources = ["Swisscom", "Amazon", "Lufthansa", "Migros", "Galaxus", "Sunrise", "Helsana", "Zalando"]
        let subjects = ["mobile subscription november", "kitchen chair order", "flight zurich lisbon", "health insurance premium",
                        "electricity bill autumn", "winter jacket return", "office desk delivery", "annual tax summary"]
        let kinds: [BuiltInKind] = [.invoice, .receipt, .contract, .ticket, .report, .letter]
        return (0..<count).map { _ in
            let hasTime = style.timeFormat != .off
            let fields = NameFields(
                kind: .builtIn(kinds.randomElement(using: &g)!), source: sources.randomElement(using: &g)!,
                subject: subjects.randomElement(using: &g)!,
                date: DateValue(year: Int.random(in: 2020...2026, using: &g), month: Int.random(in: 1...12, using: &g),
                                day: Int.random(in: 13...28, using: &g), hour: hasTime ? Int.random(in: 10...23, using: &g) : nil,
                                minute: hasTime ? Int.random(in: 10...59, using: &g) : nil)
            )
            return NameFormatter.format(fields, style: style, context: FormatContext(fileExtension: "pdf")).fileName
        }
    }

    static func check(_ inferred: InferredStyle, against style: NamingStyle) -> [String] {
        var problems: [String] = []
        let hasDate = style.template.contains { $0.kind == .date }
        if hasDate, inferred.dateFormat != style.dateFormat { problems.append("date format \(String(describing: inferred.dateFormat)) ≠ \(style.dateFormat)") }
        if hasDate, inferred.timeFormat != style.timeFormat { problems.append("time \(inferred.timeFormat) ≠ \(style.timeFormat)") }
        let expectedPosition: InferredStyle.DatePosition = !hasDate ? .none : (style.template.first?.kind == .date ? .start : .end)
        if inferred.datePosition != expectedPosition { problems.append("date position \(inferred.datePosition)") }
        if inferred.partSeparator != style.partSeparator { problems.append("part separator “\(inferred.partSeparator.rawValue)” ≠ “\(style.partSeparator.rawValue)”") }
        if inferred.wordSeparator != style.wordSeparator { problems.append("word separator “\(inferred.wordSeparator.rawValue)” ≠ “\(style.wordSeparator.rawValue)”") }
        if inferred.caseMode != style.caseMode { problems.append("case \(inferred.caseMode) ≠ \(style.caseMode)") }
        if inferred.template != style.template.map(\.kind) { problems.append("template \(inferred.template) ≠ \(style.template.map(\.kind))") }
        return problems
    }

    /// H10: example-name inference is 100% correct on 50 fixture sets.
    @Test func exampleNameInferenceIsCorrectOnFiftySets() throws {
        let styles = Self.inferenceStyles(seed: 0x4831_30, count: 50)
        for (index, style) in styles.enumerated() {
            let names = Self.sampleNames(for: style, count: 3 + index % 3, seed: UInt64(index + 1))
            let inferred = try StyleInference.inferFromExamples(names)
            let problems = Self.check(inferred, against: style)
            #expect(problems.isEmpty, "set \(index): \(problems) — \(names)")
        }
    }

    /// B5: learn-from-folder is 100% correct on consistent-format fixtures, including max length.
    @Test func learnFromFolderIsCorrectOnConsistentFolders() throws {
        let styles = Self.inferenceStyles(seed: 0x4235, count: 30)
        for (index, style) in styles.enumerated() {
            let names = Self.sampleNames(for: style, count: 10 + index, seed: UInt64(1_000 + index))
            let inferred = try StyleInference.inferFromFolder(names)
            #expect(Self.check(inferred, against: style).isEmpty, "folder \(index): \(Self.check(inferred, against: style))")
            let lengths = names.map { FileExtension.split($0).base.count }.sorted()
            let p90 = lengths[Int((Double(lengths.count) * 0.9).rounded(.up)) - 1]
            let expected = min(150, max(20, Int((Double(p90) / 10).rounded(.up)) * 10))
            #expect(inferred.maxLength == expected)
        }
    }

    @Test func learnFromFolderNeedsTenFiles() {
        #expect(throws: StyleInferenceError.tooFewNames(minimum: 10, found: 9)) {
            try StyleInference.inferFromFolder(Array(repeating: "2026-11-27 Swisscom Invoice.pdf", count: 9))
        }
        #expect(throws: StyleInferenceError.tooFewNames(minimum: 3, found: 2)) {
            try StyleInference.inferFromExamples(["a b", "c d"])
        }
    }

    @Test func inferredStyleOnlyAppliesWhenAccepted() throws {
        let names = Self.sampleNames(for: Presets.kebab, count: 12, seed: 5)
        let inferred = try StyleInference.inferFromFolder(names)
        let proposed = inferred.applied(to: Presets.clean)
        #expect(proposed.partSeparator == .hyphen)
        #expect(proposed.caseMode == .lowercase)
        #expect(Presets.clean.partSeparator == .space, "the original style is untouched")
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
