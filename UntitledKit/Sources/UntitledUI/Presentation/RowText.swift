public import Foundation

/// Times and VoiceOver phrases for rows (3.17): "Renamed Screenshot… to Safari Flight Booking, 2 minutes ago".
public enum RowText {
    /// "just now", "2 minutes ago", "3 hours ago", "yesterday", or a date.
    public static func relative(_ date: Date, now: Date, calendar: Calendar) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600:
            let minutes = Int(seconds / 60)
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        case ..<86_400 where calendar.isDate(date, inSameDayAs: now):
            let hours = Int(seconds / 3_600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        default:
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
                return "yesterday"
            }
            return dayFormatter(calendar: calendar, format: "d MMMM yyyy").string(from: date)
        }
    }

    /// The short time shown at the end of a row, in monospaced digits.
    public static func clock(_ date: Date, calendar: Calendar) -> String {
        dayFormatter(calendar: calendar, format: "HH:mm").string(from: date)
    }

    /// A recent or Activity row, read naturally.
    public static func renamedLabel(oldName: String, newName: String, time: Date, now: Date, calendar: Calendar, undone: Bool = false) -> String {
        let when = relative(time, now: now, calendar: calendar)
        return undone ? "Restored \(oldName), \(when)" : "Renamed \(oldName) to \(newName), \(when)"
    }

    /// A Review row.
    public static func reviewLabel(proposedName: String, currentName: String, lowConfidence: Bool, destination: String?) -> String {
        var parts = ["\(proposedName), proposed for \(currentName)"]
        if let destination { parts.append("moves to \(destination)") }
        if lowConfidence { parts.append("low confidence") }
        return parts.joined(separator: ", ")
    }

    /// "was Screenshot 2026-11-27 at 14.03.11.png" under a new name.
    public static func was(_ oldName: String) -> String { "was \(oldName)" }

    static func dayFormatter(calendar: Calendar, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = format
        return formatter
    }
}

/// Activity grouped by day (3.15).
public struct DayGroup<Element: Sendable>: Sendable, Identifiable {
    public var id: Date { day }
    public var day: Date
    public var title: String
    public var items: [Element]
}

public enum ActivityGrouping {
    /// Groups items (newest first) by local day, titled "Today", "Yesterday" or "Monday 23 November".
    public static func byDay<Element: Sendable>(_ items: [Element], time: (Element) -> Date, now: Date, calendar: Calendar) -> [DayGroup<Element>] {
        var groups: [DayGroup<Element>] = []
        for item in items.sorted(by: { time($0) > time($1) }) {
            let day = calendar.startOfDay(for: time(item))
            if groups.last?.day == day {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(DayGroup(day: day, title: title(for: day, now: now, calendar: calendar), items: [item]))
            }
        }
        return groups
    }

    public static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return RowText.dayFormatter(calendar: calendar, format: sameYear ? "EEEE d MMMM" : "EEEE d MMMM yyyy").string(from: day)
    }
}
