import Foundation

/// Splits generated text into words for the formatter.
///
/// Words are separated by whitespace and by punctuation that cannot sit inside a filename
/// word (`/ \ : ; , | ! ? ( ) [ ] { } < > " * # = ~ ^ ` … • · – —` and underscores).
/// Hyphens, apostrophes, dots, `&`, `+` and `@` stay inside words ("Wi-Fi", "l'offre",
/// "v1.2", "AT&T"), but are trimmed from the ends. Words with no letter, digit or emoji
/// are dropped.
public enum WordTokenizer {
    public static func words(_ text: String, compatibilityNormalize: Bool = true) -> [String] {
        let normalized = compatibilityNormalize ? text.nfkc : text
        var words: [String] = []
        var current = ""
        for character in normalized {
            if isBreak(character) {
                flush(&current, into: &words)
            } else {
                current.append(character)
            }
        }
        flush(&current, into: &words)
        return words
    }

    private static func flush(_ current: inout String, into words: inout [String]) {
        defer { current = "" }
        let trimmed = trimEdges(current)
        guard let first = trimmed.first, isContentCharacter(first) else { return }
        words.append(trimmed)
    }

    /// A character that carries meaning: a letter, digit or emoji.
    static func isContentCharacter(_ character: Character) -> Bool {
        if let ascii = character.asciiValue {
            return (ascii >= 48 && ascii <= 57) || (ascii >= 65 && ascii <= 90) || (ascii >= 97 && ascii <= 122)
        }
        if character.isEmojiGrapheme { return true }
        guard let first = character.unicodeScalars.first else { return false }
        return TextFolding.isWordCharacter(first)
    }

    private static func trimEdges(_ word: String) -> String {
        guard let first = word.first, let last = word.last else { return word }
        if isContentCharacter(first), isContentCharacter(last) { return word }
        var slice = Substring(word)
        while let character = slice.first, !isContentCharacter(character) { slice.removeFirst() }
        while let character = slice.last, !isContentCharacter(character) { slice.removeLast() }
        return String(slice)
    }

    private static let breakScalars: Set<Unicode.Scalar> = [
        "/", "\\", ":", ";", ",", "|", "!", "?", "(", ")", "[", "]", "{", "}", "<", ">",
        "\"", "*", "#", "=", "~", "^", "`", "_", "\u{2026}", "\u{2022}", "\u{00B7}",
        "\u{2013}", "\u{2014}", "\u{2015}", "\u{201C}", "\u{201D}", "\u{201E}", "\u{00AB}",
        "\u{00BB}", "\u{2039}", "\u{203A}", "\u{3001}", "\u{3002}", "\u{FF0C}", "\u{FF1A}",
        "\u{300C}", "\u{300D}", "\u{300E}", "\u{300F}", "\u{3010}", "\u{3011}",
    ]

    /// ASCII characters that end a word: whitespace, controls and the break punctuation.
    private static let asciiBreaks: [Bool] = (0..<128).map { value in
        if value < 32 || value == 127 || value == 32 { return true }
        return "/\\:;,|!?()[]{}<>\"*#=~^`_".unicodeScalars.contains(Unicode.Scalar(UInt8(value)))
    }

    private static func isBreak(_ character: Character) -> Bool {
        if let ascii = character.asciiValue { return asciiBreaks[Int(ascii)] }
        if character.isEmojiGrapheme { return false }
        guard character.unicodeScalars.count >= 1, let first = character.unicodeScalars.first else { return true }
        if breakScalars.contains(first) { return true }
        let p = first.properties
        if p.isWhitespace { return true }
        switch p.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator,
             .privateUse, .unassigned, .surrogate:
            return true
        default:
            return p.isDefaultIgnorableCodePoint && first.value != 0x200D
        }
    }
}
