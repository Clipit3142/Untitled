public import Foundation
public import UntitledCore
import UntitledFS
public import UntitledStore
public import UntitledModel

/// Settings the engine reads (3.15 Settings, 3.19).
public struct EngineSettings: Codable, Sendable, Hashable {
    public var stabilityWait: TimeInterval = Defaults.stabilityWait
    public var pdfPages: Int = Defaults.pdfPagesRead
    public var historyRetentionDays: Int? = Defaults.historyRetentionDays
    public var processing = ProcessingSettings()
    public var basicNamingOnly = false
    /// Image input ships only if spike 2 confirms it (3.21); off until then.
    public var imageInput = false

    public init() {}
}

/// System notifications (3.15). In-app actions never reach the presenter.
public protocol NotificationPresenting: Sendable {
    func postRenamed(operationID: Int64, oldName: String, newName: String)
    func postSummary(summaryID: String, operationIDs: [Int64])
    func removeRenamed(operationIDs: [Int64])
    func postReview(itemID: String, oldName: String, proposedName: String)
    func postBurst(groupID: String, count: Int)
}

/// Power and thermal state (3.19).
public protocol PowerMonitoring: Sendable {
    func conditions() -> PowerConditions
}

public struct FixedPower: PowerMonitoring {
    public var value: PowerConditions
    public init(_ value: PowerConditions = PowerConditions()) { self.value = value }
    public func conditions() -> PowerConditions { value }
}

/// Changes the UI listens to.
public enum EngineEvent: Sendable, Hashable {
    case queueChanged
    case historyChanged
    case statusChanged
    case foldersChanged
    case suggestionsChanged
    /// Styles, rules, destinations, kinds or examples changed.
    case libraryChanged
    case automaticOffer(folderID: String)
    case notice(String)
}

/// The status pill (3.15): "Watching Desktop and Downloads", "Paused until 06:00" …
public enum EngineStatus: Sendable, Hashable {
    case notWatching
    case watching(folderNames: [String])
    case paused(until: Date?)
    case held(HoldReason)
    case waitingForAppleIntelligence
    case basicNaming(folderNames: [String])
    case needsAttention(folderName: String)
    case working

    public func text(timeZone: TimeZone = .current) -> String {
        switch self {
        case .notWatching: return "Not watching any folders"
        case .watching(let names): return "Watching " + EngineStatus.list(names)
        case .paused(let until):
            guard let until else { return "Paused" }
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            return "Paused until " + formatter.string(from: until)
        case .held(.lowPowerMode): return "Paused in Low Power Mode"
        case .held(.thermal): return "Paused while your Mac is hot"
        case .held(.waitingForPower): return "Waiting until your Mac is plugged in"
        case .held(.userPaused): return "Paused"
        case .waitingForAppleIntelligence: return "Waiting for Apple Intelligence"
        case .basicNaming: return "Basic naming"
        case .needsAttention(let name): return "\(name) needs attention"
        case .working: return "Naming files…"
        }
    }

    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return "no folders"
        case 1: return names[0]
        case 2: return names[0] + " and " + names[1]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}

/// Undo results (3.14).
public enum UndoResult: Sendable, Hashable {
    case restored(path: String, collisionNumber: Int?)
    /// The file is outside the folders Untitled can use; ask for access to this folder (L3).
    case needsAccess(folder: String)
    case unavailable(reason: String)
}

/// Builds proposals from extraction results and generated fields (3.5 steps 5–7).
public struct ProposalBuilder: Sendable {
    public var style: NamingStyle
    public var customKinds: [CustomKind]
    public var rules: [Rule]
    public var destinations: [Destination]
    public var folders: [GrantedFolder]
    public var timeZone: TimeZone

    public init(style: NamingStyle, customKinds: [CustomKind], rules: [Rule], destinations: [Destination],
                folders: [GrantedFolder], timeZone: TimeZone) {
        self.style = style
        self.customKinds = customKinds
        self.rules = rules
        self.destinations = destinations
        self.folders = folders
        self.timeZone = timeZone
    }

    public func language(for extraction: UntitledExtractLanguage) -> NameLanguage {
        style.nameLanguage ?? extraction.detected ?? .english
    }

    /// Validates, formats, scores and files one proposal.
    public func proposal(currentName: String, generated: GeneratedFields, path: NamingPath, basicReason: BasicReason?,
                         evidence: Evidence, language: NameLanguage, app: String?, original: String?) -> Proposal {
        let validated = ProposalValidator.validate(generated, evidence: evidence, style: style, app: app, original: original, path: path)
        let signals = ConfidenceSignals(evidence: evidence, guardrailOrRefusal: basicReason?.forcesLowConfidence ?? false)
        var proposal = Proposal(
            fields: validated.fields, fileName: "", parts: [], evidence: validated.evidence, confidence: .low, lowReasons: [],
            styleID: style.id, styleVersion: style.version, path: path, language: language, isScreenshot: evidence.isScreenshot,
            signals: signals, basicReason: basicReason?.explanation
        )
        proposal = reformatted(proposal, currentName: currentName, downloadDomain: evidence.downloadDomain)
        return proposal
    }

    /// Re-formats a proposal from its stored fields: used for style changes and field edits,
    /// without calling the model (H8, M2).
    public func reformatted(_ proposal: Proposal, currentName: String, downloadDomain: String?) -> Proposal {
        var copy = proposal
        let context = FormatContext(language: proposal.language, customKinds: customKinds,
                                    fileExtension: FileExtension.split(currentName).extension, isScreenshot: proposal.isScreenshot)
        let formatted = NameFormatter.format(proposal.fields, style: style, context: context)
        copy.fileName = formatted.fileName
        copy.parts = formatted.parts
        copy.styleID = style.id
        copy.styleVersion = style.version
        (copy.confidence, copy.lowReasons) = ProposalValidator.confidence(formatted: formatted, signals: proposal.signals, currentName: currentName)
        let facts = RuleFacts(kind: proposal.fields.kind, source: proposal.fields.source, downloadDomain: downloadDomain,
                              isScreenshot: proposal.isScreenshot, app: proposal.fields.app, fileName: currentName, originalName: currentName)
        if let rule = RuleEngine.firstMatch(rules, facts: facts), let destination = destinations.first(where: { $0.id == rule.destinationID }) {
            copy.ruleID = rule.id
            copy.destinationID = destination.id
            let pattern = rule.subfolderPattern.isEmpty ? destination.subfolderPattern : rule.subfolderPattern
            copy.subfolder = SubfolderPattern.components(pattern, fields: proposal.fields, language: proposal.language,
                                                         customKinds: customKinds, options: style.characters)
        } else {
            copy.ruleID = nil
            copy.destinationID = nil
            copy.subfolder = []
        }
        return copy
    }

    /// The name for a collision attempt (3.13).
    public func name(for proposal: Proposal, currentName: String, collision: Int?) -> String {
        let context = FormatContext(language: proposal.language, customKinds: customKinds,
                                    fileExtension: FileExtension.split(currentName).extension,
                                    isScreenshot: proposal.isScreenshot, collisionNumber: collision)
        return NameFormatter.format(proposal.fields, style: style, context: context).fileName
    }
}

/// The detected content language, wrapped so the builder does not depend on extraction types.
public struct UntitledExtractLanguage: Sendable {
    public var detected: NameLanguage?
    public init(_ detected: NameLanguage?) { self.detected = detected }
}
