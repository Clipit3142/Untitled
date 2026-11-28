/// Settings tabs (3.15).
public enum SettingsTab: String, Sendable, Hashable, CaseIterable, Identifiable {
    case general, appleIntelligence, notifications, privacy, advanced

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .appleIntelligence: "Apple Intelligence"
        case .notifications: "Notifications"
        case .privacy: "Privacy"
        case .advanced: "Advanced"
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appleIntelligence: "apple.intelligence"
        case .notifications: "bell.badge"
        case .privacy: "hand.raised"
        case .advanced: "slider.horizontal.3"
        }
    }
}

/// Every setting, wherever it lives, with its one-line explanation (O4).
public enum SettingKey: String, Sendable, Hashable, CaseIterable {
    // Settings window
    case launchAtLogin, showInDock, pauseInLowPowerMode, renameSound
    case appleIntelligenceStatus, basicNamingOnly, onBattery
    case notifyRenamed, notifyReview, systemNotificationSettings
    case clearHistory, clearLearnedData, resetEverything
    case stabilityWait, pdfPages, historyRetention, exportDiagnostics
    // Folders
    case folderMode, folderStyle, onlyGenericNames, folderGenericPatterns, renameExisting
    // Styles
    case styleTemplate, screenshotTemplate, partSeparator, wordSeparator, caseMode, dateFormat, dateOrder
    case timeFormat, maxLength, subjectWords, nameLanguage, removeAccents, asciiOnly, windowsSafe, allowEmoji
    case extensionCase, vocabulary, protectedWords, neverInclude, removeFillerWords, examples
    // Rules
    case ruleConditions, ruleDestination, ruleSubfolderPattern
}

public struct SettingDescriptor: Sendable, Hashable, Identifiable {
    public var id: SettingKey { key }
    public var key: SettingKey
    public var title: String
    public var explanation: String
    /// The Settings tab, or nil for settings in the main window.
    public var tab: SettingsTab?
}

public enum SettingsCatalog {
    public static func descriptor(_ key: SettingKey) -> SettingDescriptor {
        let (title, explanation, tab) = entry(key)
        return SettingDescriptor(key: key, title: title, explanation: explanation, tab: tab)
    }

    public static func settings(in tab: SettingsTab) -> [SettingDescriptor] {
        SettingKey.allCases.map(descriptor).filter { $0.tab == tab }
    }

