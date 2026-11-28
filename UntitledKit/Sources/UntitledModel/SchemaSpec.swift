public import UntitledCore

/// The output schema, described independently of the framework so it can be tested on any
/// platform (3.8, F7). The Apple adapter turns it into a `DynamicGenerationSchema`.
public struct SchemaSpec: Sendable, Hashable {
    /// Allowed `kind` values: built-in English labels, then custom kind labels, then "Other".
    public var kinds: [String]
    /// Allowed `dateChoice` values: "none" and one entry per date candidate index.
    public var dateChoices: [String]
    public var sourceMaxWords: Int
    public var subjectMaxWords: Int
    public var customKinds: [CustomKind]

    public init(customKinds: [CustomKind], candidates: [DateCandidate], subjectMaxWords: Int) {
        var kinds = BuiltInKind.allCases.map(\.englishLabel)
        for custom in customKinds where !kinds.contains(custom.label) { kinds.append(custom.label) }
        kinds.append("Other")
        self.kinds = kinds
        self.dateChoices = ["none"] + candidates.map { String($0.index) }
        self.sourceMaxWords = Defaults.sourceMaxWords
        self.subjectMaxWords = subjectMaxWords
        self.customKinds = customKinds
    }

    public static let propertyNames = ["kind", "source", "subject", "dateChoice"]

    public var kindDescription: String { "The document type." }
    public var sourceDescription: String { "The company, organization, website or app the file comes from, at most \(sourceMaxWords) words. Leave empty if unknown." }
    public var subjectDescription: String { "What the file is about, at most \(subjectMaxWords) words, no dates." }
    public var dateDescription: String { "The index of the date that best dates the file, or none." }

    /// Turns raw schema values back into fields. Out-of-range values are treated as absent,
    /// so a malformed answer can never pick a date that was not offered.
    public func fields(kind: String, source: String?, subject: String, dateChoice: String) -> GeneratedFields {
        let kindRef = kinds.contains(kind) ? KindRef.fromSchemaValue(kind, customKinds: customKinds) : .other
        let index = dateChoices.contains(dateChoice) ? Int(dateChoice) : nil
        let trimmedSource = source?.trimmingWhitespace
        return GeneratedFields(kind: kindRef, source: trimmedSource?.isEmpty == false ? trimmedSource : nil,
                               subject: subject, dateChoice: index)
    }
}

extension String {
    var trimmingWhitespace: String {
        var slice = Substring(self)
        while let first = slice.first, first.isWhitespace { slice.removeFirst() }
        while let last = slice.last, last.isWhitespace { slice.removeLast() }
        return String(slice)
    }
}
