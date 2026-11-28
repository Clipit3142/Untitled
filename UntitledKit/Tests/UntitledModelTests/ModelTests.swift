import Foundation
import Synchronization
import Testing
import UntitledTestSupport
@testable import UntitledModel
import UntitledCore

/// A scripted model: counts tokens as characters / 3, enforces its context size like the
/// real model, and records every call.
final class FakeGenerator: FieldGenerator {
    struct State {
        var script: [Result<GeneratedFields, ModelFailure>] = []
        var calls: [GenerationRequest] = []
        var active = 0
        var maxActive = 0
        var prewarms = 0
    }

    let state = Mutex(State())
    let context: Int
    let delay: Duration

    init(context: Int = 4_096, script: [Result<GeneratedFields, ModelFailure>] = [], delay: Duration = .zero) {
        self.context = context
        self.delay = delay
        state.withLock { $0.script = script }
    }

    static func tokens(_ text: String) -> Int { (text.utf8.count + 2) / 3 }

    func generate(_ request: GenerationRequest) async throws -> GeneratedFields {
        let scripted: Result<GeneratedFields, ModelFailure>? = state.withLock { s in
            s.calls.append(request)
            s.active += 1
            s.maxActive = max(s.maxActive, s.active)
            return s.script.isEmpty ? nil : s.script.removeFirst()
        }
        defer { state.withLock { $0.active -= 1 } }
        if delay > .zero { try await Task.sleep(for: delay) }
        let used = Self.tokens(request.instructions) + Self.tokens(request.promptText)
        if used > context { throw ModelFailure.contextSizeExceeded }
        if let scripted { return try scripted.get() }
        let first = request.content.first?.text ?? "nothing"
        return GeneratedFields(kind: .builtIn(.invoice), source: nil, subject: first, dateChoice: nil)
    }

    func tokenCount(instructions: String, prompt: String, image: PromptImage?) async throws -> Int {
        Self.tokens(instructions) + Self.tokens(prompt) + (image == nil ? 0 : 300)
    }

    func contextSize() async throws -> Int { context }
    func prewarm(instructions: String) async { state.withLock { $0.prewarms += 1 } }

    var calls: [GenerationRequest] { state.withLock { $0.calls } }
}

func request(_ lines: [ContentLine], examples: [String] = [], candidates: [DateCandidate] = []) -> GenerationRequest {
    GenerationRequest(metadata: PromptBuilder.metadata(originalName: "scan0001.pdf", downloadDomain: "swisscom.ch", app: nil,
                                                       isScreenshot: false, kindHint: "PDF", candidates: candidates, labels: []),
                      content: lines, image: nil, examples: examples,
                      schema: SchemaSpec(customKinds: [], candidates: candidates, subjectMaxWords: 5),
                      instructions: PromptBuilder.instructions(style: Presets.clean, language: .english))
}

