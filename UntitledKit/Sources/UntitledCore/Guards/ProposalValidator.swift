import Foundation

/// Validates generated fields against evidence and computes confidence (3.9).
public enum ProposalValidator {
    public struct Validated: Sendable, Hashable {
        public var fields: NameFields
        public var evidence: [PartEvidence]
        public var sourceDropped: Bool
    }

    /// Turns generated fields into name fields that only contain what evidence supports.
    public static func validate(
        _ generated: GeneratedFields,
        evidence: Evidence,
        style: NamingStyle,
        app: String?,
        original: String?,
        path: NamingPath
    ) -> Validated {
        var notes: [PartEvidence] = []

        // Source: only if it matches the text, the download domain or the app name.
        var source: String?
        var sourceDropped = false
        if let candidate = generated.source?.trimmed, !candidate.isEmpty {
            if let reason = sourceEvidence(candidate, evidence: evidence, app: app) {
                source = candidate
                notes.append(PartEvidence(token: .source, explanation: reason))
            } else {
                sourceDropped = true
            }
        }

        // Date: the chosen candidate, otherwise the style's order of file dates.
        var date: DateValue?
        var dateSource: DateSource?
        for kind in style.dateOrder {
            switch kind {
            case .content:
                if let choice = generated.dateChoice, let candidate = evidence.dateCandidates.first(where: { $0.index == choice }) {
                    date = candidate.value
                    dateSource = .content
                    notes.append(PartEvidence(token: .date, explanation: "From the file: “\(candidate.snippet)”"))
                }
            case .capture:
                if let capture = evidence.captureDate {
                    date = capture
                    dateSource = .capture
                    notes.append(PartEvidence(token: .date, explanation: "When the screenshot was taken"))
                }
            case .added:
                if let added = evidence.dateAdded {
                    date = added
                    dateSource = .added
                    notes.append(PartEvidence(token: .date, explanation: "When the file was added to the folder"))
                }
            case .created:
                if let created = evidence.creationDate {
                    date = created
                    dateSource = .created
                    notes.append(PartEvidence(token: .date, explanation: "When the file was created"))
                }
            }
            if date != nil { break }
        }

        switch path {
        case .model:
            notes.append(PartEvidence(token: .kind, explanation: "Chosen by Apple Intelligence from the file's content"))
            notes.append(PartEvidence(token: .subject, explanation: "Summarized by Apple Intelligence from the file's content"))
        case .basic:
            notes.append(PartEvidence(token: .kind, explanation: generated.kind == .other
                ? "No document type was recognized" : "Recognized from a keyword in the file"))
            notes.append(PartEvidence(token: .subject, explanation: "From the most prominent line of text"))
        case .typed:
            break
        }
        if app != nil { notes.append(PartEvidence(token: .app, explanation: "The app in front when the screenshot was taken")) }
        if original != nil { notes.append(PartEvidence(token: .original, explanation: "From the file's original name")) }
        notes.append(PartEvidence(token: .text, explanation: "Fixed text from your style"))

        let fields = NameFields(
            kind: generated.kind,
            source: source,
            subject: generated.subject,
            date: date,
            dateSource: dateSource,
            app: app,
            original: original
        )
        return Validated(fields: fields, evidence: notes, sourceDropped: sourceDropped)
    }

    /// Explains where a source was found, or returns nil if it has no evidence.
    public static func sourceEvidence(_ source: String, evidence: Evidence, app: String?) -> String? {
        let sourceWords = WordTokenizer.words(source).map(TextFolding.key)
        guard !sourceWords.isEmpty else { return nil }
        if containsPhrase(sourceWords, in: evidence.text) {
            return "Found in the file: “\(source)”"
        }
        if let domain = evidence.downloadDomain,
           domainMatches(sourceWords, domain: domain) || DomainAliases.matches(source: source, domain: domain) {
            return "Downloaded from \(domain)"
        }
        if let app, !app.isEmpty {
            let appWords = WordTokenizer.words(app).map(TextFolding.key)
            if appWords == sourceWords || containsPhrase(sourceWords, in: app) {
                return "The app: \(app)"
            }
        }
        return nil
    }

    static func containsPhrase(_ phrase: [String], in text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let joinedPhrase = phrase.joined()
        if joinedPhrase.contains(where: GenericNameDetector.isDenseScript) {
            let foldedText = TextFolding.key(text).filter { !$0.isWhitespace }
            return foldedText.contains(phrase.joined())
        }
        let words = WordTokenizer.words(text).map(TextFolding.key)
        guard words.count >= phrase.count else { return false }
        for start in 0...(words.count - phrase.count) where Array(words[start..<(start + phrase.count)]) == phrase {
            return true
        }
        // A source written as one word in the text ("PayPal" vs "Pay Pal").
        return words.contains(phrase.joined())
    }

    static func domainMatches(_ phrase: [String], domain: String) -> Bool {
        let labels = domain.lowercased().split(separator: ".").map { TextFolding.key(String($0)) }
        let joined = phrase.joined()
        return labels.contains(joined) || labels.contains(phrase.joined(separator: "-"))
    }

    /// Confidence per 3.9. High only if every condition holds.
    public static func confidence(
        formatted: FormattedName,
        evidence: Evidence,
        guardrailOrRefusal: Bool,
        currentName: String
    ) -> (Confidence, [LowConfidenceReason]) {
        confidence(formatted: formatted, signals: ConfidenceSignals(evidence: evidence, guardrailOrRefusal: guardrailOrRefusal),
                   currentName: currentName)
    }

    /// Confidence from stored signals, for re-formatting queued proposals (H8).
    public static func confidence(
        formatted: FormattedName,
        signals: ConfidenceSignals,
        currentName: String
    ) -> (Confidence, [LowConfidenceReason]) {
        var reasons: [LowConfidenceReason] = []
        if !formatted.missingRequiredTokens.isEmpty { reasons.append(.missingRequiredToken) }
        if !signals.enoughContent { reasons.append(.littleContent) }
        if signals.guardrailOrRefusal { reasons.append(.guardrailOrRefusal) }
        if formatted.subjectWordsBefore > 0,
           Double(formatted.subjectWordsRemovedByGuards) / Double(formatted.subjectWordsBefore) >= 0.5 {
            reasons.append(.guardsRemovedMostOfSubject)
        }
        if formatted.fileName == currentName { reasons.append(.nameUnchanged) }
        if signals.metadataOnly { reasons.append(.metadataOnly) }
        return (reasons.isEmpty ? .high : .low, reasons)
    }
}
