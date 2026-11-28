public import UntitledCore
import Foundation

/// Editing operations and labels for the Styles screen (3.15). The view keeps a draft style and
/// saves it only when `StyleValidator` finds no issues (H7).
public enum StyleEditing {
    public static func move(_ template: inout [TemplateToken], from source: Int, to destination: Int) {
        guard template.indices.contains(source), destination >= 0, destination <= template.count else { return }
        let token = template.remove(at: source)
        template.insert(token, at: min(destination > source ? destination - 1 : destination, template.count))
    }

    public static func toggleRequired(_ template: inout [TemplateToken], at index: Int) {
        guard template.indices.contains(index) else { return }
        template[index].required.toggle()
    }

    public static func remove(_ template: inout [TemplateToken], at index: Int) {
        guard template.indices.contains(index) else { return }
        template.remove(at: index)
    }

    /// Tokens that can still be added (fixed text can be added any number of times).
    public static func addable(to template: [TemplateToken], screenshot: Bool) -> [TokenKind] {
        let used = Set(template.map(\.kind))
        return TokenKind.allCases.filter { kind in
            if kind == .text { return true }
            if kind == .app && !screenshot { return false }
            return !used.contains(kind)
        }
    }

    public static func chipTitle(_ token: TemplateToken) -> String {
        let base = token.kind == .text ? "“\(token.text ?? "")”" : WhyThisName.label(token.kind)
        return token.required ? base + " (required)" : base
    }

    public static func label(_ separator: PartSeparator) -> String {
        switch separator {
        case .space: "Space"
        case .spacedHyphen: "Spaced hyphen ( - )"
        case .spacedEnDash: "Spaced en dash ( – )"
        case .underscore: "Underscore ( _ )"
        case .hyphen: "Hyphen ( - )"
        case .dot: "Dot ( . )"
        }
    }

    public static func label(_ separator: WordSeparator) -> String {
        switch separator {
        case .space: "Space"
        case .hyphen: "Hyphen"
        case .underscore: "Underscore"
        case .dot: "Dot"
        case .none: "None"
        }
    }

    public static func label(_ mode: CaseMode) -> String {
        switch mode {
        case .title: "Title Case"
        case .sentence: "Sentence case"
        case .lowercase: "lowercase"
        case .uppercase: "UPPERCASE"
        case .camel: "camelCase"
        case .pascal: "PascalCase"
        case .asGenerated: "As generated"
        }
    }

    public static func label(_ format: DateFormat) -> String { format.rawValue }

    public static func label(_ format: TimeFormat) -> String {
        switch format {
        case .off: "Off"
        case .dotted: "14.03"
        case .compact: "1403"
        }
    }

    public static func label(_ source: DateSource) -> String {
        switch source {
        case .content: "Date in the file"
        case .capture: "Capture date"
        case .added: "Date added"
        case .created: "Date created"
        }
    }

    /// Parses a comma-separated list field (protected words, never include).
    public static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
