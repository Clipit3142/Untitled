import Foundation

/// Makes text safe to use as a filename (3.10 steps 6–7).
public enum Sanitizer {
    /// Characters treated as separators when collapsing and trimming.
    static let separatorCharacters: Set<Character> = [" ", "-", "_", ".", "\u{2013}"]

    /// Characters the Windows-safe option removes (G7). ":" and "/" are always removed.
    static let windowsForbidden: Set<Character> = ["\\", "*", "?", "\"", "<", ">", "|"]

    static let windowsReservedNames: Set<String> = {
        var names: Set<String> = ["CON", "PRN", "AUX", "NUL"]
        for n in 0...9 { names.insert("COM\(n)"); names.insert("LPT\(n)") }
        for s in ["\u{00B9}", "\u{00B2}", "\u{00B3}"] { names.insert("COM\(s)"); names.insert("LPT\(s)") }
        return names
    }()

    // MARK: Character options (step 6)

    /// Applies Remove accents, ASCII only, Windows-safe and Allow emoji.
    public static func applyCharacterOptions(_ text: String, _ options: CharacterOptions) -> String {
        var result = text
        if !options.allowEmoji {
            result = String(result.filter { !$0.isEmojiGrapheme })
        }
        if options.removeAccents || options.asciiOnly {
            result = TextFolding.removeAccents(result)
        }
        if options.asciiOnly {
            result = String(String.UnicodeScalarView(result.unicodeScalars.filter { $0.isASCII }))
        }
        if options.windowsSafe {
            result = String(result.filter { !windowsForbidden.contains($0) })
        }
        return result
    }

    // MARK: Invisible and forbidden characters (step 7, first bullet)

    /// Removes "/", ":", NUL, control, format, bidirectional, zero-width and other
    /// default-ignorable characters; turns every kind of space and line break into a plain
    /// space. Inside an emoji grapheme (only when emoji are allowed) the joiner, variation
    /// selector, skin-tone, keycap and tag characters that make up the emoji are kept.
    public static func stripForbidden(_ text: String, allowEmoji: Bool) -> String {
        // Removing a character can merge its neighbours into one grapheme (a stray skin-tone
        // modifier joins the letter before it), so repeat until nothing changes.
        if text.isASCIIOnly { return stripOnce(text, allowEmoji: allowEmoji) }
        var current = text.nfc
        for _ in 0..<4 {
            let next = stripOnce(current, allowEmoji: allowEmoji).nfc
            if next == current { return next }
            current = next
        }
        return current
    }

    private static func stripOnce(_ text: String, allowEmoji: Bool) -> String {
        var out = String.UnicodeScalarView()
        for character in text {
            if allowEmoji, character.isEmojiGrapheme {
                for scalar in character.unicodeScalars where isEmojiComponent(scalar) {
                    out.append(scalar)
                }
                continue
            }
            for scalar in character.unicodeScalars {
                if let mapped = mapScalar(scalar) { out.append(mapped) }
            }
        }
        return String(out)
    }

    private static func mapScalar(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        if scalar.isASCII {
            switch scalar.value {
            case 0x00, 0x2F, 0x3A: return nil
            case 0x09...0x0D: return " "
            case 0x01...0x1F, 0x7F: return nil
            default: return scalar
            }
        }
        switch scalar.value {
        case 0x00, 0x2F, 0x3A: return nil // NUL, "/", ":"
        case 0x2800, 0x115F, 0x1160, 0x3164, 0xFFA0: return nil // blank-looking letters
        default: break
        }
        let p = scalar.properties
        switch p.generalCategory {
        case .control:
            return (0x09...0x0D).contains(scalar.value) || scalar.value == 0x85 ? " " : nil
        case .format, .privateUse, .unassigned, .surrogate:
            return nil
        case .spaceSeparator, .lineSeparator, .paragraphSeparator:
            return " "
        default:
            break
        }
        if p.isDefaultIgnorableCodePoint || p.isNoncharacterCodePoint || p.isBidiControl || p.isJoinControl {
            return nil
        }
        return scalar
    }

