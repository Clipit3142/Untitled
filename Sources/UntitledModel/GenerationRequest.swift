public import Foundation
public import UntitledCore
#if canImport(CoreGraphics)
public import CoreGraphics
#endif

/// An image passed to the model alongside text (3.7, 3.8). Only used when image input ships.
public struct PromptImage: @unchecked Sendable {
    // @unchecked: CGImage is immutable once created.
    #if canImport(CoreGraphics)
    public let cgImage: CGImage
    public init(cgImage: CGImage) { self.cgImage = cgImage }
    #else
    public let pixelSize: Int
    public init(pixelSize: Int) { self.pixelSize = pixelSize }
    #endif
}

/// A line of extracted text. Title-sized lines and lines with date candidates survive
/// budget trimming (3.8).
public struct ContentLine: Sendable, Hashable {
    public var text: String
    public var isTitleSized: Bool
    public var hasDateCandidate: Bool

    public init(text: String, isTitleSized: Bool = false, hasDateCandidate: Bool = false) {
        self.text = text
        self.isTitleSized = isTitleSized
        self.hasDateCandidate = hasDateCandidate
    }
}

/// Sampling for a request: greedy for first proposals, random for Regenerate (3.8).
public enum Sampling: Sendable, Hashable {
    case greedy
    case random(seed: UInt64?)
}

/// Quality of service: background for automatic work, user-initiated for Quick Rename (3.8).
public enum RequestPriority: Sendable, Hashable {
    case background
    case userInitiated
}

/// Everything the model sees for one file. Text lives only in memory (3.18).
public struct GenerationRequest: Sendable {
    public var metadata: [String]
    public var content: [ContentLine]
    public var image: PromptImage?
    public var examples: [String]
    public var schema: SchemaSpec
    public var instructions: String
    public var sampling: Sampling
    public var priority: RequestPriority

    public init(metadata: [String], content: [ContentLine], image: PromptImage?, examples: [String],
                schema: SchemaSpec, instructions: String, sampling: Sampling = .greedy, priority: RequestPriority = .background) {
        self.metadata = metadata
        self.content = content
        self.image = image
        self.examples = examples
        self.schema = schema
        self.instructions = instructions
        self.sampling = sampling
        self.priority = priority
    }

    /// The prompt text in the order of 3.8: metadata, content, (image), approved names.
    public var promptText: String { PromptBuilder.prompt(metadata: metadata, content: content.map(\.text), examples: examples) }
}

/// Model failures, mapped from the framework's errors (3.8 "Error policy").
public enum ModelFailure: Error, Sendable, Hashable {
    case guardrailViolation
    case refusal(explanation: String?)
    case contextSizeExceeded
    case rateLimited(resetDate: Date?)
    case concurrentRequests
    case unavailable
    case assetsUnavailable
    case unsupportedLanguage
    case decodingFailure
    case timeout
}

/// Whether Apple Intelligence can be used (3.8 "Availability", B2, F3).
public enum ModelAvailability: String, Sendable, Hashable, Codable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    /// The user chose "Use Basic naming only".
    case basicOnly

    public var usesModel: Bool { self == .available }

    /// The status pill text (3.15).
    public var statusText: String? {
        switch self {
        case .available: nil
        case .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .basicOnly: "Basic naming"
        }
    }

    /// The explanation in Settings and onboarding.
    public var explanation: String {
        switch self {
        case .available: "Apple Intelligence is ready. Files are named on this Mac."
        case .deviceNotEligible: "This Mac doesn't support Apple Intelligence. Untitled uses Basic naming, which reads keywords and titles."
        case .appleIntelligenceNotEnabled: "Apple Intelligence is turned off. Turn it on in System Settings for better names, or keep using Basic naming."
        case .modelNotReady: "Apple Intelligence is still downloading. Untitled uses Basic naming until it's ready."
        case .basicOnly: "You chose Basic naming only. Untitled reads keywords and titles instead of using Apple Intelligence."
        }
    }
}

/// The model behind Untitled: the on-device Apple model in the app, a fake in tests.
public protocol FieldGenerator: Sendable {
    /// Generates fields. Throws `ModelFailure` for every failure the policy handles.
    func generate(_ request: GenerationRequest) async throws -> GeneratedFields
    /// Tokens used by instructions plus prompt text (and image, when present).
    func tokenCount(instructions: String, prompt: String, image: PromptImage?) async throws -> Int
    /// The model's context size in tokens.
    func contextSize() async throws -> Int
    /// Loads the model ahead of the first request after a quiet period (3.5).
    func prewarm(instructions: String) async
}
