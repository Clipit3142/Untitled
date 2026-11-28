/// A conservative token count for budgeting (3.8, F5), used where the SDK offers no token
/// counting API. It errs high so prompts always fit: tokenizers average about four ASCII
/// characters per token and one to one and a half tokens per CJK character; this counts one
/// token per three ASCII characters, two per non-ASCII character, plus a margin per line.
public enum TokenEstimator {
    /// Tokens reserved for an attached image (≤ 1,536 px on the long side, 3.4).
    public static let imageTokens = 1_500

    public static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var ascii = 0
        var other = 0
        var lines = 1
        for scalar in text.unicodeScalars {
            if scalar.isASCII {
                ascii += 1
                if scalar == "\n" { lines += 1 }
            } else {
                other += 1
            }
        }
        let base = (ascii + 2) / 3 + other * 2 + lines * 2
        return base + base / 10
    }

    public static func estimate(instructions: String, prompt: String, hasImage: Bool) -> Int {
        estimate(instructions) + estimate(prompt) + (hasImage ? imageTokens : 0)
    }
}