struct SchemaAndPromptTests {
    /// F7: the schema matches the current kinds and date candidates.
    @Test func schemaMatchesKindsAndCandidates() {
        let candidates = DateCandidateParser.candidates(in: "Issued 2026-11-27, due 15.12.2026", language: .german)
        let spec = SchemaSpec(customKinds: [CustomKind(id: "w", label: "Warranty")], candidates: candidates, subjectMaxWords: 7)
        #expect(spec.kinds.count == BuiltInKind.allCases.count + 2)
        #expect(spec.kinds.first == "Invoice" && spec.kinds.last == "Other" && spec.kinds.contains("Warranty"))
        #expect(spec.dateChoices == ["none", "0", "1"])
        #expect(spec.subjectDescription.contains("7 words"))
        #expect(spec.fields(kind: "Warranty", source: " Acme ", subject: "x", dateChoice: "1")
                == GeneratedFields(kind: .custom(id: "w"), source: "Acme", subject: "x", dateChoice: 1))
        #expect(spec.fields(kind: "Banana", source: "", subject: "x", dateChoice: "7")
                == GeneratedFields(kind: .other, source: nil, subject: "x", dateChoice: nil))
        // Custom-kind changes apply from the next schema.
        let next = SchemaSpec(customKinds: [], candidates: [], subjectMaxWords: 5)
        #expect(!next.kinds.contains("Warranty") && next.dateChoices == ["none"])
    }

    @Test func instructionsUseTheSpecifiedWording() {
        var style = Presets.clean
        style.subjectWords = 4
        style.vocabulary = [VocabularyRule(from: "Bill", to: "Invoice")]
        style.neverInclude = ["confidential"]
        let text = PromptBuilder.instructions(style: style, language: .german)
        #expect(text == "You name files. Fill the fields using only information in the provided content and metadata. Prefer concrete words (company, product, document type) over generic ones. Subject: at most 4 words, no dates, no numbers longer than 8 digits. Never include account numbers, card numbers, IBANs, phone numbers, email addresses, passwords or ID numbers. Write in German. Preferred words: Invoice. Avoid: confidential. If the content is unreadable, use kind Other and a short visual description.")
    }

    @Test func promptOrderAndExampleLimit() {
        let prompt = PromptBuilder.prompt(metadata: ["Original name: a.pdf"], content: ["Line one"],
                                          examples: (1...8).map { "Name \($0)" })
        let metadata = prompt.range(of: "Metadata:")!.lowerBound
        let content = prompt.range(of: "Content:")!.lowerBound
        let names = prompt.range(of: "Names the user approved")!.lowerBound
        #expect(metadata < content && content < names)
        #expect(!prompt.contains("Name 3") && prompt.contains("Name 4") && prompt.contains("Name 8"))
    }
}

struct BudgetTests {
    /// F5: 1,000 fixtures, including maximum-length content, cause 0 context-exceeded errors.
    @Test func thousandFixturesNeverExceedTheContext() async throws {
        var g = SeededGenerator(seed: 0x4635)
        let generator = FakeGenerator(context: 4_096)
        for index in 0..<1_000 {
            let lineCount = index % 10 == 0 ? 5_000 : Int.random(in: 0...400, using: &g)
            var lines: [ContentLine] = []
            for line in 0..<lineCount {
                let text = index % 7 == 0 && line == 0
                    ? String(repeating: "x", count: 60_000)
                    : (0..<Int.random(in: 1...30, using: &g)).map { _ in g.word() }.joined(separator: " ")
                lines.append(ContentLine(text: text, isTitleSized: line % 13 == 0, hasDateCandidate: line % 17 == 0))
            }
            let original = request(lines, examples: (0..<Int.random(in: 0...20, using: &g)).map { "Example name \($0)" })
            let fitted = try await Budgeter.fit(original, generator: generator)
            let total = try await generator.tokenCount(instructions: fitted.instructions, prompt: fitted.promptText, image: nil)
            #expect(total <= 4_096 - 1_000, "fixture \(index)")
            let content = fitted.content.map(\.text).joined(separator: "\n")
            #expect(FakeGenerator.tokens(content) <= 3_000)
            await #expect(throws: Never.self) { _ = try await generator.generate(fitted) }
        }
    }

    @Test func trimmingFollowsTheSpecifiedOrder() async throws {
        let generator = FakeGenerator(context: 1_800)
        var lines = (0..<120).map { ContentLine(text: "Plain line number \($0) with some filler words in it") }
        lines[50] = ContentLine(text: "Total due 2026-12-15", hasDateCandidate: true)
        lines[3] = ContentLine(text: "INVOICE", isTitleSized: true)
        let fitted = try await Budgeter.fit(request(lines), generator: generator)
        #expect(fitted.content.count <= 40)
        #expect(fitted.content.contains { $0.text == "INVOICE" })
        #expect(!fitted.content.contains { $0.text.hasPrefix("Total due") }, "line 50 is cut with the lines after 40")
    }
}

struct CoordinatorTests {
    static let fields = GeneratedFields(kind: .builtIn(.receipt), source: "Migros", subject: "groceries", dateChoice: nil)

    final class StatusLog: Sendable {
        let statuses = Mutex<[GenerationStatus]>([])
    }

