/// Renders a date token as words (3.10 step 3). A format with spaces ("27 Nov 2026") yields
/// several words, so the word separator and case apply to it. A time is its own word.
public enum DateRenderer {
    public static func words(_ date: DateValue, format: DateFormat, time: TimeFormat, language: NameLanguage) -> [String] {
        var words = dateWords(date, format: format, language: language)
        if time != .off, format.hasDay, let hour = date.hour, let minute = date.minute {
            let separator = time == .dotted ? "." : ""
            words.append(pad(hour) + separator + pad(minute))
        }
        return words
    }

    static func dateWords(_ date: DateValue, format: DateFormat, language: NameLanguage) -> [String] {
        let y = String(date.year)
        let m = pad(date.month)
        let d = pad(date.day)
        switch format {
        case .iso: return ["\(y)-\(m)-\(d)"]
        case .compact: return ["\(y)\(m)\(d)"]
        case .yearMonth: return ["\(y)-\(m)"]
        case .dotted: return ["\(d).\(m).\(y)"]
        case .dayMonthYearDash: return ["\(d)-\(m)-\(y)"]
        case .monthDayYearDash: return ["\(m)-\(d)-\(y)"]
        case .dayMonthNameYear:
            switch language {
            case .japanese, .chineseSimplified:
                return ["\(y)年\(date.month)月\(date.day)日"]
            case .korean:
                return ["\(y)년", "\(date.month)월", "\(date.day)일"]
            default:
                let month = MonthNames.abbreviations(language)[date.month - 1]
                return [String(date.day), month, y]
            }
        }
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }
}
