public import Foundation

/// A calendar date, optionally with a time, as it appears in a name.
/// Kept as components, not as `Date`, so formatting never depends on time zones.
public struct DateValue: Codable, Sendable, Hashable, Comparable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int?
    public var minute: Int?

    public init?(year: Int, month: Int, day: Int, hour: Int? = nil, minute: Int? = nil) {
        guard (1900...2199).contains(year), (1...12).contains(month),
              (1...DateValue.daysIn(month: month, year: year)).contains(day) else { return nil }
        if let hour, !(0...23).contains(hour) { return nil }
        if let minute, !(0...59).contains(minute) { return nil }
        if (hour == nil) != (minute == nil) { return nil }
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
    }

    /// Builds a date value from an absolute time in a given calendar and time zone.
    public init(date: Date, timeZone: TimeZone, includeTime: Bool = true) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        self.year = parts.year ?? 1970
        self.month = parts.month ?? 1
        self.day = parts.day ?? 1
        self.hour = includeTime ? parts.hour : nil
        self.minute = includeTime ? parts.minute : nil
    }

    public var hasTime: Bool { hour != nil && minute != nil }

    /// The same day without a time.
    public var dayOnly: DateValue {
        var copy = self
        copy.hour = nil
        copy.minute = nil
        return copy
    }

    public static func < (lhs: DateValue, rhs: DateValue) -> Bool {
        (lhs.year, lhs.month, lhs.day, lhs.hour ?? -1, lhs.minute ?? -1)
            < (rhs.year, rhs.month, rhs.day, rhs.hour ?? -1, rhs.minute ?? -1)
    }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        default: return 0
        }
    }
}

/// Where a date in a name came from (3.9: content candidate or a file date).
public enum DateSource: String, Codable, Sendable, Hashable, CaseIterable {
    case content
    case capture
    case added
    case created
}