    actor SleepLog {
        var delays: [TimeInterval] = []
        func add(_ delay: TimeInterval) { delays.append(delay) }
    }

    func coordinator(_ generator: FakeGenerator, availability: ModelAvailability = .available, log: SleepLog = SleepLog(),
                     statuses: StatusLog? = nil) -> GenerationCoordinator {
        GenerationCoordinator(
            generator: generator, availability: { availability },
            sleeper: { delay in await log.add(delay) },
            timeoutSleeper: { delay in try await Task.sleep(for: .seconds(delay)) },
            onStatus: { status in statuses?.statuses.withLock { $0.append(status) } }
        )
    }

    /// F4: every row of the error table behaves exactly as specified.
    @Test func errorTable() async {
        let line = [ContentLine(text: "Migros receipt")]
        func outcome(_ script: [Result<GeneratedFields, ModelFailure>], availability: ModelAvailability = .available) async -> (GenerationOutcome, Int) {
            let generator = FakeGenerator(script: script)
            let result = await coordinator(generator, availability: availability).generate(request(line))
            return (result, generator.calls.count)
        }
        #expect(await outcome([.failure(.guardrailViolation)]) == (.basic(.guardrail), 1))
        #expect(await outcome([.failure(.refusal(explanation: nil))]) == (.basic(.refusal(explanation: nil)), 1))
        #expect(BasicReason.guardrail.forcesLowConfidence && BasicReason.refusal(explanation: nil).forcesLowConfidence)
        #expect(await outcome([.failure(.contextSizeExceeded), .success(Self.fields)]) == (.model(Self.fields), 2))
        #expect(await outcome([.failure(.contextSizeExceeded), .failure(.contextSizeExceeded)]) == (.basic(.contextExceeded), 2))
        #expect(await outcome([.failure(.rateLimited(resetDate: nil)), .success(Self.fields)]) == (.model(Self.fields), 2))
        #expect(await outcome([.failure(.concurrentRequests), .success(Self.fields)]) == (.model(Self.fields), 2))
        #expect(await outcome([.failure(.unavailable)]).1 == 1)
        #expect(await outcome([.failure(.assetsUnavailable)]) == (.basic(.assetsUnavailable), 1))
        #expect(await outcome([.failure(.unsupportedLanguage)]) == (.basic(.unsupportedLanguage), 1))
        #expect(await outcome([.failure(.decodingFailure), .success(Self.fields)]) == (.model(Self.fields), 2))
        #expect(await outcome([.failure(.decodingFailure), .failure(.decodingFailure)]) == (.basic(.decodingFailure), 2))
        #expect(await outcome([.failure(.timeout)]) == (.basic(.timeout), 1))
        for state in [ModelAvailability.deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .basicOnly] {
            #expect(await outcome([], availability: state) == (.basic(.unavailable(state)), 0))
        }
    }

    @Test func noAnswerWithinTheTimeoutFallsBackToBasic() async {
        let generator = FakeGenerator(delay: .seconds(30))
        let fast = GenerationCoordinator(generator: generator, availability: { .available }, timeout: 0.2)
        let start = Date()
        #expect(await fast.generate(request([ContentLine(text: "x")])) == .basic(.timeout))
        #expect(Date().timeIntervalSince(start) < 5)
    }

    /// V4: under forced rate limiting, retries follow the backoff schedule exactly, the status is shown,
    /// and no file is processed twice.
    @Test func rateLimitBackoffSchedule() async {
        let failures = Array(repeating: Result<GeneratedFields, ModelFailure>.failure(.rateLimited(resetDate: nil)), count: 6)
        let generator = FakeGenerator(script: failures + [.success(Self.fields)])
        let log = SleepLog()
        let statuses = StatusLog()
        let result = await coordinator(generator, log: log, statuses: statuses).generate(request([ContentLine(text: "x")]))
        #expect(result == .model(Self.fields))
        #expect(await log.delays == [5, 15, 60, 300, 300, 300])
        let waits = statuses.statuses.withLock { $0 }.filter { if case .waitingForAppleIntelligence = $0 { true } else { false } }
        #expect(waits.count == 6)
        #expect(generator.calls.count == 7, "one request, retried; never duplicated")
    }

