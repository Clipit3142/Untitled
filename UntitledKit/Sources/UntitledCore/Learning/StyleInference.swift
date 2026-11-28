import Foundation

/// What can be read from a set of well-named files (3.10 "Learning a style").
public struct InferredStyle: Sendable, Hashable {
    public enum DatePosition: String, Codable, Sendable, Hashable { case start, end, none }

    public var dateFormat: DateFormat?
    public var datePosition: DatePosition
    public var timeFormat: TimeFormat
    public var partSeparator: PartSeparator
    public var wordSeparator: WordSeparator
    public var caseMode: CaseMode
    /// Token order, including the date at its position.
    public var template: [TokenKind]
    public var maxLength: Int
    public var sampleCount: Int

    /// Applies the inferred settings to a style. Nothing changes until the user accepts it.
    public func applied(to style: NamingStyle) -> NamingStyle {
        var copy = style
        if let dateFormat { copy.dateFormat = dateFormat }
        copy.timeFormat = timeFormat
        copy.partSeparator = partSeparator
        copy.wordSeparator = caseMode.forcesNoWordSeparator ? .none : wordSeparator
        copy.caseMode = caseMode
        copy.maxLength = maxLength
        copy.template = template.map { kind in
            TemplateToken(kind, required: kind == .date || kind == .subject)
        }
        copy.version += 1
        return copy
    }
}

public enum StyleInferenceError: Error, Sendable, Hashable {
    case tooFewNames(minimum: Int, found: Int)
}

/// Infers a style by counting patterns (3.10). Used for learning from a folder (≥ 10
/// files) and from 3–5 typed example names.
public enum StyleInference {
    public static func inferFromFolder(_ names: [String]) throws(StyleInferenceError) -> InferredStyle {
        guard names.count >= Defaults.learnFromFolderMinimum else {
            throw .tooFewNames(minimum: Defaults.learnFromFolderMinimum, found: names.count)
        }
        return infer(names)
    }

    public static func inferFromExamples(_ names: [String]) throws(StyleInferenceError) -> InferredStyle {
        let cleaned = names.map(\.trimmed).filter { !$0.isEmpty }
        guard cleaned.count >= Defaults.exampleNamesRange.lowerBound else {
            throw .tooFewNames(minimum: Defaults.exampleNamesRange.lowerBound, found: cleaned.count)
        }
        return infer(Array(cleaned.prefix(Defaults.exampleNamesRange.upperBound)))
    }

    /// The analysis of one name.
    public struct NameAnalysis: Sendable, Hashable {
        public var dateFormat: DateFormat?
        public var dateAmbiguousDashOrder: Bool
        public var datePosition: InferredStyle.DatePosition
        public var timeFormat: TimeFormat
        public var partSeparator: PartSeparator?
        public var wordSeparator: WordSeparator?
        public var caseMode: CaseMode?
        public var tokens: [TokenKind]
        public var restWords: [String]
        public var kindWords: [String]
        public var length: Int
    }

    public static func infer(_ names: [String]) -> InferredStyle {
        let analyses = names.map { analyze($0) }
        let dateFormats = analyses.compactMap { $0.dateAmbiguousDashOrder ? nil : $0.dateFormat }
        var dateFormat = majority(dateFormats)
        if dateFormat == nil, analyses.contains(where: \.dateAmbiguousDashOrder) { dateFormat = .dayMonthYearDash }
        let datePosition = majority(analyses.map(\.datePosition)) ?? .none
        let timeFormat = majority(analyses.map(\.timeFormat)) ?? .off
        let partSeparator = majority(analyses.compactMap(\.partSeparator)) ?? .space
        var wordSeparator = majority(analyses.compactMap(\.wordSeparator)) ?? WordSeparator(rawValue: partSeparator.rawValue) ?? .space
        let caseMode = majority(analyses.compactMap(\.caseMode)) ?? .asGenerated
        if caseMode.forcesNoWordSeparator { wordSeparator = .none }
        let template = majority(analyses.map(\.tokens)) ?? [.date, .subject]

        let lengths = analyses.map(\.length).sorted()
        let index = max(0, Int((Double(lengths.count) * 0.9).rounded(.up)) - 1)
        let p90 = lengths.isEmpty ? Defaults.maxNameLength : lengths[min(index, lengths.count - 1)]
        let rounded = Int((Double(p90) / 10).rounded(.up)) * 10
        let maxLength = min(max(rounded, Defaults.maxNameLengthRange.lowerBound), Defaults.maxNameLengthRange.upperBound)

        return InferredStyle(
            dateFormat: dateFormat, datePosition: datePosition, timeFormat: timeFormat,
            partSeparator: partSeparator, wordSeparator: wordSeparator, caseMode: caseMode,
            template: template, maxLength: maxLength, sampleCount: names.count
        )
    }

