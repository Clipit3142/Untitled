#if canImport(FoundationModels)
import Foundation
import FoundationModels
public import UntitledCore

/// The on-device Apple model through the Foundation Models framework (3.8).
///
/// One fresh session per file, non-streaming `respond`, and a runtime-built schema so the
/// answer must fit it. Greedy sampling for first proposals, random for Regenerate.
public struct AppleFieldGenerator: FieldGenerator {
    public init() {}

    private var model: SystemLanguageModel { SystemLanguageModel.default }

    public func generate(_ request: GenerationRequest) async throws -> GeneratedFields {
        let schema = try Self.schema(for: request.schema)
        let session = LanguageModelSession(model: model, instructions: request.instructions)
        let options: GenerationOptions
        switch request.sampling {
        case .greedy:
            options = GenerationOptions(samplingMode: .greedy)
        case .random(let seed):
            options = GenerationOptions(samplingMode: .random(top: 40, seed: seed))
        }
        do {
            let response: LanguageModelSession.Response<GeneratedContent>
            if let image = request.image {
                let text = request.promptText
                response = try await session.respond(schema: schema, options: options) {
                    text
                    Attachment(image.cgImage)
                }
            } else {
                response = try await session.respond(to: request.promptText, schema: schema, options: options)
            }
            let content = response.content
            let kind = try content.value(String.self, forProperty: "kind")
            let source = try? content.value(String.self, forProperty: "source")
            let dateChoice = try content.value(String.self, forProperty: "dateChoice")
            let subject = try content.value(String.self, forProperty: "subject")
            return request.schema.fields(kind: kind, source: source, subject: subject, dateChoice: dateChoice)
        } catch let failure as ModelFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LanguageModelError {
            throw Self.map(error)
        } catch LanguageModelSession.Error.concurrentRequests {
            throw ModelFailure.concurrentRequests
        } catch SystemLanguageModel.Error.assetsUnavailable {
            throw ModelFailure.assetsUnavailable
        } catch {
            throw ModelFailure.decodingFailure
        }
    }

    static func map(_ error: LanguageModelError) -> ModelFailure {
        switch error {
        case .contextSizeExceeded: .contextSizeExceeded
        case .guardrailViolation: .guardrailViolation
        case .refusal: .refusal(explanation: nil)
        case .rateLimited: .rateLimited(resetDate: nil)
        case .unsupportedLanguageOrLocale: .unsupportedLanguage
        case .timeout: .timeout
        default: .decodingFailure
        }
    }

    /// The SDK has no token counting API, so the budget uses a conservative estimate; a
    /// context overflow is still handled by the error policy (retry with half the content).
    public func tokenCount(instructions: String, prompt: String, image: PromptImage?) async throws -> Int {
        TokenEstimator.estimate(instructions: instructions, prompt: prompt, hasImage: image != nil)
    }

    public func contextSize() async throws -> Int {
        model.contextSize
    }

    public func prewarm(instructions: String) async {
        LanguageModelSession(model: model, instructions: instructions).prewarm()
    }

    /// The current availability (3.8, B2).
    public static func availability() -> ModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady): .modelNotReady
        case .unavailable: .modelNotReady
        }
    }

    /// Builds the runtime schema. Property order is generation order: the subject comes
    /// last so it can draw on the kind, source and date chosen before it.
    static func schema(for spec: SchemaSpec) throws -> GenerationSchema {
        let kind = DynamicGenerationSchema(name: "Kind", description: spec.kindDescription, anyOf: spec.kinds)
        let date = DynamicGenerationSchema(name: "DateChoice", description: spec.dateDescription, anyOf: spec.dateChoices)
        let root = DynamicGenerationSchema(name: "FileNameFields", description: "Fields for naming a file.", properties: [
            DynamicGenerationSchema.Property(name: "kind", description: spec.kindDescription, schema: kind),
            DynamicGenerationSchema.Property(name: "source", description: spec.sourceDescription,
                                             schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            DynamicGenerationSchema.Property(name: "dateChoice", description: spec.dateDescription, schema: date),
            DynamicGenerationSchema.Property(name: "subject", description: spec.subjectDescription,
                                             schema: DynamicGenerationSchema(type: String.self)),
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }
}
#endif