    /// F6: 50 simultaneous arrivals are processed in arrival order with 0 concurrency errors.
    @Test func fiftySimultaneousArrivalsInOrder() async {
        let generator = FakeGenerator(delay: .milliseconds(5))
        let coordinator = coordinator(generator)
        let results = await withTaskGroup(of: (Int, GenerationOutcome).self) { group in
            for index in 0..<50 {
                group.addTask {
                    await Task.yield()
                    return (index, await coordinator.generate(request([ContentLine(text: "file \(index)")])))
                }
                // Arrival order is the order generate() is entered.
                try? await Task.sleep(for: .milliseconds(1))
            }
            var collected: [(Int, GenerationOutcome)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        #expect(results.count == 50)
        #expect(generator.state.withLock { $0.maxActive } == 1)
        let order = generator.calls.compactMap { $0.content.first?.text }
        #expect(order == (0..<50).map { "file \($0)" })
    }

    @Test func prewarmsOnlyAfterAQuietPeriod() async {
        let generator = FakeGenerator()
        var now = Date(timeIntervalSince1970: 1_000)
        let clock = Mutex(now)
        let coordinator = GenerationCoordinator(generator: generator, availability: { .available }, now: { clock.withLock { $0 } })
        await coordinator.noteArrival(instructions: "i")
        await coordinator.noteArrival(instructions: "i")
        now = now.addingTimeInterval(600)
        clock.withLock { $0 = now }
        await coordinator.noteArrival(instructions: "i")
        #expect(generator.state.withLock { $0.prewarms } == 2)
    }

    /// F2: the same input gives an identical result in 50 runs (greedy path with a fixed model).
    @Test func identicalResultsAcrossRuns() async {
        let generator = FakeGenerator()
        let coordinator = coordinator(generator)
        var outcomes: Set<String> = []
        for _ in 0..<50 {
            let outcome = await coordinator.generate(request([ContentLine(text: "Swisscom invoice November")]))
            outcomes.insert(String(describing: outcome))
        }
        #expect(outcomes.count == 1)
        #expect(generator.calls.allSatisfy { $0.sampling == .greedy })
    }
}

struct BasicNamerTests {
    @Test(arguments: [
        ("Rechnung Nr. 4711", BuiltInKind?.some(.invoice)), ("FACTURE", .invoice), ("Fattura elettronica", .invoice),
        ("Factura simplificada", .invoice), ("Fatura de serviços", .invoice), ("Factuur", .invoice), ("請求書", .invoice),
        ("Quittung", .receipt), ("Reçu de paiement", .receipt), ("Kontoauszug Oktober", .bankStatement),
        ("Relevé de compte", .bankStatement), ("Lohnabrechnung", .payslip), ("Boarding pass LX 1234", .boardingPass),
        ("Order confirmation #123", .orderConfirmation), ("Mietvertrag", nil), ("Contrat de location", .contract),
        ("Steuererklärung 2025", .taxDocument), ("Curriculum Vitae", .resume), ("User Guide", .manual),
    ])
    func keywordTable(title: String, expected: BuiltInKind?) {
        let fields = BasicNamer.fields(BasicInput(lines: [ContentLine(text: title, isTitleSized: true)], titleLine: title))
        #expect(fields.kind == (expected.map { KindRef.builtIn($0) } ?? .other), "\(title)")
    }

    @Test func sourceSubjectAndDate() {
        let candidates = DateCandidateParser.candidates(in: "27 November 2026", language: .english)
        let fields = BasicNamer.fields(BasicInput(
            lines: [ContentLine(text: "Mobile subscription November 2026", isTitleSized: true)],
            titleLine: "Mobile subscription 27 November 2026", downloadDomain: "www.swisscom.ch", candidates: candidates
        ))
        #expect(fields.source == "Swisscom")
        #expect(fields.subject == "Mobile subscription")
        #expect(fields.dateChoice == 0)
        #expect(BasicNamer.fields(BasicInput(app: "Safari", isScreenshot: true)).source == "Safari")
        #expect(BasicNamer.fields(BasicInput(labels: [ImageLabel(identifier: "golden_retriever", confidence: 0.9)],
                                             fileExtension: "jpg")).subject == "golden retriever")
        #expect(BasicNamer.fields(BasicInput(labels: [ImageLabel(identifier: "beach", confidence: 0.9)], fileExtension: "jpg")).kind == .builtIn(.photo))
        #expect(BasicNamer.fields(BasicInput(fileExtension: "pptx")).kind == .builtIn(.presentation))
        #expect(BasicNamer.fields(BasicInput(lines: [ContentLine(text: "From: anna"), ContentLine(text: "Subject: lunch")])).kind == .builtIn(.email))
    }

    @Test func domainAliases() {
        #expect(DomainAliases.source(forDomain: "www.bahn.de") == "Deutsche Bahn")
        #expect(DomainAliases.source(forDomain: "mail.acme-tools.co.uk") == "Acme Tools")
        #expect(DomainAliases.source(forDomain: "downloads.example.com") == "Example")
        #expect(DomainAliases.matches(source: "Deutsche Bahn", domain: "bahn.de"))
        let evidence = Evidence(text: "", downloadDomain: "bahn.de")
        #expect(ProposalValidator.sourceEvidence("Deutsche Bahn", evidence: evidence, app: nil) != nil)
    }
}

