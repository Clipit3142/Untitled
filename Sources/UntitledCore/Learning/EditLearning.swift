public import Foundation

/// A pattern detected in a user's edit of a proposed name (3.11).
public enum EditPattern: Codable, Sendable, Hashable {
    case caseChange(CaseMode)
    case partSeparatorChange(PartSeparator)
    case wordSeparatorChange(WordSeparator)
    case dateFormatChange(DateFormat)
    case datePositionChange(InferredStyle.DatePosition)
    case tokenRemoved(TokenKind)
    case tokenAdded(TokenKind)
    case wordReplaced(from: String, to: String)
    case shortened(maxLength: Int)
    case fillerRemoved

    /// Identifies "the same edit" when counting occurrences.
    public var key: String {
        switch self {
        case .caseChange(let mode): "case:\(mode.rawValue)"
        case .partSeparatorChange(let separator): "part:\(separator.rawValue)"
        case .wordSeparatorChange(let separator): "word:\(separator.rawValue)"
        case .dateFormatChange(let format): "dateFormat:\(format.rawValue)"
        case .datePositionChange(let position): "datePosition:\(position.rawValue)"
        case .tokenRemoved(let token): "removed:\(token.rawValue)"
        case .tokenAdded(let token): "added:\(token.rawValue)"
        case .wordReplaced(let from, let to): "replace:\(TextFolding.key(from))→\(TextFolding.key(to))"
        case .shortened(let length): "shortened:\(length)"
        case .fillerRemoved: "filler"
        }
    }

    /// The question on the suggestion card.
    public func question(occurrences: Int) -> String {
        let times = occurrences == 2 ? "twice" : "\(occurrences) times"
        switch self {
        case .caseChange(let mode): return "You changed names to \(mode.displayName) \(times). Always do this?"
        case .partSeparatorChange(let separator): return "You changed the separator between parts to \(separator.displayName) \(times). Always do this?"
        case .wordSeparatorChange(let separator): return "You changed the separator between words to \(separator.displayName) \(times). Always do this?"
        case .dateFormatChange(let format): return "You changed the date format to \(format.rawValue) \(times). Always do this?"
        case .datePositionChange(let position): return "You moved the date to the \(position == .start ? "start" : "end") \(times). Always do this?"
        case .tokenRemoved(let token): return "You removed the \(token.displayName) \(times). Always leave it out?"
        case .tokenAdded(let token): return "You added the \(token.displayName) \(times). Always include it?"
        case .wordReplaced(let from, let to): return "You changed ‘\(from)’ to ‘\(to)’ \(times). Always do this?"
        case .shortened(let length): return "You shortened names to about \(length) characters \(times). Always keep names this short?"
        case .fillerRemoved: return "You removed filler words \(times). Always remove them?"
        }
    }
}

extension CaseMode {
    public var displayName: String {
        switch self {
        case .title: "Title Case"
        case .sentence: "Sentence case"
        case .lowercase: "lowercase"
        case .uppercase: "UPPERCASE"
        case .camel: "camelCase"
        case .pascal: "PascalCase"
        case .asGenerated: "As generated"
        }
    }
}

extension PartSeparator {
    public var displayName: String {
        switch self {
        case .space: "a space"
        case .spacedHyphen: "a spaced hyphen"
        case .spacedEnDash: "a spaced en dash"
        case .underscore: "an underscore"
        case .hyphen: "a hyphen"
        case .dot: "a dot"
        }
    }
}

extension WordSeparator {
    public var displayName: String {
        switch self {
        case .space: "a space"
        case .hyphen: "a hyphen"
        case .underscore: "an underscore"
        case .dot: "a dot"
        case .none: "nothing"
        }
    }
}

extension TokenKind {
    public var displayName: String {
        switch self {
        case .date: "date"
        case .kind: "document type"
        case .source: "company or source"
        case .subject: "subject"
        case .app: "app name"
        case .original: "original name"
        case .text: "fixed text"
        }
    }
}