    public static let privacyStatement = """
    Everything stays on this Mac. Untitled has no internet access. It reads new files only to name them, \
    keeps what it reads in memory, and stores only names, paths, short fields and thumbnails.
    """

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func entry(_ key: SettingKey) -> (String, String, SettingsTab?) {
        switch key {
        case .launchAtLogin: ("Launch at login", "Starts Untitled when you log in, so new files are named right away.", .general)
        case .showInDock: ("Show in Dock", "Keeps Untitled in the Dock and ⌘-Tab even when no window is open.", .general)
        case .pauseInLowPowerMode: ("Pause in Low Power Mode", "Waits to name files while Low Power Mode is on, to save battery.", .general)
        case .renameSound: ("Rename sound", "Plays a quiet sound when a file is renamed automatically.", .general)
        case .appleIntelligenceStatus: ("Status", "Shows whether Apple Intelligence can name files on this Mac.", .appleIntelligence)
        case .basicNamingOnly: ("Use Basic naming only", "Names files from keywords and titles without Apple Intelligence.", .appleIntelligence)
        case .onBattery: ("On battery", "Choose whether files are named on battery or only when plugged in.", .appleIntelligence)
        case .notifyRenamed: ("Automatic renames", "Shows a notification with Undo after a file is renamed automatically.", .notifications)
        case .notifyReview: ("Files to review", "Shows a notification with Accept, Edit and Skip when a name is ready to review.", .notifications)
        case .systemNotificationSettings: ("Notification Settings…", "Opens System Settings to change banners, sounds and badges.", .notifications)
        case .clearHistory: ("Clear History…", "Deletes the Activity list and cached thumbnails. Renamed files keep their names.", .privacy)
        case .clearLearnedData: ("Clear Learned Data…", "Forgets the edits Untitled learned from and every suggestion answer.", .privacy)
        case .resetEverything: ("Reset Untitled…", "Removes every folder, style, rule, setting and history entry, as on first launch.", .privacy)
        case .stabilityWait: ("Stability wait", "How long a new file must stay unchanged before Untitled reads it.", .advanced)
        case .pdfPages: ("PDF pages read", "How many pages of a PDF are read to name it.", .advanced)
        case .historyRetention: ("Keep history", "How long Activity keeps renamed files, so you can undo them.", .advanced)
        case .exportDiagnostics: ("Export Diagnostics…", "Saves a report for support, with every name and path removed.", .advanced)
        case .folderMode: ("Mode", "Automatic renames new files, Review asks first, Off ignores the folder.", nil)
        case .folderStyle: ("Style", "The naming style used for files in this folder.", nil)
        case .onlyGenericNames: ("Only generic names", "Renames only files with names like “Screenshot…” or “Untitled”, and keeps names you chose.", nil)
        case .folderGenericPatterns: ("Also treat as generic", "Extra name patterns to rename in this folder, such as “IMG_*”.", nil)
        case .renameExisting: ("Rename Existing Files…", "Proposes names for files already in the folder; you review them first.", nil)
        case .styleTemplate: ("Template", "The parts of a name and their order. Required parts make the name Low confidence when missing.", nil)
        case .screenshotTemplate: ("Screenshot template", "The parts of a screenshot's name, which can include the app it was taken in.", nil)
        case .partSeparator: ("Between parts", "The characters placed between the date, source, kind and subject.", nil)
        case .wordSeparator: ("Between words", "The character placed between words inside a part.", nil)
        case .caseMode: ("Case", "How words are capitalized. camelCase and PascalCase remove the word separator.", nil)
        case .dateFormat: ("Date format", "How dates are written. Dates are never shortened to fit the length limit.", nil)
        case .dateOrder: ("Date preference", "Which date wins when a file has several: content, capture, added or created.", nil)
        case .timeFormat: ("Time", "Adds the time to screenshot dates, so names stay in order.", nil)
        case .maxLength: ("Max length", "The longest a name can be, without the extension, including any “2” suffix.", nil)
        case .subjectWords: ("Subject words", "The most words used to describe what the file is about.", nil)
        case .nameLanguage: ("Name language", "The language names are written in. “Same as content” follows each file.", nil)
        case .removeAccents: ("Remove accents", "Writes “é” as “e”, keeping letters from other scripts.", nil)
        case .asciiOnly: ("ASCII only", "Keeps only plain English letters, digits and basic punctuation.", nil)
        case .windowsSafe: ("Windows-safe", "Avoids characters and names Windows can't use, for files you share.", nil)
        case .allowEmoji: ("Allow emoji", "Keeps emoji that appear in a file's title.", nil)
        case .extensionCase: ("Extension", "Keeps the extension exactly as it is, or lowercases it.", nil)
        case .vocabulary: ("Vocabulary", "Words to always replace, such as “Bill” with “Invoice”.", nil)
        case .protectedWords: ("Protected words", "Words whose capitals are kept, such as “iPhone” or “PDF”.", nil)
        case .neverInclude: ("Never include", "Single words that never appear in a name.", nil)
        case .removeFillerWords: ("Remove filler words", "Drops words like “the” and “of” from subjects.", nil)
        case .examples: ("Examples", "Names you approved. The newest five guide Apple Intelligence; up to 20 are kept.", nil)
        case .ruleConditions: ("When", "The file details that must all match for this rule to apply.", nil)
        case .ruleDestination: ("Move to", "The folder matching files are moved to after renaming.", nil)
        case .ruleSubfolderPattern: ("Subfolder", "An optional subfolder made from the file's fields, such as “{year}/{source}”.", nil)
        }
    }
}
