/// Reasons a style cannot be saved (H7). Each has a one-line explanation for the UI.
public enum StyleIssue: Sendable, Hashable, CustomStringConvertible {
    case maxLengthOutOfRange(Int)
    case subjectWordsOutOfRange(Int)
    case emptyTemplate(screenshot: Bool)
    case noNamingToken(screenshot: Bool)
    case duplicateToken(TokenKind, screenshot: Bool)
    case emptyFixedText
    case noSeparatorRequiresCamelOrPascal
    case timeNeedsDay
    case dateOrderInvalid
    case vocabularyEmptyFrom
    case vocabularyLoop(from: String, to: String)
    case emptyProtectedWord
    case neverIncludeRemovesMonthName(String)
    case asciiOnlyWithEnDash
    case emptyName

    public var description: String {
        switch self {
        case .maxLengthOutOfRange(let value):
            "Max length must be between 20 and 150 characters (now \(value))."
        case .subjectWordsOutOfRange(let value):
            "Subject words must be between 1 and 12 (now \(value))."
        case .emptyTemplate(let screenshot):
            "The \(screenshot ? "screenshot " : "")template needs at least one token."
        case .noNamingToken(let screenshot):
            "The \(screenshot ? "screenshot " : "")template needs a token other than Date and fixed text."
        case .duplicateToken(let kind, let screenshot):
            "The \(screenshot ? "screenshot " : "")template uses \(kind.rawValue.capitalized) twice."
        case .emptyFixedText:
            "Fixed text can't be empty."
        case .noSeparatorRequiresCamelOrPascal:
            "\"None\" between words is only available with camelCase and PascalCase."
        case .timeNeedsDay:
            "A time can only be added to a date format that includes the day."
        case .dateOrderInvalid:
            "Date order must list content, capture, added and created once each."
        case .vocabularyEmptyFrom:
            "A vocabulary replacement needs a word to replace."
        case .vocabularyLoop(let from, let to):
            "\"\(from) → \(to)\" creates a loop with another replacement."
        case .emptyProtectedWord:
            "Protected words can't be empty."
        case .neverIncludeRemovesMonthName(let word):
            "\"\(word)\" is a month name used in dates, so it can't be in Never include with this date format."
        case .asciiOnlyWithEnDash:
            "ASCII only can't be combined with the en dash separator, which isn't ASCII."
        case .emptyName:
            "The style needs a name."
        }
    }
}

public enum StyleValidator {
    /// Returns every issue that prevents saving. An empty array means the style is valid.
    public static func issues(_ style: NamingStyle) -> [StyleIssue] {
        var issues: [StyleIssue] = []
        if style.name.trimmed.isEmpty { issues.append(.emptyName) }
        if !Defaults.maxNameLengthRange.contains(style.maxLength) { issues.append(.maxLengthOutOfRange(style.maxLength)) }
        if !Defaults.subjectWordsRange.contains(style.subjectWords) { issues.append(.subjectWordsOutOfRange(style.subjectWords)) }
        for (template, isScreenshot) in [(style.template, false), (style.screenshotTemplate, true)] {
            if template.isEmpty { issues.append(.emptyTemplate(screenshot: isScreenshot)) }
            if !template.isEmpty, !template.contains(where: { $0.kind != .date && $0.kind != .text }) {
                issues.append(.noNamingToken(screenshot: isScreenshot))
            }
            var seen: Set<TokenKind> = []
            for token in template where token.kind != .text {
                if !seen.insert(token.kind).inserted { issues.append(.duplicateToken(token.kind, screenshot: isScreenshot)) }
            }
            for token in template where token.kind == .text {
                let sanitized = Sanitizer.sanitizeComponent(token.text ?? "", options: style.characters)
                if sanitized.isEmpty { issues.append(.emptyFixedText) }
            }
        }
        if style.wordSeparator == .none, !style.caseMode.forcesNoWordSeparator {
            issues.append(.noSeparatorRequiresCamelOrPascal)
        }
        if style.timeFormat != .off, !style.dateFormat.hasDay { issues.append(.timeNeedsDay) }
        if style.characters.asciiOnly, style.partSeparator == .spacedEnDash { issues.append(.asciiOnlyWithEnDash) }
        if Set(style.dateOrder) != Set(DateSource.allCases) || style.dateOrder.count != DateSource.allCases.count {
            issues.append(.dateOrderInvalid)
        }
        if style.vocabulary.contains(where: { WordTokenizer.words($0.from).isEmpty }) {
            issues.append(.vocabularyEmptyFrom)
        }
        if let rule = Vocabulary.loop(in: style.vocabulary) {
            issues.append(.vocabularyLoop(from: rule.from, to: rule.to))
        }
        if style.protectedWords.contains(where: { $0.trimmed.isEmpty }) { issues.append(.emptyProtectedWord) }
        if style.dateFormat == .dayMonthNameYear {
            let monthKeys = Set(NameLanguage.allCases.flatMap { MonthNames.abbreviations($0) }.map(TextFolding.key))
            for word in style.neverInclude where monthKeys.contains(TextFolding.key(word.trimmed)) {
                issues.append(.neverIncludeRemovesMonthName(word))
            }
        }
        return issues
    }

    public static func isValid(_ style: NamingStyle) -> Bool { issues(style).isEmpty }

    /// Applies the automatic adjustments the UI makes while editing: camelCase and
    /// PascalCase switch the word separator to none, and other cases leave none.
    public static func normalized(_ style: NamingStyle) -> NamingStyle {
        var copy = style
        if copy.caseMode.forcesNoWordSeparator {
            copy.wordSeparator = .none
        } else if copy.wordSeparator == .none {
            copy.wordSeparator = .space
        }
        return copy
    }
}