/// Finds the patterns in an edit (3.11 "Patterns detected").
public enum EditAnalyzer {
    public static func patterns(proposed: FormattedName, final finalName: String, style: NamingStyle, language: NameLanguage) -> [EditPattern] {
        let proposedBase = FileExtension.split(proposed.fileName).base
        let finalBase = FileExtension.split(finalName).base
        guard proposedBase != finalBase, !finalBase.trimmed.isEmpty else { return [] }

        var result: [EditPattern] = []
        let before = StyleInference.analyze(proposedBase)
        let after = StyleInference.analyze(finalBase)

        // Same words, different presentation.
        let beforeWords = before.restWords.map(TextFolding.key)
        let afterWords = after.restWords.map(TextFolding.key)
        if beforeWords == afterWords {
            if let mode = after.caseMode, mode != style.caseMode, mode != .asGenerated { result.append(.caseChange(mode)) }
            if let word = after.wordSeparator, word.rawValue != style.effectiveWordSeparator, !(word == .none && !(after.caseMode?.forcesNoWordSeparator ?? false)) {
                result.append(.wordSeparatorChange(word))
            }
        }
        if let part = after.partSeparator, part != style.partSeparator, before.partSeparator == style.partSeparator,
           after.datePosition != .none || after.tokens.count > 1 {
            result.append(.partSeparatorChange(part))
        }
        // Dates.
        if let format = after.dateFormat, before.dateFormat != nil, format != style.dateFormat {
            result.append(.dateFormatChange(format))
        }
        if before.datePosition != .none, after.datePosition != .none, before.datePosition != after.datePosition {
            result.append(.datePositionChange(after.datePosition))
        }
        if before.datePosition != .none, after.datePosition == .none { result.append(.tokenRemoved(.date)) }
        if before.datePosition == .none, after.datePosition != .none { result.append(.tokenAdded(.date)) }

        // Tokens removed: a rendered part no longer present.
        let finalKey = TextFolding.key(finalBase)
        for part in proposed.parts where part.token != .date && part.token != .subject {
            let partKey = TextFolding.key(part.text)
            let words = WordTokenizer.words(partKey)
            if !words.isEmpty, !words.contains(where: { finalKey.contains($0) }) {
                result.append(.tokenRemoved(part.token))
            }
        }

        // Word replacements and filler removal.
        let diff = wordDiff(beforeWords, afterWords)
        let beforeOriginal = before.restWords
        let afterOriginal = after.restWords
        for (removedIndex, addedIndex) in diff.replacements {
            result.append(.wordReplaced(from: beforeOriginal[removedIndex], to: afterOriginal[addedIndex]))
        }
        let filler = WordLists.fillerWords(language)
        if !diff.deletions.isEmpty, diff.insertions.isEmpty, diff.replacements.isEmpty,
           diff.deletions.allSatisfy({ filler.contains(beforeWords[$0]) }) {
            result.append(.fillerRemoved)
        }

        // Shortened: at least 20 % shorter and nothing new added.
        if finalBase.count * 5 <= proposedBase.count * 4, diff.insertions.isEmpty, diff.replacements.isEmpty {
            let target = max(Defaults.maxNameLengthRange.lowerBound, Int((Double(finalBase.count) / 10).rounded(.up)) * 10)
            if target < style.maxLength { result.append(.shortened(maxLength: target)) }
        }
        var seen: Set<String> = []
        return result.filter { seen.insert($0.key).inserted }
    }

    /// A word-level diff. Adjacent single deletions and insertions become replacements.
    static func wordDiff(_ a: [String], _ b: [String]) -> (deletions: [Int], insertions: [Int], replacements: [(Int, Int)]) {
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var i = 0, j = 0
        var deletions: [Int] = [], insertions: [Int] = [], replacements: [(Int, Int)] = []
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] { i += 1; j += 1; continue }
            let deleteNext = i < n && (j >= m || lcs[i + 1][j] >= lcs[i][j + 1])
            let insertNext = j < m && (i >= n || lcs[i][j + 1] > lcs[i + 1][j])
            if deleteNext, j < m, i < n, lcs[i + 1][j + 1] == lcs[i][j] {
                replacements.append((i, j)); i += 1; j += 1
            } else if deleteNext {
                deletions.append(i); i += 1
            } else if insertNext {
                insertions.append(j); j += 1
            } else {
                break
            }
        }
        return (deletions, insertions, replacements)
    }
}

/// One recorded edit pattern.
public struct EditEvent: Codable, Sendable, Hashable {
    public var pattern: EditPattern
    public var styleID: String
    public var date: Date

    public init(pattern: EditPattern, styleID: String, date: Date) {
        self.pattern = pattern
        self.styleID = styleID
        self.date = date
    }
}

/// The user's answers to suggestions.
public struct SuggestionAnswers: Codable, Sendable, Hashable {
    /// "Never ask" keys per style, kept until reset (I3).
    public var neverAsk: Set<String> = []
    /// "Not now": the time it was dismissed. The card returns only after a newer occurrence.
    public var notNow: [String: Date] = [:]
    /// "Always": applied patterns.
    public var accepted: Set<String> = []

    public init() {}

    static func key(_ styleID: String, _ patternKey: String) -> String { styleID + "|" + patternKey }
}

/// A suggestion card (3.11).
public struct Suggestion: Sendable, Hashable, Identifiable {
    public var id: String { SuggestionAnswers.key(styleID, pattern.key) }
    public var pattern: EditPattern
    public var styleID: String
    public var occurrences: Int
    public var question: String
}

