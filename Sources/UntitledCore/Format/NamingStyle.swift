/// A template token (3.10). Each token is Required or Optional.
public enum TokenKind: String, Codable, Sendable, Hashable, CaseIterable {
    case date, kind, source, subject, app, original, text
}

public struct TemplateToken: Codable, Sendable, Hashable {
    public var kind: TokenKind
    public var required: Bool
    /// The fixed text for `.text` tokens, used as typed (sanitized only).
    public var text: String?

    public init(_ kind: TokenKind, required: Bool = false, text: String? = nil) {
        self.kind = kind
        self.required = required
        self.text = text
    }

    public static func date(required: Bool = false) -> TemplateToken { .init(.date, required: required) }
    public static func kind(required: Bool = false) -> TemplateToken { .init(.kind, required: required) }
    public static func source(required: Bool = false) -> TemplateToken { .init(.source, required: required) }
    public static func subject(required: Bool = false) -> TemplateToken { .init(.subject, required: required) }
    public static func app(required: Bool = false) -> TemplateToken { .init(.app, required: required) }
    public static func original(required: Bool = false) -> TemplateToken { .init(.original, required: required) }
    public static func text(_ value: String, required: Bool = false) -> TemplateToken {
        .init(.text, required: required, text: value)
    }
}

public enum PartSeparator: String, Codable, Sendable, Hashable, CaseIterable {
    case space = " "
    case spacedHyphen = " - "
    case spacedEnDash = " – "
    case underscore = "_"
    case hyphen = "-"
    case dot = "."
}

public enum WordSeparator: String, Codable, Sendable, Hashable, CaseIterable {
    case space = " "
    case hyphen = "-"
    case underscore = "_"
    case dot = "."
    case none = ""
}

public enum CaseMode: String, Codable, Sendable, Hashable, CaseIterable {
    case title, sentence, lowercase, uppercase, camel, pascal, asGenerated

    /// camelCase and PascalCase force the word separator to none (3.10).
    public var forcesNoWordSeparator: Bool { self == .camel || self == .pascal }
    /// Protected words keep their casing only in these modes (3.10).
    public var keepsProtectedCasing: Bool { self == .title || self == .sentence || self == .asGenerated }
}

public enum DateFormat: String, Codable, Sendable, Hashable, CaseIterable {
    case iso = "2026-11-27"
    case compact = "20261127"
    case yearMonth = "2026-11"
    case dotted = "27.11.2026"
    case dayMonthYearDash = "27-11-2026"
    case monthDayYearDash = "11-27-2026"
    case dayMonthNameYear = "27 Nov 2026"

    public var hasDay: Bool { self != .yearMonth }
}

public enum TimeFormat: String, Codable, Sendable, Hashable, CaseIterable {
    case off
    case dotted = "HH.MM"
    case compact = "HHMM"
}

public enum ExtensionCase: String, Codable, Sendable, Hashable, CaseIterable {
    case keep, lowercase
}

public struct CharacterOptions: Codable, Sendable, Hashable {
    public var removeAccents = false
    public var asciiOnly = false
    public var windowsSafe = false
    public var allowEmoji = false

    public init(removeAccents: Bool = false, asciiOnly: Bool = false, windowsSafe: Bool = false, allowEmoji: Bool = false) {
        self.removeAccents = removeAccents
        self.asciiOnly = asciiOnly
        self.windowsSafe = windowsSafe
        self.allowEmoji = allowEmoji
    }
}

