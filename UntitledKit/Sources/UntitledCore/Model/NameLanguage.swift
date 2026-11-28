import Foundation

/// Languages Untitled can write names in. The UI is English (3.1); names follow the content
/// or a fixed language chosen in the style.
public enum NameLanguage: String, CaseIterable, Codable, Sendable, Hashable {
    case english = "en"
    case german = "de"
    case french = "fr"
    case italian = "it"
    case spanish = "es"
    case portuguese = "pt"
    case dutch = "nl"
    case japanese = "ja"
    case korean = "ko"
    case chineseSimplified = "zh-Hans"

    /// Maps a BCP-47 tag such as `de-CH` or `zh-Hans-CN` to a supported language.
    public init?(languageTag: String) {
        let lowered = languageTag.lowercased().replacingOccurrences(of: "_", with: "-")
        if lowered.hasPrefix("zh") {
            // Traditional Chinese is not a supported name language.
            if lowered.contains("hant") || lowered.hasSuffix("-tw") || lowered.hasSuffix("-hk") { return nil }
            self = .chineseSimplified
            return
        }
        let primary = lowered.split(separator: "-").first.map(String.init) ?? lowered
        guard let match = NameLanguage.allCases.first(where: { $0.rawValue == primary }) else { return nil }
        self = match
    }

    /// English name shown in the UI.
    public var displayName: String {
        switch self {
        case .english: "English"
        case .german: "German"
        case .french: "French"
        case .italian: "Italian"
        case .spanish: "Spanish"
        case .portuguese: "Portuguese"
        case .dutch: "Dutch"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .chineseSimplified: "Chinese (Simplified)"
        }
    }

    /// True when numeric dates in this language are written day-first, which settles
    /// ambiguous dates like 03.04.2026 (3.7). English is used both ways, so it settles nothing.
    public var settlesDayFirst: Bool {
        switch self {
        case .german, .french, .italian, .spanish, .portuguese, .dutch: true
        case .english, .japanese, .korean, .chineseSimplified: false
        }
    }

    /// Languages whose scripts have no letter case.
    public var isCaseless: Bool {
        switch self {
        case .japanese, .korean, .chineseSimplified: true
        default: false
        }
    }

    /// The word used when a name would otherwise be empty (3.10 step 9).
    public var fileWord: String {
        switch self {
        case .english: "File"
        case .german: "Datei"
        case .french: "Fichier"
        case .italian: "File"
        case .spanish: "Archivo"
        case .portuguese: "Arquivo"
        case .dutch: "Bestand"
        case .japanese: "ファイル"
        case .korean: "파일"
        case .chineseSimplified: "文件"
        }
    }
}
