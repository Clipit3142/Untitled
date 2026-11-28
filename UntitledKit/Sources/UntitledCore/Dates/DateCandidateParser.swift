import Foundation

/// A date found in a file's text, with the exact snippet it came from (3.7).
public struct DateCandidate: Codable, Sendable, Hashable {
    public var index: Int
    public var value: DateValue
    public var snippet: String

    public init(index: Int, value: DateValue, snippet: String) {
        self.index = index
        self.value = value
        self.snippet = snippet
    }
}

/// Finds date candidates in text with numeric and month-name patterns.
///
/// - Year-first dates (2026-11-27, 2026/11/27, 20261127) are unambiguous.
/// - Day/month dates (03.04.2026, 27/11/26) are read day-first or month-first only when
///   the reading is certain: a component above 12, both components equal, a day-first
///   language, or another numeric date on the page whose order is certain. Anything
///   else is dropped, never guessed (E6).
/// - Month names in English, German, French, Italian, Spanish, Portuguese and Dutch
///   ("27 November 2026", "Nov 27, 2026", "27. März 2026", "27 de noviembre de 2026",
///   "1er décembre 2026") and CJK forms ("2026年11月27日", "2026년 11월 27일").
public enum DateCandidateParser {
    public static let maxCandidates = 20

    public static func candidates(in text: String, language: NameLanguage?) -> [DateCandidate] {
        var found: [(value: DateValue, snippet: String, numeric: NumericReading?)] = []
        for line in text.split(whereSeparator: \.isNewline) {
            found += scan(String(line))
        }
        // Settle day/month order.
        let dayFirstEvidence = found.contains { $0.numeric?.order == .dayFirst }
        let monthFirstEvidence = found.contains { $0.numeric?.order == .monthFirst }
        let settled: NumericOrder? = {
            if language?.settlesDayFirst == true, !monthFirstEvidence { return .dayFirst }
            if dayFirstEvidence, !monthFirstEvidence { return .dayFirst }
            if monthFirstEvidence, !dayFirstEvidence { return .monthFirst }
            return nil
        }()
        var results: [DateCandidate] = []
        var seen: Set<String> = []
        for item in found {
            var value = item.value
            if let numeric = item.numeric, numeric.order == .ambiguous {
                guard let settled else { continue }
                guard let resolved = numeric.resolve(settled) else { continue }
                value = resolved
            }
            let key = "\(value.year)-\(value.month)-\(value.day)|\(item.snippet)"
            guard seen.insert(key).inserted else { continue }
            results.append(DateCandidate(index: results.count, value: value, snippet: String(item.snippet.prefix(60))))
            if results.count == maxCandidates { break }
        }
        return results
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(String)
        case word(String)
        case symbol(Character)
        case space
    }

    struct Positioned {
        var token: Token
        var range: Range<String.Index>
    }

