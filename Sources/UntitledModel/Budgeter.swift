import UntitledCore

/// Fits a request into the model's context (3.8 "Budget", F5): content is trimmed until the
/// prompt fits in the context size minus 1,000 tokens, and content never exceeds 3,000 tokens.
/// Trimming order: lines after the first 40; lines with neither a date candidate nor
/// title-sized text; then a cut at a line boundary.
public enum Budgeter {
    /// Lines longer than this are split at spaces first, so "a cut at a line boundary" can
    /// always make progress on text without line breaks.
    public static let maxLineCharacters = 400

    public static func fit(_ request: GenerationRequest, generator: any FieldGenerator) async throws -> GenerationRequest {
        let contextSize = try await generator.contextSize()
        let limit = contextSize - Defaults.contextReserveTokens
        var current = request
        current.content = splitLongLines(request.content)

        func fits(_ candidate: GenerationRequest) async throws -> Bool {
            let content = candidate.content.map(\.text).joined(separator: "\n")
            let contentTokens = content.isEmpty ? 0 : try await generator.tokenCount(instructions: "", prompt: content, image: nil)
            guard contentTokens <= Defaults.contentTokenBudget else { return false }
            let total = try await generator.tokenCount(instructions: candidate.instructions, prompt: candidate.promptText, image: candidate.image)
            return total <= limit
        }

        if try await fits(current) { return current }

        // 1. Lines after the first 40.
        current.content = Array(current.content.prefix(Defaults.contentLineLimit))
        if try await fits(current) { return current }

        // 2. Lines with neither date candidates nor title-sized text.
        current.content = current.content.filter { $0.hasDateCandidate || $0.isTitleSized }
        if try await fits(current) { return current }

        // 3. A cut at a line boundary: the longest prefix that fits.
        let lines = current.content
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high + 1) / 2
            var candidate = current
            candidate.content = Array(lines.prefix(middle))
            if try await fits(candidate) { low = middle } else { high = middle - 1 }
        }
        current.content = Array(lines.prefix(low))
        if try await fits(current) { return current }

        // Even with no content the fixed parts are too large: drop examples, then the image.
        current.examples = []
        if try await fits(current) { return current }
        current.image = nil
        return current
    }

    static func splitLongLines(_ lines: [ContentLine]) -> [ContentLine] {
        lines.flatMap { line -> [ContentLine] in
            guard line.text.count > maxLineCharacters else { return [line] }
            var pieces: [ContentLine] = []
            var current = ""
            for word in line.text.split(separator: " ", omittingEmptySubsequences: true) {
                var word = Substring(word)
                while word.count > maxLineCharacters {
                    pieces.append(ContentLine(text: String(word.prefix(maxLineCharacters)), isTitleSized: line.isTitleSized, hasDateCandidate: line.hasDateCandidate))
                    word = word.dropFirst(maxLineCharacters)
                }
                if current.count + word.count + 1 > maxLineCharacters, !current.isEmpty {
                    pieces.append(ContentLine(text: current, isTitleSized: line.isTitleSized, hasDateCandidate: line.hasDateCandidate))
                    current = ""
                }
                current += current.isEmpty ? String(word) : " " + word
            }
            if !current.isEmpty { pieces.append(ContentLine(text: current, isTitleSized: line.isTitleSized, hasDateCandidate: line.hasDateCandidate)) }
            return pieces
        }
    }

    /// Half the content, for the single retry after a context-size error.
    public static func halved(_ request: GenerationRequest) -> GenerationRequest {
        var copy = request
        copy.content = Array(request.content.prefix(request.content.count / 2))
        return copy
    }
}
