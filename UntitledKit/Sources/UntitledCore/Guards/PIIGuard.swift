import Foundation

/// Removes personal data from generated text before it can reach a name (3.9).
///
/// Applies to every generated field and to the file's original name. It never runs on
/// names the user types. Detection works on a normalized copy of the text:
/// compatibility-normalized (full-width digits become ASCII), every decimal digit mapped
/// to 0–9, invisible format characters removed and every space or dash variant unified.
///
/// Removed:
/// - email addresses: any whitespace-delimited chunk containing "@"
/// - IBANs whose mod-97 checksum is valid, with or without spacing
/// - number spans (digit groups joined by 1–3 non-letter characters) that contain a
///   Luhn-valid 13–19 digit card number, start with an international prefix, have
///   8 or more digits in two or more groups (phone formatting), or contain a run of
///   9 or more consecutive digits
public enum PIIGuard {
    public struct Result: Sendable, Equatable {
        public var text: String
        public var removedSpans: Int
    }

    /// Redacts personal data and returns the normalized, redacted text.
    public static func redact(_ text: String) -> Result {
        var scalars = normalize(text)
        var removed = 0
        removed += removeEmails(&scalars)
        removed += removeIBANs(&scalars)
        removed += removeNumberSpans(&scalars)
        return Result(text: String(String.UnicodeScalarView(scalars)), removedSpans: removed)
    }

    /// True if the text still contains something the guard would remove.
    public static func containsPII(_ text: String) -> Bool {
        redact(text).removedSpans > 0
    }

    // MARK: Normalization

