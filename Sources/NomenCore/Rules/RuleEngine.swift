/// A condition in a filing rule (3.12).
public enum RuleCondition: Codable, Sendable, Hashable {
    case kindIs(KindRef)
    case sourceContains(String)
    case downloadDomainIs(String)
    case downloadDomainEndsWith(String)
    case isScreenshot(Bool)
    case appIs(String)
    case fileTypeIs(String)
    case originalNameContains(String)
}

public enum RuleMatchMode: String, Codable, Sendable, Hashable {
    case all, any
}

/// An ordered filing rule. The first enabled rule that matches wins (3.12).
public struct Rule: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var match: RuleMatchMode
    public var conditions: [RuleCondition]
    public var destinationID: String
    /// Optional subfolder pattern using {year}, {month}, {source} and {kind}.
    public var subfolderPattern: String

    public init(id: String, name: String, enabled: Bool = true, match: RuleMatchMode = .all,
                conditions: [RuleCondition], destinationID: String, subfolderPattern: String = "") {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.match = match
        self.conditions = conditions
        self.destinationID = destinationID
        self.subfolderPattern = subfolderPattern
    }
}

/// What rules can see about a processed file.
public struct RuleFacts: Sendable, Hashable, Codable {
    public var kind: KindRef
    public var source: String?
    public var downloadDomain: String?
    public var isScreenshot: Bool
    public var app: String?
    public var fileName: String
    public var originalName: String

    public init(kind: KindRef, source: String?, downloadDomain: String?, isScreenshot: Bool,
                app: String?, fileName: String, originalName: String) {
        self.kind = kind
        self.source = source
        self.downloadDomain = downloadDomain
        self.isScreenshot = isScreenshot
        self.app = app
        self.fileName = fileName
        self.originalName = originalName
    }
}

public enum RuleEngine {
    /// The first enabled rule that matches, or nil. Rules without conditions never match.
    public static func firstMatch(_ rules: [Rule], facts: RuleFacts) -> Rule? {
        rules.first { $0.enabled && matches($0, facts: facts) }
    }

    public static func matches(_ rule: Rule, facts: RuleFacts) -> Bool {
        guard !rule.conditions.isEmpty else { return false }
        switch rule.match {
        case .all: return rule.conditions.allSatisfy { evaluate($0, facts) }
        case .any: return rule.conditions.contains { evaluate($0, facts) }
        }
    }

    static func evaluate(_ condition: RuleCondition, _ facts: RuleFacts) -> Bool {
        switch condition {
        case .kindIs(let kind):
            return facts.kind == kind
        case .sourceContains(let text):
            guard let source = facts.source, !text.trimmed.isEmpty else { return false }
            return TextFolding.key(source).contains(TextFolding.key(text.trimmed))
        case .downloadDomainIs(let domain):
            guard let host = normalizedHost(facts.downloadDomain) else { return false }
            return host == normalizedHost(domain)
        case .downloadDomainEndsWith(let suffix):
            guard let host = normalizedHost(facts.downloadDomain), let suffix = normalizedHost(suffix) else { return false }
            return host == suffix || host.hasSuffix("." + suffix)
        case .isScreenshot(let value):
            return facts.isScreenshot == value
        case .appIs(let app):
            guard let factsApp = facts.app else { return false }
            return TextFolding.key(factsApp) == TextFolding.key(app.trimmed)
        case .fileTypeIs(let type):
            guard let ext = FileExtension.typeKey(facts.fileName) else { return false }
            return canonicalType(ext) == canonicalType(type.trimmed.lowercased().trimmingDot())
        case .originalNameContains(let text):
            guard !text.trimmed.isEmpty else { return false }
            return TextFolding.key(facts.originalName).contains(TextFolding.key(text.trimmed))
        }
    }

    static func normalizedHost(_ host: String?) -> String? {
        guard var host = host?.trimmed.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        while host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }

    static func canonicalType(_ ext: String) -> String {
        switch ext {
        case "jpeg": "jpg"
        case "tif": "tiff"
        case "htm": "html"
        case "heif": "heic"
        case "markdown": "md"
        default: ext
        }
    }
}

extension String {
    func trimmingDot() -> String { hasPrefix(".") ? String(dropFirst()) : self }
}

/// Renders a rule's subfolder pattern into path components (3.12, K3).
///
/// Field values are sanitized like names, "/" splits only the pattern itself, and empty,
/// "." and ".." components are dropped, so the result can never point outside the
/// destination.
public enum SubfolderPattern {
    public static func components(_ pattern: String, fields: NameFields, language: NameLanguage,
                                  customKinds: [CustomKind], options: CharacterOptions = CharacterOptions()) -> [String] {
        let year = fields.date.map { String($0.year) } ?? ""
        let month = fields.date.map { $0.month < 10 ? "0\($0.month)" : String($0.month) } ?? ""
        let source = PIIGuard.redact(fields.source ?? "").text
        let kind = fields.kind.label(in: language, customKinds: customKinds)
        var result: [String] = []
        for rawComponent in pattern.split(separator: "/", omittingEmptySubsequences: true) {
            var component = ""
            var remaining = Substring(rawComponent)
            while !remaining.isEmpty {
                if remaining.hasPrefix("{year}") { component += year; remaining.removeFirst(6) }
                else if remaining.hasPrefix("{month}") { component += month; remaining.removeFirst(7) }
                else if remaining.hasPrefix("{source}") { component += safe(source); remaining.removeFirst(8) }
                else if remaining.hasPrefix("{kind}") { component += safe(kind); remaining.removeFirst(6) }
                else { component.append(remaining.removeFirst()) }
            }
            let sanitized = Sanitizer.sanitizeComponent(component, options: options)
            guard !sanitized.isEmpty, sanitized != ".", sanitized != ".." else { continue }
            result.append(Sanitizer.fitBytes(sanitized, limit: Defaults.maxFileNameBytes))
        }
        return result
    }

    /// Field values never carry path syntax: separators become spaces.
    private static func safe(_ value: String) -> String {
        String(value.map { "/\\:".contains($0) ? " " : $0 })
    }

    public static let tokens = ["{year}", "{month}", "{source}", "{kind}"]
}