@Suite("Token estimate (F5)")
struct TokenEstimatorTests {
    @Test("The estimate errs high for English, accented Latin and CJK text")
    func errsHigh() {
        // Real tokenizers average about 4 ASCII characters per token.
        let english = String(repeating: "Swisscom invoice for the mobile subscription in November. ", count: 40)
        #expect(TokenEstimator.estimate(english) >= english.count / 3)
        let french = String(repeating: "Facture détaillée de décembre, échéance prévue. ", count: 40)
        #expect(TokenEstimator.estimate(french) >= french.count / 3)
        // About 1 to 1.5 tokens per CJK character.
        let japanese = String(repeating: "東京都の請求書です。", count: 100)
        #expect(TokenEstimator.estimate(japanese) >= Int(Double(japanese.count) * 1.5))
        #expect(TokenEstimator.estimate("") == 0)
        #expect(TokenEstimator.estimate(instructions: "a", prompt: "b", hasImage: true) >= TokenEstimator.imageTokens)
    }

    @Test("Budgeted content stays within 3,000 estimated tokens")
    func budgetWithEstimate() async throws {
        struct EstimatingModel: FieldGenerator {
            func generate(_ request: GenerationRequest) async throws -> GeneratedFields { throw ModelFailure.decodingFailure }
            func tokenCount(instructions: String, prompt: String, image: PromptImage?) async throws -> Int {
                TokenEstimator.estimate(instructions: instructions, prompt: prompt, hasImage: image != nil)
            }
            func contextSize() async throws -> Int { 4_096 }
            func prewarm(instructions: String) async {}
        }
        let lines = (0..<400).map { ContentLine(text: "Line \($0) 東京 with some ordinary words and a few more words to fill it") }
        let request = GenerationRequest(metadata: [], content: lines, image: nil, examples: [],
                                        schema: SchemaSpec(customKinds: [], candidates: [], subjectMaxWords: 5),
                                        instructions: "Name the file.", sampling: .greedy, priority: .background)
        let fitted = try await Budgeter.fit(request, generator: EstimatingModel())
        let content = fitted.content.map(\.text).joined(separator: "\n")
        #expect(TokenEstimator.estimate(content) <= Defaults.contentTokenBudget)
        #expect(TokenEstimator.estimate(instructions: fitted.instructions, prompt: fitted.promptText, hasImage: false) <= 4_096 - Defaults.contextReserveTokens)
        #expect(!fitted.content.isEmpty)
    }
}