    static func tokenize(_ line: String) -> [Positioned] {
        var tokens: [Positioned] = []
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            let start = index
            if character.isASCII, character.isNumber {
                while index < line.endIndex, line[index].isASCII, line[index].isNumber { index = line.index(after: index) }
                tokens.append(Positioned(token: .number(String(line[start..<index])), range: start..<index))
            } else if character.isLetter {
                if GenericNameDetector.isDenseScript(character) || "年月日년월일".contains(character) {
                    index = line.index(after: index)
                    tokens.append(Positioned(token: .word(String(character)), range: start..<index))
                } else {
                    while index < line.endIndex, line[index].isLetter, !"年月日년월일".contains(line[index]),
                          !GenericNameDetector.isDenseScript(line[index]) {
                        index = line.index(after: index)
                    }
                    tokens.append(Positioned(token: .word(String(line[start..<index])), range: start..<index))
                }
            } else if character.isWhitespace {
                while index < line.endIndex, line[index].isWhitespace { index = line.index(after: index) }
                tokens.append(Positioned(token: .space, range: start..<index))
            } else {
                index = line.index(after: index)
                tokens.append(Positioned(token: .symbol(character), range: start..<index))
            }
        }
        return tokens
    }

    // MARK: Patterns

    enum NumericOrder { case dayFirst, monthFirst, equal, ambiguous }

    struct NumericReading {
        var first: Int
        var second: Int
        var year: Int
        var order: NumericOrder

        func resolve(_ order: NumericOrder) -> DateValue? {
            switch order {
            case .dayFirst: DateValue(year: year, month: second, day: first)
            case .monthFirst, .equal: DateValue(year: year, month: first, day: second)
            case .ambiguous: nil
            }
        }
    }

    static func scan(_ line: String) -> [(DateValue, String, NumericReading?)] {
        let tokens = tokenize(line)
        var results: [(DateValue, String, NumericReading?)] = []
        var i = 0
        while i < tokens.count {
            if let match = matchAt(tokens, i, line: line) {
                results.append((match.value, String(line[match.range]), match.numeric))
                i = match.next
            } else {
                i += 1
            }
        }
        return results
    }

    struct Match {
        var value: DateValue
        var range: Range<String.Index>
        var next: Int
        var numeric: NumericReading?
    }

    static func number(_ tokens: [Positioned], _ i: Int) -> String? {
        guard i < tokens.count, case .number(let n) = tokens[i].token else { return nil }
        return n
    }

    static func symbol(_ tokens: [Positioned], _ i: Int) -> Character? {
        guard i < tokens.count, case .symbol(let c) = tokens[i].token else { return nil }
        return c
    }

    static func word(_ tokens: [Positioned], _ i: Int) -> String? {
        guard i < tokens.count, case .word(let w) = tokens[i].token else { return nil }
        return w
    }

    static func skipSpace(_ tokens: [Positioned], _ i: Int) -> Int {
        var j = i
        while j < tokens.count, tokens[j].token == .space { j += 1 }
        return j
    }

    /// True if the token before `i` is a digit or a dot/slash/hyphen glued to a digit,
    /// which means the candidate is part of a longer number such as a version.
    static func gluedBefore(_ tokens: [Positioned], _ i: Int) -> Bool {
        guard i > 0 else { return false }
        if case .number = tokens[i - 1].token { return true }
        if let c = symbol(tokens, i - 1), ".-/".contains(c), i >= 2, number(tokens, i - 2) != nil { return true }
        return false
    }

    static func gluedAfter(_ tokens: [Positioned], _ i: Int) -> Bool {
        guard i < tokens.count else { return false }
        if case .number = tokens[i].token { return true }
        if let c = symbol(tokens, i), ".-/".contains(c), number(tokens, i + 1) != nil { return true }
        return false
    }

    static func matchAt(_ t: [Positioned], _ i: Int, line: String) -> Match? {
        if let n = number(t, i) {
            if gluedBefore(t, i) { return nil }
            // CJK: 2026年11月27日 / 2026년 11월 27일
            if n.count == 4, let year = Int(n) {
                var j = skipSpace(t, i + 1)
                if let w = word(t, j), w == "年" || w == "년" {
                    j = skipSpace(t, j + 1)
                    if let m = number(t, j), let month = Int(m) {
                        j = skipSpace(t, j + 1)
                        if let w2 = word(t, j), w2 == "月" || w2 == "월" {
                            j = skipSpace(t, j + 1)
                            if let d = number(t, j), let day = Int(d) {
                                j += 1
                                var end = t[j - 1].range.upperBound
                                let k = skipSpace(t, j)
                                if let w3 = word(t, k), w3 == "日" || w3 == "일" { j = k + 1; end = t[k].range.upperBound }
                                if let value = DateValue(year: year, month: month, day: day) {
                                    return Match(value: value, range: t[i].range.lowerBound..<end, next: j)
                                }
                            }
                        }
                    }
                }
            }
            // Year first: 2026-11-27, 2026/11/27, 2026.11.27
            if n.count == 4, let year = Int(n), let s1 = symbol(t, i + 1), "-/.".contains(s1),
               let m = number(t, i + 2), m.count <= 2, let s2 = symbol(t, i + 3), s2 == s1,
               let d = number(t, i + 4), d.count <= 2, !gluedAfter(t, i + 5),
               let value = DateValue(year: year, month: Int(m) ?? 0, day: Int(d) ?? 0) {
                return Match(value: value, range: t[i].range.lowerBound..<t[i + 4].range.upperBound, next: i + 5)
            }
            // Compact: 20261127
            if n.count == 8, n.hasPrefix("19") || n.hasPrefix("20"), !gluedAfter(t, i + 1),
               let year = Int(n.prefix(4)), let month = Int(n.dropFirst(4).prefix(2)), let day = Int(n.suffix(2)),
               let value = DateValue(year: year, month: month, day: day) {
                return Match(value: value, range: t[i].range, next: i + 1)
            }
            // Day/month numeric: 27.11.2026, 03/04/2026, 27-11-26
            if n.count <= 2, let a = Int(n), let s1 = symbol(t, i + 1), "-/.".contains(s1),
               let m = number(t, i + 2), m.count <= 2, let b = Int(m), let s2 = symbol(t, i + 3), s2 == s1,
               let y = number(t, i + 4), y.count == 4 || y.count == 2, !gluedAfter(t, i + 5),
               let yearRaw = Int(y) {
                let year = y.count == 2 ? (yearRaw < 70 ? 2000 + yearRaw : 1900 + yearRaw) : yearRaw
                let order: NumericOrder
                if a == b { order = .equal }
                else if a > 12, b <= 12 { order = .dayFirst }
                else if b > 12, a <= 12 { order = .monthFirst }
                else if a <= 12, b <= 12 { order = .ambiguous }
                else { return nil }
                let reading = NumericReading(first: a, second: b, year: year, order: order)
                let provisional = reading.resolve(order == .ambiguous ? .dayFirst : order)
                    ?? reading.resolve(.monthFirst)
                guard let value = provisional else { return nil }
                if order != .ambiguous, reading.resolve(order) == nil { return nil }
                return Match(value: value, range: t[i].range.lowerBound..<t[i + 4].range.upperBound, next: i + 5, numeric: reading)
            }
            // Day month-name year: 27 Nov 2026, 27. November 2026, 1er décembre 2026, 27 de noviembre de 2026
            if n.count <= 2, let day = Int(n) {
                var j = i + 1
                if let w = word(t, j), ["st", "nd", "rd", "th", "er", "e", "o", "a"].contains(w.lowercased()) { j += 1 }
                if let c = symbol(t, j), c == "." || c == "º" || c == "ª" { j += 1 }
                j = skipSpace(t, j)
                if let w = word(t, j), w.lowercased() == "de" { j = skipSpace(t, j + 1) }
                if let w = word(t, j), let month = MonthNames.month(for: w) {
                    j += 1
                    if let c = symbol(t, j), c == "." { j += 1 }
                    if let c = symbol(t, j), c == "," { j += 1 }
                    j = skipSpace(t, j)
                    if let w2 = word(t, j), w2.lowercased() == "de" { j = skipSpace(t, j + 1) }
                    if let y = number(t, j), y.count == 4, let year = Int(y), !gluedAfter(t, j + 1),
                       let value = DateValue(year: year, month: month, day: day) {
                        return Match(value: value, range: t[i].range.lowerBound..<t[j].range.upperBound, next: j + 1)
                    }
                }
            }
            return nil
        }
        // Month-name day year: Nov 27, 2026 / November 27th 2026
        if let w = word(t, i), let month = MonthNames.month(for: w) {
            if i > 0, case .word = t[i - 1].token { return nil }
            var j = i + 1
            if let c = symbol(t, j), c == "." { j += 1 }
            j = skipSpace(t, j)
            guard let d = number(t, j), d.count <= 2, let day = Int(d) else { return nil }
            j += 1
            if let suffix = word(t, j), ["st", "nd", "rd", "th"].contains(suffix.lowercased()) { j += 1 }
            if let c = symbol(t, j), c == "," { j += 1 }
            j = skipSpace(t, j)
            guard let y = number(t, j), y.count == 4, let year = Int(y), !gluedAfter(t, j + 1),
                  let value = DateValue(year: year, month: month, day: day) else { return nil }
            return Match(value: value, range: t[i].range.lowerBound..<t[j].range.upperBound, next: j + 1)
        }
        return nil
    }
}
