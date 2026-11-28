/// Applies a case mode to the words of one token (3.10 step 4).
///
/// Rules:
/// - Protected words keep their casing in Title, Sentence and As generated; in lowercase,
///   UPPERCASE, camelCase and PascalCase the case setting wins.
/// - Title and Sentence keep acronyms (2–4 letters, all capitals) and mixed-case words
///   ("eBay", "McDonald"), unless the whole token is written in capitals, which is read
///   as shouting and lowered first.
/// - Title Case lowers small words (English, French, German, Italian, Spanish, Portuguese)
///   except at the start and end of the token, capitalizes each hyphen part, and handles
///   elisions such as "l'offre" → "L'Offre" and "carte d'embarquement" → "Carte d'Embarquement".
/// - Sentence case capitalizes the first word of the token. German keeps the generated
///   casing of later words, because German capitalization is lexical.
/// - camelCase and PascalCase split words at hyphens and elisions, remove apostrophes,
///   and join the parts without a separator.
/// - Scripts without case are unchanged by every mode.
public struct CaseTransformer: Sendable {
    public let mode: CaseMode
    public let language: NameLanguage
    private let protected: [String: String]

    public init(mode: CaseMode, language: NameLanguage, protectedWords: [String]) {
        self.mode = mode
        self.language = language
        self.protected = protectedWords == WordLists.builtInProtectedWords
            ? Self.builtInProtectedMap : Self.protectedMap(protectedWords)
    }

    private static let builtInProtectedMap = protectedMap(WordLists.builtInProtectedWords)

    private static func protectedMap(_ words: [String]) -> [String: String] {
        var map: [String: String] = [:]
        for word in words {
            let trimmed = word.trimmed
            guard !trimmed.isEmpty else { continue }
            map[TextFolding.caseKey(trimmed)] = trimmed
        }
        return map
    }

    public func apply(_ words: [String]) -> [String] {
        guard !words.isEmpty else { return [] }
        switch mode {
        case .asGenerated:
            return words.map { protectedForm($0) ?? $0 }
        case .lowercase:
            return words.map { $0.lowercased() }
        case .uppercase:
            return words.map { $0.uppercased() }
        case .title:
            return title(words)
        case .sentence:
            return sentence(words)
        case .camel, .pascal:
            return camel(words, pascal: mode == .pascal)
        }
    }

    // MARK: Title

    private func title(_ words: [String]) -> [String] {
        let shouting = Self.isShouting(words)
        let small = WordLists.titleSmallWords(language)
        let lastIndex = words.count - 1
        return words.enumerated().map { index, word in
            if let protectedWord = protectedForm(word) { return protectedWord }
            if !shouting, Self.isMixedCase(word) || Self.isAcronym(word) { return word }
            let base = shouting ? word.lowercased() : word
            let isEdge = index == 0 || index == lastIndex
            if !isEdge, small.contains(base.lowercased()) { return base.lowercased() }
            return titleWord(base, isFirstWord: index == 0, smallWords: small)
        }
    }

    private func titleWord(_ word: String, isFirstWord: Bool, smallWords: Set<String>) -> String {
        let segments = word.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        return segments.enumerated().map { index, segment in
            if index > 0, smallWords.contains(segment.lowercased()) { return segment.lowercased() }
            return titleSegment(segment, isFirst: isFirstWord && index == 0, smallWords: smallWords)
        }.joined(separator: "-")
    }

    private func titleSegment(_ segment: String, isFirst: Bool, smallWords: Set<String>) -> String {
        if let apostrophe = segment.firstIndex(where: { $0 == "'" || $0 == "\u{2019}" }) {
            let prefix = String(segment[..<apostrophe])
            let rest = String(segment[segment.index(after: apostrophe)...])
            if (1...2).contains(prefix.count), rest.contains(where: \.isLetter) {
                let prefixOut = !isFirst && smallWords.contains(prefix.lowercased())
                    ? prefix.lowercased() : capitalize(prefix)
                return prefixOut + String(segment[apostrophe]) + capitalize(rest)
            }
        }
        return capitalize(segment)
    }

    // MARK: Sentence

    private func sentence(_ words: [String]) -> [String] {
        let shouting = Self.isShouting(words)
        return words.enumerated().map { index, word in
            if let protectedWord = protectedForm(word) { return protectedWord }
            if !shouting, Self.isMixedCase(word) || Self.isAcronym(word) { return word }
            let base = shouting ? word.lowercased() : word
            if index == 0 { return capitalize(base) }
            if language == .german, !shouting { return base }
            return base.lowercased()
        }
    }

    // MARK: camelCase / PascalCase

    private func camel(_ words: [String], pascal: Bool) -> [String] {
        var parts: [String] = []
        for word in words {
            for segment in word.split(separator: "-") {
                var segment = String(segment)
                if let apostrophe = segment.firstIndex(where: { $0 == "'" || $0 == "\u{2019}" }),
                   (1...2).contains(segment.distance(from: segment.startIndex, to: apostrophe)) {
                    parts.append(String(segment[..<apostrophe]))
                    segment = String(segment[segment.index(after: apostrophe)...])
                }
                segment.removeAll { $0 == "'" || $0 == "\u{2019}" }
                if !segment.isEmpty { parts.append(segment) }
            }
        }
        return parts.enumerated().map { index, part in
            if index == 0, !pascal { return part.lowercased() }
            guard let first = part.first, !first.isDecimalDigit else { return part.lowercased() }
            return String(first).uppercased() + part.dropFirst().lowercased()
        }
    }

    // MARK: Helpers

    private func protectedForm(_ word: String) -> String? {
        guard mode.keepsProtectedCasing else { return nil }
        return protected[TextFolding.caseKey(word)]
    }

    /// Capitalizes the first letter and lowers the rest. Words starting with a digit
    /// ("2nd", "3D") are unchanged. Dutch "ij" becomes "IJ".
    private func capitalize(_ word: String) -> String {
        guard let first = word.first else { return word }
        if first.isDecimalDigit { return word }
        let lower = word.lowercased()
        if language == .dutch, lower.hasPrefix("ij") {
            return "IJ" + lower.dropFirst(2)
        }
        guard let firstLower = lower.first else { return word }
        return String(firstLower).uppercased() + lower.dropFirst()
    }

    static func isShouting(_ words: [String]) -> Bool {
        let cased = words.filter { word in word.filter { $0.isLetter && ($0.isUppercase || $0.isLowercase) }.count >= 2 }
        guard cased.count >= 2 else { return false }
        return cased.allSatisfy { word in !word.contains(where: { $0.isLowercase }) }
    }

    static func isAcronym(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        guard (2...4).contains(letters.count) else { return false }
        guard letters.allSatisfy({ $0.isUppercase }) else { return false }
        return word.allSatisfy { $0.isLetter || $0.isDecimalDigit || $0 == "&" }
    }

    static func isMixedCase(_ word: String) -> Bool {
        var sawLower = false
        for character in word where character.isLetter {
            if character.isLowercase { sawLower = true } else if character.isUppercase, sawLower { return true }
        }
        return false
    }
}
