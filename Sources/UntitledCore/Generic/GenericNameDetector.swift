import Foundation

/// Decides whether a name is generic (3.6) and strips the generic parts from names.
///
/// A name is generic when it matches a structural pattern (Android screenshot names,
/// camera counters with a suffix) or when fewer than 3 letters remain after removing
/// digits, dates, month names, UUIDs, hex runs of 12+ characters and the generic words
/// below. Characters of Han, kana and Hangul scripts count as two letters each, so a
/// two-character Japanese or Chinese name such as "東京" is respected (SPEC Part 5 #38).
public struct GenericNameDetector: Sendable {
    /// User patterns: case-insensitive globs with `*` and `?`, matched against the base name.
    public var userPatterns: [String]

    public init(userPatterns: [String] = []) {
        self.userPatterns = userPatterns
    }

    public func isGeneric(_ fileName: String) -> Bool {
        let base = FileExtension.split(fileName).base.nfkc
        if userPatterns.contains(where: { Glob.matches($0, base) }) { return true }
        let lowered = base.lowercased()
        if GenericPatterns.matchesStructural(lowered) { return true }
        return Self.remainingLetterWeight(lowered) < 3
    }

    /// The name with generic parts removed, or nil if nothing meaningful remains.
    /// Used for the Original token and by Basic naming (3.7 "All files").
    ///
    /// A word is dropped when it is a UUID or hex run, has no letters (digits, dates,
    /// times, " (1)"), or when every letter run in it is a generic word or a month name
    /// ("IMG", "scan0001", "d’écran").
    public func strippedOriginal(_ fileName: String) -> String? {
        let base = FileExtension.split(fileName).base
        let words = WordTokenizer.words(base).filter { word in
            let lowered = word.lowercased()
            if GenericPatterns.isIdentifier(lowered) { return false }
            let runs = Self.letterRuns(lowered)
            if runs.isEmpty { return false }
            return runs.contains { run in
                !GenericWords.all.contains(TextFolding.key(run)) && MonthNames.month(for: run) == nil
            }
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    static func letterRuns(_ text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in text {
            if let scalar = character.unicodeScalars.first, scalar.properties.isAlphabetic, !character.isDecimalDigit {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// Letters left after removing identifiers, digits, dates and generic words.
    static func remainingLetterWeight(_ lowered: String) -> Int {
        var weight = 0
        for run in letterRuns(GenericPatterns.removeIdentifiers(lowered)) {
            if GenericWords.all.contains(TextFolding.key(run)) || MonthNames.month(for: run) != nil { continue }
            for character in run {
                weight += isDenseScript(character) ? 2 : 1
            }
        }
        return weight
    }

    static func isDenseScript(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF: return true // kana
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FFFF: return true // Han
        case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F: return true // Hangul
        default: return false
        }
    }
}

enum GenericPatterns {
    /// Structural patterns that the letter count cannot catch.
    static func matchesStructural(_ lowered: String) -> Bool {
        // Android: Screenshot_20261127-140512_Chrome, Screenshot_2026-11-27-14-05-12-123_com.app
        if lowered.hasPrefix("screenshot_") || lowered.hasPrefix("screen_recording_") || lowered.hasPrefix("screenrecorder") {
            let rest = lowered.drop(while: { $0 != "_" }).dropFirst()
            if let first = rest.first, first.isDecimalDigit { return true }
        }
        // Camera counters followed by an edit marker: IMG_1234-edited, DSC_0001_copy
        let parts = lowered.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " })
        if parts.count >= 2, let head = parts.first, GenericWords.cameraPrefixes.contains(String(head)),
           parts[1].allSatisfy(\.isDecimalDigit),
           parts.dropFirst(2).allSatisfy({ GenericWords.all.contains(TextFolding.key(String($0))) || $0.allSatisfy(\.isDecimalDigit) }) {
            return true
        }
        return false
    }

    /// Removes UUIDs and hex runs of 12+ characters.
    static func removeIdentifiers(_ lowered: String) -> String {
        var result = ""
        var run = ""
        func flush() {
            if isIdentifier(run) {
                result += " "
            } else {
                result += run
            }
            run = ""
        }
        for character in lowered {
            if character.isHexDigit || character == "-" {
                run.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }

    static func isIdentifier(_ text: String) -> Bool {
        let hex = text.filter(\.isHexDigit)
        guard hex.count >= 12 else { return false }
        // UUID: 8-4-4-4-12
        let groups = text.split(separator: "-", omittingEmptySubsequences: false)
        if groups.map(\.count) == [8, 4, 4, 4, 12], groups.allSatisfy({ $0.allSatisfy(\.isHexDigit) }) { return true }
        // A hex run of 12+ characters with at least one digit and one letter.
        for group in groups where group.count >= 12 && group.allSatisfy(\.isHexDigit) {
            if group.contains(where: \.isDecimalDigit), group.contains(where: \.isLetter) { return true }
        }
        return false
    }
}

/// Case-insensitive glob matching with `*` and `?`.
enum Glob {
    static func matches(_ pattern: String, _ text: String) -> Bool {
        let p = Array(TextFolding.caseKey(pattern))
        let t = Array(TextFolding.caseKey(text))
        var pi = 0, ti = 0, star = -1, mark = 0
        while ti < t.count {
            if pi < p.count, p[pi] == "?" || p[pi] == t[ti] {
                pi += 1; ti += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi; mark = ti; pi += 1
            } else if star >= 0 {
                pi = star + 1; mark += 1; ti = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
