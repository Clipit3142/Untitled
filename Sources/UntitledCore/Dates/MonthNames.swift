/// Month names per language, for rendering ("27 Nov 2026") and for finding dates in text.
public enum MonthNames {
    /// Abbreviations used in names. Written without trailing dots, because a dot in a
    /// filename reads as a separator.
    public static func abbreviations(_ language: NameLanguage) -> [String] {
        switch language {
        case .english: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        case .german: ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
        case .french: ["janv", "févr", "mars", "avr", "mai", "juin", "juil", "août", "sept", "oct", "nov", "déc"]
        case .italian: ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]
        case .spanish: ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"]
        case .portuguese: ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
        case .dutch: ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
        case .japanese, .chineseSimplified: (1...12).map { "\($0)月" }
        case .korean: (1...12).map { "\($0)월" }
        }
    }

    /// Full month names, used only for parsing.
    public static func fullNames(_ language: NameLanguage) -> [String] {
        switch language {
        case .english: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        case .german: ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
        case .french: ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
        case .italian: ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
        case .spanish: ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
        case .portuguese: ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]
        case .dutch: ["januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december"]
        case .japanese, .chineseSimplified, .korean: abbreviations(language)
        }
    }

    /// Extra spellings accepted when parsing (common abbreviations with other lengths).
    static let extraParseForms: [(String, Int)] = [
        ("sept", 9), ("janv", 1), ("févr", 2), ("fevr", 2), ("avr", 4), ("juil", 7), ("déc", 12),
        ("dec", 12), ("mär", 3), ("maer", 3), ("marz", 3), ("märz", 3), ("okt", 10), ("dez", 12),
        ("gen", 1), ("mag", 5), ("giu", 6), ("lug", 7), ("ago", 8), ("set", 9), ("ott", 10),
        ("dic", 12), ("ene", 1), ("abr", 4), ("fev", 2), ("out", 10), ("mrt", 3), ("mei", 5),
        ("juin", 6), ("août", 8), ("aout", 8), ("febr", 2), ("sep", 9),
    ]

    /// Every parse form, folded (lowercase, no accents), mapped to a month number.
    static let parseTable: [String: Int] = {
        var table: [String: Int] = [:]
        for language in NameLanguage.allCases where !language.isCaseless {
            for (index, name) in fullNames(language).enumerated() { table[TextFolding.key(name)] = index + 1 }
            for (index, name) in abbreviations(language).enumerated() where table[TextFolding.key(name)] == nil {
                table[TextFolding.key(name)] = index + 1
            }
        }
        for (form, month) in extraParseForms where table[TextFolding.key(form)] == nil {
            table[TextFolding.key(form)] = month
        }
        return table
    }()

    /// The month for a word such as "Nov", "nov.", "Novembre" or "März", if any.
    public static func month(for word: String) -> Int? {
        var key = TextFolding.key(word)
        while key.hasSuffix(".") { key.removeLast() }
        return parseTable[key]
    }
}