    static func majority<T: Hashable>(_ values: [T]) -> T? {
        guard !values.isEmpty else { return nil }
        var counts: [T: Int] = [:]
        var firstSeen: [T: Int] = [:]
        for (index, value) in values.enumerated() {
            counts[value, default: 0] += 1
            if firstSeen[value] == nil { firstSeen[value] = index }
        }
        return counts.max { a, b in
            a.value == b.value ? firstSeen[a.key]! > firstSeen[b.key]! : a.value < b.value
        }?.key
    }

    // MARK: Single name

    public static func analyze(_ name: String) -> NameAnalysis {
        let base = FileExtension.split(name).base
        let length = base.count
        var rest = base
        var dateFormat: DateFormat?
        var ambiguous = false
        var position: InferredStyle.DatePosition = .none
        var time: TimeFormat = .off
        var partSeparator: PartSeparator?

        if let found = findDate(in: base) {
            dateFormat = found.format
            ambiguous = found.ambiguous
            position = found.position
            time = found.time
            rest = found.rest
            partSeparator = found.separator
        }

        // Separators inside the rest.
        let restSeparators = Set(rest.filter { Sanitizer.separatorCharacters.contains($0) })
        var wordSeparator: WordSeparator?
        if restSeparators.contains(" ") { wordSeparator = .space }
        else if restSeparators.contains("_") { wordSeparator = .underscore }
        else if restSeparators.contains("-") { wordSeparator = .hyphen }
        else if restSeparators.contains(".") { wordSeparator = .dot }

        // Segments are runs of words; when `explicit`, each segment is one token.
        var segments: [[String]]
        var explicit = false
        if let separator = [PartSeparator.spacedEnDash, .spacedHyphen].first(where: { rest.contains($0.rawValue) })
            ?? (partSeparator.map { [.spacedEnDash, .spacedHyphen].contains($0) } == true ? partSeparator : nil) {
            partSeparator = partSeparator ?? separator
            segments = rest.components(separatedBy: separator.rawValue).map(\.trimmed).filter { !$0.isEmpty }
                .map { $0.split(separator: " ").map(String.init) }
            explicit = true
            wordSeparator = .space
        } else {
            let separatorCharacter = wordSeparator.map(\.rawValue) ?? ""
            let items = separatorCharacter.isEmpty ? [rest] : rest.components(separatedBy: separatorCharacter).filter { !$0.isEmpty }
            if items.contains(where: hasCamelHump) {
                // camelCase or PascalCase: the visible separator separates tokens.
                if let ws = wordSeparator, partSeparator == nil { partSeparator = PartSeparator(rawValue: ws.rawValue) }
                wordSeparator = WordSeparator.none
                segments = items.map(splitCamel)
                explicit = true
            } else if wordSeparator == .space, let part = partSeparator, [.underscore, .hyphen, .dot].contains(part) {
                // Words separated by spaces, tokens by another character.
                segments = rest.components(separatedBy: part.rawValue).map { $0.split(separator: " ").map(String.init) }.filter { !$0.isEmpty }
                explicit = segments.count > 1
                if !explicit { segments = [segments.flatMap { $0 }] }
            } else {
                segments = [items.flatMap { $0.split(separator: " ").map(String.init) }]
            }
        }
        if partSeparator == nil, let wordSeparator, position == .none, wordSeparator != WordSeparator.none {
            partSeparator = PartSeparator(rawValue: wordSeparator.rawValue)
        }
        let allWords = segments.flatMap { $0 }

        // Tokens: find a kind label.
        var tokens: [TokenKind] = []
        var kindWords: [String] = []
        var caseSegments = segments
        if explicit, segments.count > 1 {
            var kindIndex: Int?
            for (index, words) in segments.enumerated() where kindIndex == nil && isKindLabel(words) {
                kindIndex = index
                kindWords = words
            }
            let nonKind = segments.indices.filter { $0 != kindIndex }
            let subjectIndex = nonKind.max { a, b in
                segments[a].count == segments[b].count ? a < b : segments[a].count < segments[b].count
            }
            for index in segments.indices {
                if index == kindIndex { tokens.append(.kind) }
                else if index == subjectIndex { tokens.append(.subject) }
                else { tokens.append(.source) }
            }
        } else if let range = kindRange(in: allWords) {
            kindWords = Array(allWords[range])
            caseSegments = []
            if range.lowerBound > 0 { tokens.append(.source); caseSegments.append(Array(allWords[..<range.lowerBound])) }
            tokens.append(.kind)
            caseSegments.append(kindWords)
            if range.upperBound < allWords.count { tokens.append(.subject); caseSegments.append(Array(allWords[range.upperBound...])) }
        } else if !allWords.isEmpty {
            tokens.append(.subject)
        }
        let caseMode = detectCase(caseSegments.filter { !$0.isEmpty }, joinedWithoutSeparator: wordSeparator == WordSeparator.none)
        switch position {
        case .start: tokens.insert(.date, at: 0)
        case .end: tokens.append(.date)
        case .none: break
        }

        return NameAnalysis(
            dateFormat: dateFormat, dateAmbiguousDashOrder: ambiguous, datePosition: position,
            timeFormat: time, partSeparator: partSeparator, wordSeparator: wordSeparator,
            caseMode: caseMode, tokens: tokens, restWords: allWords, kindWords: kindWords, length: length
        )
    }

