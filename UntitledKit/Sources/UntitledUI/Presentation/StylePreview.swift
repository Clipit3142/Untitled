public import UntitledCore
public import UntitledEngine

/// The live preview in Styles (3.15): stored fields only, so editing never calls the model.
public enum StylePreview {
    public struct Row: Sendable, Hashable, Identifiable {
        public var id: Int
        public var fileName: String
        public var isScreenshot: Bool
    }

    /// Built-in samples, used alongside the fields of queued proposals.
    public static let samples: [StylePreviewSample] = [
        StylePreviewSample(fields: NameFields(kind: .builtIn(.invoice), source: "Swisscom", subject: "Mobile subscription November",
                                              date: DateValue(year: 2026, month: 11, day: 27), dateSource: .content),
                           fileExtension: "pdf", isScreenshot: false),
        StylePreviewSample(fields: NameFields(kind: .builtIn(.bookingConfirmation), source: "Swiss", subject: "Flight Zurich to Lisbon",
                                              date: DateValue(year: 2026, month: 12, day: 4), dateSource: .content),
                           fileExtension: "pdf", isScreenshot: false),
        StylePreviewSample(fields: NameFields(kind: .builtIn(.webPage), subject: "Flight booking",
                                              date: DateValue(year: 2026, month: 11, day: 27, hour: 14, minute: 3),
                                              dateSource: .capture, app: "Safari"),
                           fileExtension: "png", isScreenshot: true),
        StylePreviewSample(fields: NameFields(kind: .builtIn(.receipt), source: "Migros", subject: "Groceries",
                                              date: DateValue(year: 2026, month: 11, day: 21), dateSource: .content),
                           fileExtension: "jpeg", isScreenshot: false),
    ]

    public static func rows(style: NamingStyle, samples: [StylePreviewSample] = samples, customKinds: [CustomKind] = []) -> [Row] {
        samples.enumerated().map { index, sample in
            let context = FormatContext(language: style.nameLanguage ?? sample.language, customKinds: customKinds,
                                        fileExtension: sample.fileExtension, isScreenshot: sample.isScreenshot)
            return Row(id: index, fileName: NameFormatter.format(sample.fields, style: style, context: context).fileName,
                       isScreenshot: sample.isScreenshot)
        }
    }
}
