public import UntitledCore

/// "Why this name?" (3.15, M2): one line for every part of the name.
public enum WhyThisName {
    public struct Row: Sendable, Hashable, Identifiable {
        public var id: Int
        public var label: String
        public var text: String
        public var explanation: String
    }

    public static func rows(for proposal: Proposal) -> [Row] {
        var rows = proposal.parts.enumerated().map { index, part in
            Row(id: index, label: label(part.token), text: part.text,
                explanation: proposal.evidence.first { $0.token == part.token }?.explanation ?? fallback(part.token, proposal: proposal))
        }
        if let reason = proposal.basicReason {
            rows.append(Row(id: rows.count, label: "Naming", text: "Basic", explanation: reason))
        } else if proposal.path == .basic {
            rows.append(Row(id: rows.count, label: "Naming", text: "Basic", explanation: "Named from keywords and titles, without Apple Intelligence."))
        }
        for reason in proposal.lowReasons {
            rows.append(Row(id: rows.count, label: "Low confidence", text: "", explanation: reason.explanation))
        }
        return rows
    }

    public static func label(_ token: TokenKind) -> String {
        switch token {
        case .date: "Date"
        case .kind: "Kind"
        case .source: "Source"
        case .subject: "Subject"
        case .app: "App"
        case .original: "Original name"
        case .text: "Fixed text"
        }
    }

    static func fallback(_ token: TokenKind, proposal: Proposal) -> String {
        switch token {
        case .date:
            switch proposal.fields.dateSource {
            case .content?: "A date found in the file."
            case .capture?: "When the screenshot was taken."
            case .added?: "When the file was added to the folder."
            case .created?: "When the file was created."
            case nil: "The file's date."
            }
        case .kind: "What kind of file this is, from its content."
        case .source: "Who the file comes from, as written in it."
        case .subject: "What the file is about, from its title and text."
        case .app: "The app in front when the screenshot was taken."
        case .original: "Kept from the file's original name."
        case .text: "Fixed text from your style."
        }
    }
}
