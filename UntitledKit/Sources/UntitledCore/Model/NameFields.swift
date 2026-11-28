/// The fields a name is built from (3.3). The model or Basic naming fills them; validation
/// guards them; the formatter turns them into a name.
public struct NameFields: Codable, Sendable, Hashable {
    public var kind: KindRef
    public var source: String?
    public var subject: String
    public var date: DateValue?
    public var dateSource: DateSource?
    public var app: String?
    /// The file's original name with generic parts removed.
    public var original: String?

    public init(
        kind: KindRef = .other,
        source: String? = nil,
        subject: String = "",
        date: DateValue? = nil,
        dateSource: DateSource? = nil,
        app: String? = nil,
        original: String? = nil
    ) {
        self.kind = kind
        self.source = source
        self.subject = subject
        self.date = date
        self.dateSource = dateSource
        self.app = app
        self.original = original
    }
}