    // MARK: Dates

    struct FoundDate {
        var format: DateFormat
        var ambiguous: Bool
        var position: InferredStyle.DatePosition
        var time: TimeFormat
        var rest: String
        var separator: PartSeparator?
    }

    static func findDate(in base: String) -> FoundDate? {
        let characters = Array(base)
        for (format, length) in datePatterns {
            // At the start.
            if characters.count >= length, let (readFormat, match) = matchDate(Array(characters[0..<length]), format: format) {
                var restStart = length
                var time: TimeFormat = .off
                if let t = matchTime(characters, from: restStart) { time = t.format; restStart = t.end }
                let (separator, after) = readSeparator(characters, from: restStart)
                return FoundDate(format: readFormat, ambiguous: match, position: .start, time: time,
                                 rest: String(characters[after...]), separator: separator)
            }
        }
        for (format, length) in datePatterns {
            // At the end, possibly followed by a time.
            for timeLength in [0, 6, 5] {
                let end = characters.count
                let start = end - length - timeLength
                guard start >= 0 else { continue }
                guard let (readFormat, match) = matchDate(Array(characters[start..<(start + length)]), format: format) else { continue }
                var time: TimeFormat = .off
                if timeLength > 0 {
                    guard let t = matchTime(characters, from: start + length), t.end == end else { continue }
                    time = t.format
                }
                let (separator, before) = readSeparatorBackwards(characters, before: start)
                return FoundDate(format: readFormat, ambiguous: match, position: .end, time: time,
                                 rest: String(characters[0..<before]), separator: separator)
            }
        }
        // Month-name dates: "27 Nov 2026" at the start or end.
        let words = base.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if words.count >= 3, Int(words[0]) != nil, MonthNames.month(for: words[1]) != nil, words[2].count == 4, Int(words[2]) != nil {
            let restText = words.dropFirst(3).joined(separator: " ")
            let (separator, after) = readSeparator(Array(" " + restText), from: 0)
            return FoundDate(format: .dayMonthNameYear, ambiguous: false, position: .start, time: .off,
                             rest: String(Array(" " + restText)[after...]), separator: separator)
        }
        if words.count >= 3, let last = words.last, last.count == 4, Int(last) != nil,
           MonthNames.month(for: words[words.count - 2]) != nil, Int(words[words.count - 3]) != nil {
            let restText = words.dropLast(3).joined(separator: " ")
            let chars = Array(restText + " ")
            let (separator, before) = readSeparatorBackwards(chars, before: chars.count)
            return FoundDate(format: .dayMonthNameYear, ambiguous: false, position: .end, time: .off,
                             rest: String(chars[0..<before]), separator: separator)
        }
        return nil
    }