    static func normalize(_ text: String) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.nfkc.unicodeScalars {
            if scalar.isASCII {
                out.append(scalar.value < 32 || scalar.value == 127 ? " " : scalar)
                continue
            }
            let p = scalar.properties
            if p.numericType == .decimal, let value = p.numericValue, value >= 0, value <= 9, !scalar.isASCII {
                out.append(Unicode.Scalar(UInt8(48 + Int(value))))
                continue
            }
            switch p.generalCategory {
            case .format:
                continue // zero-width spaces, joiners, bidi controls, soft hyphens
            case .spaceSeparator, .lineSeparator, .paragraphSeparator:
                out.append(" ")
                continue
            case .dashPunctuation:
                out.append("-")
                continue
            case .control:
                out.append(" ")
                continue
            default:
                break
            }
            if p.isDefaultIgnorableCodePoint { continue }
            if scalar.value == 0x2212 { out.append("-"); continue } // minus sign
            out.append(scalar)
        }
        return out
    }

    private static func isDigit(_ s: Unicode.Scalar) -> Bool { s.value >= 48 && s.value <= 57 }
    private static func isLetter(_ s: Unicode.Scalar) -> Bool {
        if s.isASCII { return (s.value >= 65 && s.value <= 90) || (s.value >= 97 && s.value <= 122) }
        return s.properties.isAlphabetic
    }
    private static func isSpace(_ s: Unicode.Scalar) -> Bool { s == " " }

    // MARK: Emails

    private static func removeEmails(_ s: inout [Unicode.Scalar]) -> Int {
        var count = 0
        var index = 0
        while index < s.count {
            if s[index] == "@" || s[index] == "\u{FF20}" {
                var start = index
                while start > 0, !isSpace(s[start - 1]) { start -= 1 }
                var end = index + 1
                while end < s.count, !isSpace(s[end]) { end += 1 }
                s.replaceSubrange(start..<end, with: [" "])
                count += 1
                index = start + 1
            } else {
                index += 1
            }
        }
        return count
    }

    // MARK: IBAN

    private static func removeIBANs(_ s: inout [Unicode.Scalar]) -> Int {
        var count = 0
        var index = 0
        while index + 3 < s.count {
            let atWordStart = index == 0 || !(isLetter(s[index - 1]) || isDigit(s[index - 1]))
            if atWordStart, isASCIILetter(s[index]), isASCIILetter(s[index + 1]),
               isDigit(s[index + 2]), isDigit(s[index + 3]),
               let end = validIBANEnd(s, start: index) {
                s.replaceSubrange(index..<end, with: [" "])
                count += 1
                index += 1
            } else {
                index += 1
            }
        }
        return count
    }

    private static func isASCIILetter(_ s: Unicode.Scalar) -> Bool {
        (s.value >= 65 && s.value <= 90) || (s.value >= 97 && s.value <= 122)
    }

    /// Returns the end index of the longest valid IBAN starting at `start`, if any.
    private static func validIBANEnd(_ s: [Unicode.Scalar], start: Int) -> Int? {
        var characters: [Unicode.Scalar] = []
        var endIndices: [Int] = []
        var index = start
        while index < s.count, characters.count < 34 {
            let c = s[index]
            if isASCIILetter(c) || isDigit(c) {
                characters.append(c)
                endIndices.append(index + 1)
                index += 1
            } else if (c == " " || c == "-" || c == "."), index + 1 < s.count,
                      isASCIILetter(s[index + 1]) || isDigit(s[index + 1]) {
                index += 1
            } else {
                break
            }
        }
        guard characters.count >= 15 else { return nil }
        let country = String(String.UnicodeScalarView(characters[0..<2])).uppercased()
        // Registered countries have one fixed length; others are tried shortest first so
        // trailing words can never be absorbed into a lucky checksum.
        let lengths = IBAN.lengths[country].map { [$0] } ?? Array(15...min(34, characters.count))
        for length in lengths where length <= characters.count {
            // An IBAN must not be followed directly by more letters or digits.
            if length < characters.count, endIndices[length - 1] == endIndices[length] - 1 { continue }
            if IBAN.isValid(Array(characters[0..<length])) { return endIndices[length - 1] }
        }
        return nil
    }

    // MARK: Number spans

    private static func removeNumberSpans(_ s: inout [Unicode.Scalar]) -> Int {
        var count = 0
        var index = 0
        while index < s.count {
            guard isDigit(s[index]) else { index += 1; continue }
            // Extend backwards over an international prefix marker such as "+" or "(".
            var spanStart = index
            var probe = index - 1
            var hasPlus = false
            while probe >= 0, probe >= index - 3, !isDigit(s[probe]), !isLetter(s[probe]) {
                if s[probe] == "+" || s[probe] == "\u{FF0B}" { hasPlus = true; spanStart = probe }
                if s[probe] == "(" { spanStart = probe }
                probe -= 1
            }
            // Collect digit groups separated by 1–3 non-letter, non-digit characters.
            var groups: [[UInt8]] = []
            var current: [UInt8] = []
            var cursor = index
            var spanEnd = index
            while cursor < s.count {
                let c = s[cursor]
                if isDigit(c) {
                    current.append(UInt8(c.value - 48))
                    cursor += 1
                    spanEnd = cursor
                } else if isLetter(c) {
                    break
                } else {
                    var gap = cursor
                    while gap < s.count, gap - cursor < 4, !isDigit(s[gap]), !isLetter(s[gap]) { gap += 1 }
                    if gap < s.count, gap - cursor <= 3, isDigit(s[gap]) {
                        if !current.isEmpty { groups.append(current); current = [] }
                        cursor = gap
                    } else {
                        break
                    }
                }
            }
            if !current.isEmpty { groups.append(current) }
            let digits = groups.flatMap { $0 }
            let intlPrefix = (hasPlus && digits.count >= 7) || (digits.count >= 8 && digits.starts(with: [0, 0]))
            let phoneFormatted = digits.count >= 8 && groups.count >= 2
            let longRun = groups.contains { $0.count >= Defaults.piiDigitRun }
            if intlPrefix || phoneFormatted || longRun || containsCard(groups) {
                s.replaceSubrange(spanStart..<spanEnd, with: [" "])
                count += 1
                index = spanStart + 1
            } else {
                index = spanEnd
            }
        }
        return count
    }

    /// True if consecutive groups form a Luhn-valid number of 13–19 digits.
    static func containsCard(_ groups: [[UInt8]]) -> Bool {
        for start in groups.indices {
            var digits: [UInt8] = []
            for end in start..<groups.count {
                digits += groups[end]
                if digits.count > 19 { break }
                if digits.count >= 13, Luhn.isValid(digits) { return true }
            }
        }
        // A single long group may hold a card next to other digits.
        for group in groups where group.count > 19 {
            for start in 0...(group.count - 13) {
                for length in 13...19 where start + length <= group.count {
                    if Luhn.isValid(Array(group[start..<(start + length)])) { return true }
                }
            }
        }
        return false
    }
}

