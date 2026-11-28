import Foundation

/// Comparison keys and character transforms shared by the guards and the formatter.
public enum TextFolding {
    /// A key for "same word" comparisons: compatibility-normalized, lowercased, without accents.
    /// Used for source evidence (3.9), never-include and protected words.
    public static func key(_ text: String) -> String {
        removeAccents(text.nfkc).lowercased()
    }

    /// A key that ignores case but keeps accents (vocabulary matching is "any case", 3.10).
    public static func caseKey(_ text: String) -> String {
        text.nfkc.lowercased()
    }

    /// Removes accents from Latin, Greek and Cyrillic letters and spells out letters that
    /// have no decomposition (ß → ss, æ → ae, ø → o, ł → l …). Marks in other scripts
    /// (Devanagari vowel signs, Japanese voicing marks, Thai) are kept, because removing
    /// them would change the word.
    public static func removeAccents(_ text: String) -> String {
        if text.isASCIIOnly { return text }
        var spelled = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if let replacement = specialLetters[scalar] {
                spelled.append(contentsOf: replacement.unicodeScalars)
            } else {
                spelled.append(scalar)
            }
        }
        let decomposed = String(spelled).nfd
        var result = String.UnicodeScalarView()
        var lastBaseStrippable = false
        for scalar in decomposed.unicodeScalars {
            let category = scalar.properties.generalCategory
            if category == .nonspacingMark || category == .enclosingMark || category == .spacingMark {
                if lastBaseStrippable { continue }
                result.append(scalar)
            } else {
                lastBaseStrippable = isAccentStrippableBase(scalar)
                result.append(scalar)
            }
        }
        return String(result).nfc
    }

    private static func isAccentStrippableBase(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0000...0x024F, 0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xAB30...0xAB6F: true // Latin
        case 0x0370...0x03FF, 0x1F00...0x1FFF: true // Greek
        case 0x0400...0x052F, 0x2DE0...0x2DFF, 0xA640...0xA69F: true // Cyrillic
        default: false
        }
    }

    private static let specialLetters: [Unicode.Scalar: String] = [
        "ß": "ss", "ẞ": "SS", "æ": "ae", "Æ": "AE", "œ": "oe", "Œ": "OE",
        "ø": "o", "Ø": "O", "đ": "d", "Đ": "D", "ł": "l", "Ł": "L",
        "þ": "th", "Þ": "Th", "ð": "d", "Ð": "D", "ħ": "h", "Ħ": "H",
        "ı": "i", "ŀ": "l", "Ŀ": "L", "ĸ": "k", "ŋ": "ng", "Ŋ": "Ng",
        "ſ": "s", "ƒ": "f", "ŧ": "t", "Ŧ": "T",
    ]

    /// True for letters with case or caseless letters, and digits.
    public static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII {
            let v = scalar.value
            return (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122)
        }
        let p = scalar.properties
        return p.isAlphabetic || p.numericType == .decimal
    }
}

extension Character {
    /// True when this grapheme displays as an emoji (3.10 "Allow emoji").
    /// Text-style symbols such as ™, © and arrows are not emoji.
    public var isEmojiGrapheme: Bool {
        if asciiValue != nil { return false }
        let scalars = unicodeScalars
        guard let first = scalars.first else { return false }
        if scalars.contains(where: { $0.value == 0x20E3 }) { return true } // keycap
        if scalars.contains(where: { (0x1F1E6...0x1F1FF).contains($0.value) }) { return true } // flags
        let p = first.properties
        if p.isEmojiModifier { return true }
        guard p.isEmoji else { return false }
        if first.isASCII { return scalars.contains(where: { $0.value == 0xFE0F }) && scalars.count > 1 }
        if p.isEmojiPresentation { return true }
        if scalars.contains(where: { $0.value == 0xFE0F }) { return true }
        // Text-default pictographs in the symbol and dingbat blocks, and anything above U+1F000.
        return (0x2600...0x27BF).contains(first.value) || first.value >= 0x1F000
    }
}