    private static func isEmojiComponent(_ scalar: Unicode.Scalar) -> Bool {
        let p = scalar.properties
        if p.isEmoji || p.isEmojiModifier || p.isEmojiPresentation { return true }
        switch scalar.value {
        case 0x200D, 0xFE0E, 0xFE0F, 0x20E3: return true
        case 0xE0020...0xE007F: return true
        case 0x1F1E6...0x1F1FF: return true
        default: return false
        }
    }

    // MARK: Collapse and trim (step 7, remaining bullets)

    /// Collapses repeated separators and trims spaces, separators and dots at both ends.
    public static func collapseAndTrim(_ text: String, partSeparator: String, wordSeparator: String) -> String {
        var result = ""
        var run = ""
        func flushRun() {
            guard !run.isEmpty else { return }
            result += collapse(run, partSeparator: partSeparator, wordSeparator: wordSeparator)
            run = ""
        }
        for character in text {
            if separatorCharacters.contains(character) {
                run.append(character)
            } else {
                flushRun()
                result.append(character)
            }
        }
        flushRun()
        return trimSeparators(result)
    }

    private static func collapse(_ run: String, partSeparator: String, wordSeparator: String) -> String {
        if run.count == 1 { return run }
        if let first = run.first, run.allSatisfy({ $0 == first }) { return String(first) }
        if run == partSeparator { return run }
        if !partSeparator.isEmpty, run.contains(partSeparator) { return partSeparator }
        if !wordSeparator.isEmpty, run.contains(wordSeparator) { return wordSeparator }
        return String(run.first(where: { $0 != " " }) ?? " ")
    }

    /// True when ASCII text needs no sanitizing: no controls, "/", ":", (Windows) reserved
    /// characters, repeated separators, or separators at either end.
    static func isCleanASCII(_ text: String, windowsSafe: Bool) -> Bool {
        var previousWasSeparator = true // so a leading separator fails
        for byte in text.utf8 {
            if byte >= 0x80 || byte < 0x20 || byte == 0x7F || byte == 0x2F || byte == 0x3A { return false }
            if windowsSafe, byte == 0x5C || byte == 0x2A || byte == 0x3F || byte == 0x22 || byte == 0x3C || byte == 0x3E || byte == 0x7C {
                return false
            }
            let isSeparator = byte == 0x20 || byte == 0x2D || byte == 0x5F || byte == 0x2E
            if isSeparator, previousWasSeparator { return false }
            previousWasSeparator = isSeparator
        }
        return !previousWasSeparator || text.isEmpty
    }

    public static func trimSeparators(_ text: String) -> String {
        var characters = Substring(text)
        while let first = characters.first, separatorCharacters.contains(first) || first.isWhitespace {
            characters.removeFirst()
        }
        while let last = characters.last, separatorCharacters.contains(last) || last.isWhitespace {
            characters.removeLast()
        }
        return String(characters)
    }

    // MARK: Entry points

    /// Sanitizes a fixed-text token or a subfolder component: character options, forbidden
    /// characters, NFC, collapse and trim.
    public static func sanitizeComponent(_ text: String, options: CharacterOptions) -> String {
        let withOptions = applyCharacterOptions(text, options)
        let stripped = stripForbidden(withOptions, allowEmoji: options.allowEmoji)
        let normalized = stripped.nfc
        let collapsed = collapseAndTrim(normalized, partSeparator: " ", wordSeparator: " ")
        return options.windowsSafe ? windowsSafeBase(collapsed) : collapsed
    }

    /// Step 7 on an assembled base name.
    public static func sanitizeBase(_ base: String, partSeparator: String, wordSeparator: String, options: CharacterOptions) -> String {
        if isCleanASCII(base, windowsSafe: options.windowsSafe) {
            return options.windowsSafe ? windowsSafeBase(base) : base
        }
        var stripped = stripForbidden(base, allowEmoji: options.allowEmoji)
        if options.windowsSafe { stripped = String(stripped.filter { !windowsForbidden.contains($0) }) }
        let normalized = stripped.nfc
        let collapsed = collapseAndTrim(normalized, partSeparator: partSeparator, wordSeparator: wordSeparator)
        return options.windowsSafe ? windowsSafeBase(collapsed) : collapsed
    }