/// Luhn (mod 10) checksum for card numbers.
public enum Luhn {
    public static func isValid(_ digits: [UInt8]) -> Bool {
        guard digits.count >= 2 else { return false }
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            var value = Int(digit)
            if offset % 2 == 1 {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
        }
        return sum % 10 == 0
    }

    public static func isValid(_ text: String) -> Bool {
        let digits = text.unicodeScalars.compactMap { s -> UInt8? in
            (48...57).contains(s.value) ? UInt8(s.value - 48) : nil
        }
        return isValid(digits)
    }
}

/// IBAN mod-97 checksum (ISO 13616).
public enum IBAN {
    /// Registered IBAN lengths by country (ISO 13616 registry).
    static let lengths: [String: Int] = [
        "AD": 24, "AE": 23, "AL": 28, "AT": 20, "AZ": 28, "BA": 20, "BE": 16, "BG": 22, "BH": 22, "BR": 29,
        "BY": 28, "CH": 21, "CR": 22, "CY": 28, "CZ": 24, "DE": 22, "DK": 18, "DO": 28, "EE": 20, "EG": 29,
        "ES": 24, "FI": 18, "FO": 18, "FR": 27, "GB": 22, "GE": 22, "GI": 23, "GL": 18, "GR": 27, "GT": 28,
        "HR": 21, "HU": 28, "IE": 22, "IL": 23, "IQ": 23, "IS": 26, "IT": 27, "JO": 30, "KW": 30, "KZ": 20,
        "LB": 28, "LC": 32, "LI": 21, "LT": 20, "LU": 20, "LV": 21, "LY": 25, "MC": 27, "MD": 24, "ME": 22,
        "MK": 19, "MR": 27, "MT": 31, "MU": 30, "NL": 18, "NO": 15, "PK": 24, "PL": 28, "PS": 29, "PT": 25,
        "QA": 29, "RO": 24, "RS": 22, "SA": 24, "SC": 31, "SD": 18, "SE": 24, "SI": 19, "SK": 24, "SM": 27,
        "ST": 25, "SV": 28, "TL": 23, "TN": 24, "TR": 26, "UA": 29, "VA": 22, "VG": 24, "XK": 20,
    ]

    public static func isValid(_ characters: [Unicode.Scalar]) -> Bool {
        guard characters.count >= 15, characters.count <= 34 else { return false }
        let upper = characters.map { s -> Unicode.Scalar in
            (97...122).contains(s.value) ? Unicode.Scalar(s.value - 32)! : s
        }
        guard upper[0].value >= 65, upper[0].value <= 90, upper[1].value >= 65, upper[1].value <= 90,
              (48...57).contains(upper[2].value), (48...57).contains(upper[3].value) else { return false }
        let rearranged = Array(upper[4...]) + Array(upper[0..<4])
        var remainder = 0
        for scalar in rearranged {
            let v = scalar.value
            if (48...57).contains(v) {
                remainder = (remainder * 10 + Int(v - 48)) % 97
            } else if (65...90).contains(v) {
                let n = Int(v - 55)
                remainder = (remainder * 100 + n) % 97
            } else {
                return false
            }
        }
        return remainder == 1
    }

    public static func isValid(_ text: String) -> Bool {
        isValid(text.unicodeScalars.filter { $0 != " " })
    }
}