    static let datePatterns: [(DateFormat, Int)] = [
        (.iso, 10), (.dotted, 10), (.dayMonthYearDash, 10), (.compact, 8), (.yearMonth, 7),
    ]

    /// Returns the format read and whether a dashed date's day/month order is ambiguous,
    /// or nil if the characters are not that format.
    static func matchDate(_ c: [Character], format: DateFormat) -> (DateFormat, Bool)? {
        func digits(_ range: Range<Int>) -> Int? {
            guard range.upperBound <= c.count, c[range].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(String(c[range]))
        }
        switch format {
        case .iso:
            guard c.count == 10, c[4] == "-", c[7] == "-", let y = digits(0..<4), let m = digits(5..<7), let d = digits(8..<10),
                  DateValue(year: y, month: m, day: d) != nil else { return nil }
            return (.iso, false)
        case .compact:
            guard c.count == 8, let y = digits(0..<4), let m = digits(4..<6), let d = digits(6..<8),
                  DateValue(year: y, month: m, day: d) != nil else { return nil }
            return (.compact, false)
        case .yearMonth:
            guard c.count == 7, c[4] == "-", let y = digits(0..<4), let m = digits(5..<7), (1...12).contains(m),
                  (1900...2199).contains(y) else { return nil }
            return (.yearMonth, false)
        case .dotted:
            guard c.count == 10, c[2] == ".", c[5] == ".", let d = digits(0..<2), let m = digits(3..<5), let y = digits(6..<10),
                  DateValue(year: y, month: m, day: d) != nil else { return nil }
            return (.dotted, false)
        case .dayMonthYearDash, .monthDayYearDash:
            guard c.count == 10, c[2] == "-", c[5] == "-", let a = digits(0..<2), let b = digits(3..<5), let y = digits(6..<10) else { return nil }
            let dayFirst = DateValue(year: y, month: b, day: a) != nil
            let monthFirst = DateValue(year: y, month: a, day: b) != nil
            switch (dayFirst, monthFirst) {
            case (true, false): return (.dayMonthYearDash, false)
            case (false, true): return (.monthDayYearDash, false)
            case (true, true): return (.dayMonthYearDash, a != b)
            case (false, false): return nil
            }
        case .dayMonthNameYear:
            return nil
        }
    }

    static func matchTime(_ c: [Character], from start: Int) -> (format: TimeFormat, end: Int)? {
        guard start < c.count, let sep = Optional(c[start]), Sanitizer.separatorCharacters.contains(sep) else { return nil }
        let s = start + 1
        func digit(_ i: Int) -> Bool { i < c.count && c[i].isASCII && c[i].isNumber }
        if digit(s), digit(s + 1), s + 2 < c.count, c[s + 2] == ".", digit(s + 3), digit(s + 4), !digit(s + 5) {
            return (.dotted, s + 5)
        }
        if digit(s), digit(s + 1), digit(s + 2), digit(s + 3), !digit(s + 4) {
            if let h = Int(String(c[s..<(s + 2)])), let m = Int(String(c[(s + 2)..<(s + 4)])), h < 24, m < 60 {
                return (.compact, s + 4)
            }
        }
        return nil
    }

    static func readSeparator(_ c: [Character], from start: Int) -> (PartSeparator?, Int) {
        for separator in [PartSeparator.spacedEnDash, .spacedHyphen, .space, .underscore, .hyphen, .dot] {
            let sep = Array(separator.rawValue)
            if start + sep.count <= c.count, Array(c[start..<(start + sep.count)]) == sep {
                return (separator, start + sep.count)
            }
        }
        return (nil, start)
    }