    /// Windows-safe base: no reserved device name before the first dot (G7).
    public static func windowsSafeBase(_ base: String) -> String {
        guard !base.isEmpty else { return base }
        let stem = base.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? base
        let trimmedStem = stem.trimmingCharacters(in: .whitespaces)
        guard windowsReservedNames.contains(trimmedStem.uppercased()) else { return base }
        if let dot = base.firstIndex(of: ".") {
            return String(base[..<dot]) + "_" + String(base[dot...])
        }
        return base + "_"
    }

    /// Sanitizes a complete filename (typed names, G6): forbidden characters removed, NFC,
    /// separators collapsed and trimmed, and the whole name cut to 255 UTF-8 bytes at a
    /// character boundary, keeping the extension. Returns nil when nothing usable remains.
    public static func sanitizeFileName(_ name: String, allowEmoji: Bool = true, windowsSafe: Bool = false) -> String? {
        var split = FileExtension.split(name)
        var options = CharacterOptions(allowEmoji: allowEmoji)
        options.windowsSafe = windowsSafe
        var base = sanitizeBase(split.base, partSeparator: " ", wordSeparator: " ", options: options)
        if base.isEmpty, let ext = split.extension {
            // "...hidden": nothing left of the base, so the "extension" is the name.
            base = sanitizeBase(ext, partSeparator: " ", wordSeparator: " ", options: options)
            split.extension = nil
        }
        var ext = split.extension.map { sanitizeExtension($0) } ?? nil
        if windowsSafe, let current = ext {
            let filtered = String(current.filter { !windowsForbidden.contains($0) })
            ext = filtered.isEmpty ? nil : filtered
        }
        guard !base.isEmpty else { return nil }
        let extBytes = ext.map { $0.utf8.count + 1 } ?? 0
        base = fitBytes(base, limit: Defaults.maxFileNameBytes - extBytes)
        guard !base.isEmpty else { return nil }
        if windowsSafe { base = windowsSafeBase(base) }
        return ext.map { base + "." + $0 } ?? base
    }

    static func sanitizeExtension(_ ext: String) -> String? {
        let cleaned = stripForbidden(ext, allowEmoji: false).nfc
        let trimmed = trimSeparators(cleaned)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Cuts text at a character boundary so its UTF-8 form fits `limit` bytes, then trims
    /// trailing separators and re-normalizes.
    public static func fitBytes(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        var result = text
        while result.utf8.count > limit {
            result.removeLast()
            result = trimSeparators(result).nfc
        }
        return result
    }

    // MARK: Validation (used by tests and by the executor as a last check)

    /// True if `name` is a valid filename by Untitled's rules.
    public static func isValidFileName(_ name: String, windowsSafe: Bool = false) -> Bool {
        guard !name.isEmpty, name.utf8.count <= Defaults.maxFileNameBytes else { return false }
        guard name == name.nfc else { return false }
        guard !name.hasPrefix("."), name != "..", !name.hasPrefix(" ") else { return false }
        if let last = name.last, last == " " || last == "." { return false }
        for character in name {
            if character.isEmojiGrapheme {
                if character.unicodeScalars.contains(where: { !isEmojiComponent($0) && $0.properties.generalCategory == .format && $0.value != 0x200D }) {
                    return false
                }
                continue
            }
            for scalar in character.unicodeScalars where mapScalar(scalar) != scalar {
                return false
            }
            if windowsSafe, windowsForbidden.contains(character) { return false }
        }
        if windowsSafe {
            let stem = name.split(separator: ".", maxSplits: 1).first.map(String.init) ?? name
            if windowsReservedNames.contains(stem.trimmingCharacters(in: .whitespaces).uppercased()) { return false }
        }
        return true
    }
}
