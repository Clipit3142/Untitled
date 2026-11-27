import Testing
import NomenTestSupport
@testable import NomenCore

/// H5: every date format renders exactly, with correct month names in every name language.
struct DateRenderTests {
    static let date = DateValue(year: 2026, month: 11, day: 27, hour: 9, minute: 5)!
    static let earlyDate = DateValue(year: 2026, month: 3, day: 4)!

    @Test(arguments: [
        (DateFormat.iso, "2026-11-27"),
        (.compact, "20261127"),
        (.yearMonth, "2026-11"),
        (.dotted, "27.11.2026"),
        (.dayMonthYearDash, "27-11-2026"),
        (.monthDayYearDash, "11-27-2026"),
        (.dayMonthNameYear, "27 Nov 2026"),
    ])
    func numericAndEnglishFormats(format: DateFormat, expected: String) {
        let words = DateRenderer.words(Self.date, format: format, time: .off, language: .english)
        #expect(words.joined(separator: " ") == expected)
    }

    @Test func padsSingleDigitDayAndMonthInNumericFormats() {
        #expect(DateRenderer.words(Self.earlyDate, format: .iso, time: .off, language: .english) == ["2026-03-04"])
        #expect(DateRenderer.words(Self.earlyDate, format: .dotted, time: .off, language: .english) == ["04.03.2026"])
        #expect(DateRenderer.words(Self.earlyDate, format: .monthDayYearDash, time: .off, language: .english) == ["03-04-2026"])
        #expect(DateRenderer.words(Self.earlyDate, format: .dayMonthNameYear, time: .off, language: .english) == ["4", "Mar", "2026"])
    }

    @Test(arguments: [
        (NameLanguage.english, ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]),
        (.german, ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]),
        (.french, ["janv", "févr", "mars", "avr", "mai", "juin", "juil", "août", "sept", "oct", "nov", "déc"]),
        (.italian, ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]),
        (.spanish, ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"]),
        (.portuguese, ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]),
        (.dutch, ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]),
    ])
    func monthNamesPerLanguage(language: NameLanguage, months: [String]) {
        for month in 1...12 {
            let value = DateValue(year: 2026, month: month, day: 15)!
            let words = DateRenderer.words(value, format: .dayMonthNameYear, time: .off, language: language)
            #expect(words == ["15", months[month - 1], "2026"], "\(language) month \(month)")
        }
    }

    @Test func cjkMonthNameFormat() {
        #expect(DateRenderer.words(Self.date, format: .dayMonthNameYear, time: .off, language: .japanese) == ["2026年11月27日"])
        #expect(DateRenderer.words(Self.date, format: .dayMonthNameYear, time: .off, language: .chineseSimplified) == ["2026年11月27日"])
        #expect(DateRenderer.words(Self.date, format: .dayMonthNameYear, time: .off, language: .korean) == ["2026년", "11월", "27일"])
    }

    @Test func numericFormatsAreTheSameInEveryLanguage() {
        for language in NameLanguage.allCases {
            for format in DateFormat.allCases where format != .dayMonthNameYear {
                #expect(DateRenderer.words(Self.date, format: format, time: .off, language: language)
                        == DateRenderer.words(Self.date, format: format, time: .off, language: .english))
            }
        }
    }

    @Test func timeFormats() {
        #expect(DateRenderer.words(Self.date, format: .iso, time: .dotted, language: .english) == ["2026-11-27", "09.05"])
        #expect(DateRenderer.words(Self.date, format: .iso, time: .compact, language: .english) == ["2026-11-27", "0905"])
        // No time on a date without one, and never with a format that has no day.
        #expect(DateRenderer.words(Self.earlyDate, format: .iso, time: .dotted, language: .english) == ["2026-03-04"])
        #expect(DateRenderer.words(Self.date, format: .yearMonth, time: .dotted, language: .english) == ["2026-11"])
    }

    @Test func monthNameDateFollowsCaseAndSeparators() {
        var style = Presets.kebab
        style.dateFormat = .dayMonthNameYear
        let fields = NameFields(kind: .builtIn(.invoice), subject: "power bill", date: Self.date)
        let name = NameFormatter.format(fields, style: style, context: FormatContext(language: .french, fileExtension: "pdf"))
        #expect(name.fileName == "27-nov-2026-facture-power-bill.pdf")

        var upper = Presets.clean
        upper.caseMode = .uppercase
        upper.dateFormat = .dayMonthNameYear
        let shouted = NameFormatter.format(fields, style: upper, context: FormatContext(language: .german, fileExtension: "pdf"))
        #expect(shouted.fileName == "27 NOV 2026 RECHNUNG POWER BILL.pdf")
    }

    @Test func timeJoinsWithHyphenWhenThereIsNoWordSeparator() {
        var style = Presets.compact
        style.caseMode = .camel
        style.wordSeparator = .none
        style.timeFormat = .compact
        let fields = NameFields(kind: .builtIn(.invoice), subject: "power bill", date: Self.date)
        let name = NameFormatter.format(fields, style: style, context: FormatContext(fileExtension: "pdf"))
        #expect(name.fileName == "20261127-0905_invoice_powerBill.pdf")
        #expect(!name.base.contains("202611270905"))
    }
}