/// The preferences that turn fields into a name (3.3, 3.10).
public struct NamingStyle: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// Incremented on every saved change; recorded in history (3.14) and prompts (3.8).
    public var version: Int
    public var template: [TemplateToken]
    public var screenshotTemplate: [TemplateToken]
    public var partSeparator: PartSeparator
    public var wordSeparator: WordSeparator
    public var caseMode: CaseMode
    public var dateFormat: DateFormat
    public var dateOrder: [DateSource]
    public var timeFormat: TimeFormat
    public var maxLength: Int
    public var subjectWords: Int
    /// nil means "Same as content".
    public var nameLanguage: NameLanguage?
    public var characters: CharacterOptions
    public var extensionCase: ExtensionCase
    public var vocabulary: [VocabularyRule]
    public var protectedWords: [String]
    public var neverInclude: [String]
    public var removeFillerWords: Bool

    public init(
        id: String = "default",
        name: String = "Clean",
        version: Int = 1,
        template: [TemplateToken] = [.date(required: true), .source(), .kind(), .subject(required: true)],
        screenshotTemplate: [TemplateToken] = [.date(required: true), .app(), .subject(required: true)],
        partSeparator: PartSeparator = .space,
        wordSeparator: WordSeparator = .space,
        caseMode: CaseMode = .title,
        dateFormat: DateFormat = .iso,
        dateOrder: [DateSource] = [.content, .capture, .added, .created],
        timeFormat: TimeFormat = .off,
        maxLength: Int = Defaults.maxNameLength,
        subjectWords: Int = Defaults.subjectWords,
        nameLanguage: NameLanguage? = nil,
        characters: CharacterOptions = CharacterOptions(),
        extensionCase: ExtensionCase = .keep,
        vocabulary: [VocabularyRule] = WordLists.builtInVocabulary,
        protectedWords: [String] = WordLists.builtInProtectedWords,
        neverInclude: [String] = [],
        removeFillerWords: Bool = false
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.template = template
        self.screenshotTemplate = screenshotTemplate
        self.partSeparator = partSeparator
        self.wordSeparator = wordSeparator
        self.caseMode = caseMode
        self.dateFormat = dateFormat
        self.dateOrder = dateOrder
        self.timeFormat = timeFormat
        self.maxLength = maxLength
        self.subjectWords = subjectWords
        self.nameLanguage = nameLanguage
        self.characters = characters
        self.extensionCase = extensionCase
        self.vocabulary = vocabulary
        self.protectedWords = protectedWords
        self.neverInclude = neverInclude
        self.removeFillerWords = removeFillerWords
    }

    /// The word separator actually used: none for camelCase and PascalCase.
    public var effectiveWordSeparator: String {
        caseMode.forcesNoWordSeparator ? "" : wordSeparator.rawValue
    }

    /// Collision suffix separator: the word separator, or "-" when there is none (3.13).
    public var suffixSeparator: String {
        let separator = effectiveWordSeparator
        return separator.isEmpty ? "-" : separator
    }

    public func template(forScreenshot isScreenshot: Bool) -> [TemplateToken] {
        isScreenshot ? screenshotTemplate : template
    }
}

public enum Presets {
    /// Clean (default): `2026-11-27 Swisscom Invoice Mobile Subscription November`.
    public static let clean = NamingStyle(id: "preset.clean", name: "Clean")

    /// Compact: `20261127_swisscom_invoice_mobile_subscription_november`.
    public static let compact = NamingStyle(
        id: "preset.compact", name: "Compact",
        partSeparator: .underscore, wordSeparator: .underscore, caseMode: .lowercase, dateFormat: .compact
    )

    /// Descriptive (max length 80): `Invoice – Mobile Subscription November – Swisscom – 2026-11-27`.
    public static let descriptive = NamingStyle(
        id: "preset.descriptive", name: "Descriptive",
        template: [.kind(), .subject(required: true), .source(), .date(required: true)],
        screenshotTemplate: [.app(), .subject(required: true), .date(required: true)],
        partSeparator: .spacedEnDash, maxLength: 80
    )

    /// Kebab: `2026-11-27-swisscom-invoice-mobile-subscription-november`.
    public static let kebab = NamingStyle(
        id: "preset.kebab", name: "Kebab",
        partSeparator: .hyphen, wordSeparator: .hyphen, caseMode: .lowercase
    )

    public static let all: [NamingStyle] = [clean, compact, descriptive, kebab]
}