    static func readSeparatorBackwards(_ c: [Character], before end: Int) -> (PartSeparator?, Int) {
        for separator in [PartSeparator.spacedEnDash, .spacedHyphen, .space, .underscore, .hyphen, .dot] {
            let sep = Array(separator.rawValue)
            if end - sep.count >= 0, Array(c[(end - sep.count)..<end]) == sep {
                return (separator, end - sep.count)
            }
        }
        return (nil, end)
    }

    // MARK: Case and words

    static func splitCamel(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in text {
            if character.isUppercase, !current.isEmpty, current.last?.isUppercase == false {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// True when a lowercase letter is directly followed by an uppercase letter, as in
    /// "mobileSubscription". A separator between the letters ("Ticket_Electricity") is not a hump.
    static func hasCamelHump(_ word: String) -> Bool {
        var previousWasLower = false
        for character in word {
            if character.isLowercase {
                previousWasLower = true
            } else if character.isUppercase {
                if previousWasLower { return true }
                previousWasLower = false
            } else {
                previousWasLower = false
            }
        }
        return false
    }

    /// Detects the case mode from token segments. Sentence case is judged per token,
    /// because each token is sentence-cased on its own.
    static func detectCase(_ segments: [[String]], joinedWithoutSeparator: Bool) -> CaseMode? {
        let words = segments.flatMap { $0 }
        let cased = words.filter { $0.contains(where: { $0.isUppercase || $0.isLowercase }) }
        guard !cased.isEmpty else { return nil }
        if joinedWithoutSeparator {
            guard let first = segments.first(where: { $0.count > 1 })?.first?.first(where: \.isLetter)
                    ?? cased.first?.first(where: \.isLetter) else { return nil }
            return first.isLowercase ? .camel : .pascal
        }
        if cased.allSatisfy({ !$0.contains(where: \.isUppercase) }) { return .lowercase }
        if cased.allSatisfy({ !$0.contains(where: \.isLowercase) }), cased.contains(where: { $0.count > 4 }) { return .uppercase }
        func capitalized(_ word: String) -> Bool { word.first(where: \.isLetter)?.isUppercase ?? true }
        let small = Set(NameLanguage.allCases.flatMap { WordLists.titleSmallWords($0) })
        let multiWord = segments.contains { $0.count > 1 }
        let isTitle = segments.allSatisfy { segment in
            segment.enumerated().allSatisfy { index, word in
                capitalized(word) || (index > 0 && index < segment.count - 1 && small.contains(word.lowercased()))
            }
        }
        let isSentence = segments.allSatisfy { segment in
            guard let first = segment.first, capitalized(first) else { return false }
            return segment.dropFirst().allSatisfy { !$0.contains(where: \.isUppercase) || isAcronymLike($0) }
        }
        if isTitle, isSentence { return multiWord ? (segments.contains { $0.dropFirst().contains(where: capitalized) } ? .title : .sentence) : nil }
        if isTitle { return .title }
        if isSentence { return .sentence }
        return .asGenerated
    }

    static func isAcronymLike(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        return (2...4).contains(letters.count) && letters.allSatisfy(\.isUppercase)
    }

    static func isKindLabel(_ words: [String]) -> Bool {
        let key = words.map(TextFolding.key).joined(separator: " ")
        return kindLabelKeys.contains(key)
    }

    static func kindRange(in words: [String]) -> Range<Int>? {
        let keys = words.map(TextFolding.key)
        for length in [3, 2, 1] where words.count >= length {
            for start in 0...(words.count - length) {
                let candidate = keys[start..<(start + length)].joined(separator: " ")
                if kindLabelKeys.contains(candidate) { return start..<(start + length) }
            }
        }
        return nil
    }

    static let kindLabelKeys: Set<String> = {
        var keys: Set<String> = []
        for kind in BuiltInKind.allCases {
            for language in NameLanguage.allCases {
                let words = WordTokenizer.words(kind.label(in: language))
                keys.insert(words.map(TextFolding.key).joined(separator: " "))
            }
        }
        return keys
    }()
}
