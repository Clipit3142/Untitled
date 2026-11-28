public import UntitledCore
import Foundation

/// Helpers for editing a proposal's fields in the Review inspector (M2).
public enum FieldEditing {
    public struct KindOption: Sendable, Hashable, Identifiable {
        public var id: String { label }
        public var label: String
        public var kind: KindRef
    }

    /// Every kind the user can pick, built-in first, then custom kinds, then Other.
    public static func kindOptions(customKinds: [CustomKind]) -> [KindOption] {
        BuiltInKind.allCases.map { KindOption(label: $0.englishLabel, kind: .builtIn($0)) }
            + customKinds.map { KindOption(label: $0.label, kind: .custom(id: $0.id)) }
            + [KindOption(label: "Other", kind: .other)]
    }

    /// "2026-11-27" or "2026-11-27 14:03".
    public static func dateText(_ date: DateValue?) -> String {
        guard let date else { return "" }
        var text = pad(date.year, 4) + "-" + pad(date.month, 2) + "-" + pad(date.day, 2)
        if let hour = date.hour, let minute = date.minute { text += " " + pad(hour, 2) + ":" + pad(minute, 2) }
        return text
    }

    /// Parses the inspector's date field; nil for anything that is not a real date. Empty clears it.
    public static func parseDate(_ text: String) -> DateValue?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard (1...2).contains(parts.count) else { return nil }
        let day = parts[0].split(separator: "-").map(String.init)
        guard day.count == 3, day[0].count == 4, day[1].count <= 2, day[2].count <= 2,
              let year = Int(day[0]), let month = Int(day[1]), let dayNumber = Int(day[2]) else { return nil }
        var hour: Int?
        var minute: Int?
        if parts.count == 2 {
            let time = parts[1].split(separator: ":").map(String.init)
            guard time.count == 2, time[1].count == 2, let h = Int(time[0]), let m = Int(time[1]) else { return nil }
            hour = h
            minute = m
        }
        guard let value = DateValue(year: year, month: month, day: dayNumber, hour: hour, minute: minute) else { return nil }
        return .some(value)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