public enum SuggestionEngine {
    /// Suggestions shown now: a pattern seen at least twice in 30 days for one style (I1),
    /// not answered with Never ask (I3) or Always, and not dismissed since its latest occurrence.
    public static func pending(events: [EditEvent], answers: SuggestionAnswers, now: Date) -> [Suggestion] {
        let windowStart = now.addingTimeInterval(-Defaults.learningWindow)
        var grouped: [String: [EditEvent]] = [:]
        var order: [String] = []
        for event in events where event.date >= windowStart && event.date <= now {
            let key = SuggestionAnswers.key(event.styleID, event.pattern.key)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(event)
        }
        return order.compactMap { key in
            guard let group = grouped[key], group.count >= Defaults.learningThreshold else { return nil }
            if answers.neverAsk.contains(key) || answers.accepted.contains(key) { return nil }
            if let dismissed = answers.notNow[key], let latest = group.map(\.date).max(), latest <= dismissed { return nil }
            let first = group[0]
            return Suggestion(pattern: first.pattern, styleID: first.styleID, occurrences: group.count,
                              question: first.pattern.question(occurrences: group.count))
        }
    }

    public enum Answer: Sendable { case always, notNow, neverAsk }

    /// Records an answer. Only Always returns a changed style; the other answers never
    /// touch the style (I2).
    public static func answer(_ answer: Answer, to suggestion: Suggestion, answers: inout SuggestionAnswers,
                              style: NamingStyle, now: Date) -> NamingStyle? {
        switch answer {
        case .always:
            answers.accepted.insert(suggestion.id)
            let updated = apply(suggestion.pattern, to: style)
            return updated == style ? nil : updated
        case .notNow:
            answers.notNow[suggestion.id] = now
            return nil
        case .neverAsk:
            answers.neverAsk.insert(suggestion.id)
            return nil
        }
    }

    /// The style change that "Always" makes.
    public static func apply(_ pattern: EditPattern, to style: NamingStyle) -> NamingStyle {
        var copy = style
        switch pattern {
        case .caseChange(let mode):
            copy.caseMode = mode
        case .partSeparatorChange(let separator):
            copy.partSeparator = separator
        case .wordSeparatorChange(let separator):
            copy.wordSeparator = separator
        case .dateFormatChange(let format):
            copy.dateFormat = format
            if !format.hasDay { copy.timeFormat = .off }
        case .datePositionChange(let position):
            for keyPath in [\NamingStyle.template, \NamingStyle.screenshotTemplate] {
                var template = copy[keyPath: keyPath]
                if let index = template.firstIndex(where: { $0.kind == .date }) {
                    let token = template.remove(at: index)
                    if position == .start { template.insert(token, at: 0) } else { template.append(token) }
                }
                copy[keyPath: keyPath] = template
            }
        case .tokenRemoved(let token):
            copy.template.removeAll { $0.kind == token && !$0.required }
            if !copy.template.contains(where: { $0.kind != .date && $0.kind != .text }) { return style }
        case .tokenAdded(let token):
            if !copy.template.contains(where: { $0.kind == token }) {
                copy.template.insert(TemplateToken(token), at: token == .date ? 0 : copy.template.count)
            }
        case .wordReplaced(let from, let to):
            copy.vocabulary.removeAll { TextFolding.caseKey($0.from) == TextFolding.caseKey(from) }
            copy.vocabulary.append(VocabularyRule(from: from, to: to))
            if Vocabulary.loop(in: copy.vocabulary) != nil { return style }
        case .shortened(let length):
            copy.maxLength = min(max(length, Defaults.maxNameLengthRange.lowerBound), Defaults.maxNameLengthRange.upperBound)
        case .fillerRemoved:
            copy.removeFillerWords = true
        }
        copy = StyleValidator.normalized(copy)
        guard StyleValidator.isValid(copy) else { return style }
        if copy != style { copy.version = style.version + 1 }
        return copy
    }
}

/// Accepted final names used as examples (3.11): 20 per style are stored and the newest
/// 5 go into prompts. Only names are stored.
public struct ExampleList: Codable, Sendable, Hashable {
    public private(set) var names: [String]

    public init(names: [String] = []) {
        self.names = Array(names.suffix(Defaults.examplesStored))
    }

    /// Adds an accepted name as the newest example. A repeated name moves to newest.
    public mutating func add(_ name: String) {
        let trimmed = String(name.prefix(Defaults.storedFieldMaxCharacters))
        names.removeAll { $0 == trimmed }
        names.append(trimmed)
        if names.count > Defaults.examplesStored { names.removeFirst(names.count - Defaults.examplesStored) }
    }

    public mutating func remove(_ name: String) {
        names.removeAll { $0 == name }
    }

    /// The newest examples, newest last, for the prompt.
    public var forPrompt: [String] { Array(names.suffix(Defaults.examplesUsed)) }
}
