public import UntitledCore
public import Foundation

/// Labels and editing for filing rules (3.12, 3.15 Rules).
public enum RuleEditing {
    public enum ConditionKind: String, Sendable, Hashable, CaseIterable, Identifiable {
        case kind, source, domainIs, domainEndsWith, screenshot, app, fileType, originalName

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .kind: "Kind is"
            case .source: "Source contains"
            case .domainIs: "Downloaded from"
            case .domainEndsWith: "Download domain ends with"
            case .screenshot: "Is a screenshot"
            case .app: "Screenshot app is"
            case .fileType: "File type is"
            case .originalName: "Original name contains"
            }
        }

        public var placeholder: RuleCondition {
            switch self {
            case .kind: .kindIs(.builtIn(.invoice))
            case .source: .sourceContains("")
            case .domainIs: .downloadDomainIs("")
            case .domainEndsWith: .downloadDomainEndsWith("")
            case .screenshot: .isScreenshot(true)
            case .app: .appIs("")
            case .fileType: .fileTypeIs("pdf")
            case .originalName: .originalNameContains("")
            }
        }
    }

    public static func kind(of condition: RuleCondition) -> ConditionKind {
        switch condition {
        case .kindIs: .kind
        case .sourceContains: .source
        case .downloadDomainIs: .domainIs
        case .downloadDomainEndsWith: .domainEndsWith
        case .isScreenshot: .screenshot
        case .appIs: .app
        case .fileTypeIs: .fileType
        case .originalNameContains: .originalName
        }
    }

    /// The condition's text value, for the conditions that take one.
    public static func text(of condition: RuleCondition) -> String? {
        switch condition {
        case .sourceContains(let value), .downloadDomainIs(let value), .downloadDomainEndsWith(let value),
             .appIs(let value), .fileTypeIs(let value), .originalNameContains(let value): value
        case .kindIs, .isScreenshot: nil
        }
    }

    public static func with(text: String, _ condition: RuleCondition) -> RuleCondition {
        switch condition {
        case .sourceContains: .sourceContains(text)
        case .downloadDomainIs: .downloadDomainIs(text)
        case .downloadDomainEndsWith: .downloadDomainEndsWith(text)
        case .appIs: .appIs(text)
        case .fileTypeIs: .fileTypeIs(text)
        case .originalNameContains: .originalNameContains(text)
        case .kindIs, .isScreenshot: condition
        }
    }

    /// A one-line summary, for the rule list and VoiceOver.
    public static func summary(_ rule: Rule, destination: String?) -> String {
        let joiner = rule.match == .all ? " and " : " or "
        let conditions = rule.conditions.map { condition -> String in
            let title = kind(of: condition).title.lowercased()
            switch condition {
            case .kindIs(let kind): return title + " " + kind.schemaValue(customKinds: [])
            case .isScreenshot(let value): return value ? "is a screenshot" : "is not a screenshot"
            default: return title + " “" + (text(of: condition) ?? "") + "”"
            }
        }.joined(separator: joiner)
        let target = destination.map { " → " + $0 } ?? ""
        return (conditions.isEmpty ? "Every file" : "When " + conditions) + target
    }

    public static func move(_ rules: inout [Rule], from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { rules[$0] }
        var remaining = rules.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertAt, remaining.count)))
        rules = remaining
    }
}
