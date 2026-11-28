public import UntitledCore

/// Builds the fixed instructions and the prompt (3.8).
public enum PromptBuilder {
    /// The instructions, fixed per style version. The wording is from 3.8.
    public static func instructions(style: NamingStyle, language: NameLanguage) -> String {
        let vocabulary = style.vocabulary.map(\.to).filter { !$0.isEmpty }
        let preferred = vocabulary.isEmpty ? "none" : vocabulary.joined(separator: ", ")
        let avoid = style.neverInclude.isEmpty ? "none" : style.neverInclude.joined(separator: ", ")
        return """
            You name files. Fill the fields using only information in the provided content and metadata. \
            Prefer concrete words (company, product, document type) over generic ones. \
            Subject: at most \(style.subjectWords) words, no dates, no numbers longer than 8 digits. \
            Never include account numbers, card numbers, IBANs, phone numbers, email addresses, passwords or ID numbers. \
            Write in \(language.displayName). Preferred words: \(preferred). Avoid: \(avoid). \
            If the content is unreadable, use kind Other and a short visual description.
            """
    }

    /// Prompt order: metadata, then content, then (as an attachment) the image, then up to 5 approved names.
    public static func prompt(metadata: [String], content: [String], examples: [String]) -> String {
        var sections: [String] = []
        if !metadata.isEmpty { sections.append("Metadata:\n" + metadata.map { "- " + $0 }.joined(separator: "\n")) }
        if !content.isEmpty { sections.append("Content:\n" + content.joined(separator: "\n")) }
        let names = Array(examples.suffix(Defaults.promptExamples))
        if !names.isEmpty { sections.append("Names the user approved in this style:\n" + names.map { "- " + $0 }.joined(separator: "\n")) }
        return sections.joined(separator: "\n\n")
    }

    /// Metadata lines, including the numbered date candidates the model chooses from.
    public static func metadata(originalName: String?, downloadDomain: String?, app: String?, isScreenshot: Bool,
                                kindHint: String?, candidates: [DateCandidate], labels: [String]) -> [String] {
        var lines: [String] = []
        if let originalName { lines.append("Original name: \(originalName)") }
        if let downloadDomain { lines.append("Downloaded from: \(downloadDomain)") }
        if let app { lines.append("App: \(app)") }
        if isScreenshot { lines.append("This is a screenshot.") }
        if let kindHint { lines.append("File type: \(kindHint)") }
        if !labels.isEmpty { lines.append("Image shows: \(labels.joined(separator: ", "))") }
        if !candidates.isEmpty {
            lines.append("Dates found: " + candidates.map { "\($0.index) = “\($0.snippet)”" }.joined(separator: "; "))
        }
        return lines
    }
}
