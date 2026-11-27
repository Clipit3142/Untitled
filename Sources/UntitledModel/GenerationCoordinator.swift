public import Foundation
public import UntitledCore

/// Why Basic naming was used instead of the model.
public enum BasicReason: Sendable, Hashable {
    case unavailable(ModelAvailability)
    case guardrail
    case refusal(explanation: String?)
    case contextExceeded
    case assetsUnavailable
    case unsupportedLanguage
    case decodingFailure
    case timeout

    /// Guardrails and refusals force Low confidence and show the reason (3.8).
    public var forcesLowConfidence: Bool {
        switch self {
        case .guardrail, .refusal: true
        default: false
        }
    }

    public var explanation: String {
        switch self {
        case .unavailable(let availability): availability.explanation
        case .guardrail: "Apple Intelligence declined to name this file, so Basic naming was used."
        case .refusal(let explanation): explanation.map { "Apple Intelligence declined: \($0)" } ?? "Apple Intelligence declined to name this file, so Basic naming was used."
        case .contextExceeded: "The file has too much text for Apple Intelligence, so Basic naming was used."
        case .assetsUnavailable: "Apple Intelligence isn't downloaded yet, so Basic naming was used."
        case .unsupportedLanguage: "Apple Intelligence doesn't support this file's language, so Basic naming was used."
        case .decodingFailure: "Apple Intelligence gave an unusable answer, so Basic naming was used."
        case .timeout: "Apple Intelligence took too long, so Basic naming was used."
        }
    }
}

public enum GenerationOutcome: Sendable, Hashable {
    case model(GeneratedFields)
    case basic(BasicReason)
}

/// What the coordinator is doing, for the status pill (3.15).
public enum GenerationStatus: Sendable, Hashable {
    case idle
    case generating
    /// Rate limited or busy: "Waiting for Apple Intelligence".
    case waitingForAppleIntelligence(nextAttempt: Date)
}

/// Runs model requests one at a time, in arrival order, applying the error policy of 3.8.
public actor GenerationCoordinator {
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    let generator: any FieldGenerator
    let availability: @Sendable () -> ModelAvailability
    let timeout: TimeInterval
    let sleeper: Sleeper
    let timeoutSleeper: Sleeper
    let now: @Sendable () -> Date
    let onStatus: @Sendable (GenerationStatus) -> Void
    private var tail: Task<Void, Never>?
    private var lastRequest: Date?

    public init(
        generator: any FieldGenerator,
        availability: @escaping @Sendable () -> ModelAvailability,
        timeout: TimeInterval = Defaults.generationTimeout,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: .seconds($0)) },
        timeoutSleeper: @escaping Sleeper = { try await Task.sleep(for: .seconds($0)) },
        now: @escaping @Sendable () -> Date = { Date() },
        onStatus: @escaping @Sendable (GenerationStatus) -> Void = { _ in }
    ) {
        self.generator = generator
        self.availability = availability
        self.timeout = timeout
        self.sleeper = sleeper
        self.timeoutSleeper = timeoutSleeper
        self.now = now
        self.onStatus = onStatus
    }

    /// Queues a request behind earlier ones and returns its outcome.
    public func generate(_ request: GenerationRequest) async -> GenerationOutcome {
        let previous = tail
        let task = Task { [weak self] () -> GenerationOutcome in
            await previous?.value
            guard let self else { return .basic(.unavailable(.basicOnly)) }
            return await self.run(request)
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    /// Prewarms the model on the first arrival after a quiet period (3.5).
    public func noteArrival(instructions: String, quietPeriod: TimeInterval = 120) async {
        let time = now()
        defer { lastRequest = time }
        guard availability().usesModel else { return }
        if let last = lastRequest, time.timeIntervalSince(last) < quietPeriod { return }
        await generator.prewarm(instructions: instructions)
    }

    private func run(_ request: GenerationRequest) async -> GenerationOutcome {
        defer { onStatus(.idle) }
        var current = (try? await Budgeter.fit(request, generator: generator)) ?? request
        var rateAttempts = 0
        var contextRetried = false
        var decodingRetried = false
        while true {
            let state = availability()
            guard state.usesModel else { return .basic(.unavailable(state)) }
            onStatus(.generating)
            do {
                let fields = try await withTimeout(current)
                return .model(fields)
            } catch let failure as ModelFailure {
                switch failure {
                case .guardrailViolation:
                    return .basic(.guardrail)
                case .refusal(let explanation):
                    return .basic(.refusal(explanation: explanation))
                case .contextSizeExceeded:
                    if contextRetried { return .basic(.contextExceeded) }
                    contextRetried = true
                    current = Budgeter.halved(current)
                case .rateLimited, .concurrentRequests:
                    let delay = RateLimitBackoff.delay(afterAttempt: rateAttempts)
                    rateAttempts += 1
                    onStatus(.waitingForAppleIntelligence(nextAttempt: now().addingTimeInterval(delay)))
                    do { try await sleeper(delay) } catch { return .basic(.timeout) }
                case .unavailable:
                    return .basic(.unavailable(availability()))
                case .assetsUnavailable:
                    return .basic(.assetsUnavailable)
                case .unsupportedLanguage:
                    return .basic(.unsupportedLanguage)
                case .decodingFailure:
                    if decodingRetried { return .basic(.decodingFailure) }
                    decodingRetried = true
                case .timeout:
                    return .basic(.timeout)
                }
            } catch {
                // Errors without a documented meaning are handled like decoding failures.
                if decodingRetried { return .basic(.decodingFailure) }
                decodingRetried = true
            }
        }
    }

    /// Generates, or throws `.timeout` after the generation timeout (3.8 "No answer in 20 s").
    private func withTimeout(_ request: GenerationRequest) async throws -> GeneratedFields {
        let generator = self.generator
        let timeout = self.timeout
        let sleeper = self.timeoutSleeper
        return try await withThrowingTaskGroup(of: GeneratedFields.self) { group in
            group.addTask { try await generator.generate(request) }
            group.addTask {
                try await sleeper(timeout)
                throw ModelFailure.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw ModelFailure.timeout }
            return first
        }
    }
}
