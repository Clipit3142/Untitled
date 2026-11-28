import Foundation
import Testing
import UntitledTestSupport
@testable import UntitledCore

/// G3: across 1,000 adversarial PII fixtures, no card numbers, IBANs, emails, phone numbers
/// or runs of 9+ digits end up in names.
struct PIIGuardTests {
    enum Kind: String, CaseIterable, Sendable { case card, iban, email, phone, digitRun }

    struct Fixture: Sendable {
        var kind: Kind
        var value: String
    }

    // MARK: Generators

    static func luhnCard(_ g: inout SeededGenerator, length: Int) -> [UInt8] {
        let prefixes: [[UInt8]] = [[4], [5, 1], [5, 5], [3, 4], [3, 7], [6, 0, 1, 1], [3, 5, 2, 8], [2, 2, 2, 1]]
        var digits = prefixes.randomElement(using: &g)!
        while digits.count < length - 1 { digits.append(UInt8.random(in: 0...9, using: &g)) }
        for check in UInt8(0)...9 where Luhn.isValid(digits + [check]) {
            return digits + [check]
        }
        return digits + [0]
    }

    static func iban(_ g: inout SeededGenerator) -> String {
        let formats: [(String, Int, Bool)] = [("CH", 17, false), ("DE", 18, false), ("FR", 23, false), ("GB", 18, true),
                                              ("NL", 14, true), ("IT", 23, true), ("ES", 20, false), ("AT", 16, false)]
        let (country, bbanLength, letters) = formats.randomElement(using: &g)!
        var bban = ""
        for index in 0..<bbanLength {
            if letters, index < 4 {
                bban.append(Character(Unicode.Scalar(UInt8.random(in: 65...90, using: &g))))
            } else {
                bban.append(Character(String(Int.random(in: 0...9, using: &g))))
            }
        }
        for check in 2...98 {
            let candidate = country + (check < 10 ? "0\(check)" : "\(check)") + bban
            if IBAN.isValid(candidate) { return candidate }
        }
        return country + "00" + bban
    }

    static func digitString(_ digits: [UInt8]) -> String { digits.map(String.init).joined() }

    /// Obfuscates a digit string with separators, Unicode digits and invisible characters.
    static func obfuscate(_ text: String, _ g: inout SeededGenerator) -> String {
        let separators = [" ", "-", ".", "_", "/", "\u{00A0}", "\u{2009}", "\u{200B}", "\u{2013}", "  ", "\u{2060}", "·", "*", ","]
        let groupSizes = [2, 3, 4, 5]
        let digitStyle = Int.random(in: 0..<6, using: &g)
        var output = ""
        var count = 0
        let group = groupSizes.randomElement(using: &g)!
        let separator = separators.randomElement(using: &g)!
        for character in text {
            if count > 0, count % group == 0, Int.random(in: 0..<4, using: &g) > 0 { output += separator }
            if let digit = character.wholeNumberValue, character.isASCII {
                switch digitStyle {
                case 0: output.append(Character(Unicode.Scalar(0xFF10 + UInt32(digit))!)) // full-width
                case 1: output.append(Character(Unicode.Scalar(0x0660 + UInt32(digit))!)) // Arabic-Indic
                case 2: output.append(Character(Unicode.Scalar(0x0966 + UInt32(digit))!)) // Devanagari
                default: output.append(character)
                }
            } else {
                output.append(character)
            }
            count += 1
        }
        return output
    }

    static func phone(_ g: inout SeededGenerator) -> String {
        let patterns = [
            "+41 44 ### ## ##", "0041 44 ### ## ##", "+1 (###) ###-####", "(###) ###-####", "###.###.####",
            "06 ## ## ## ##", "+33 6 ## ## ## ##", "+49 30 ########", "030 ########", "+44 20 #### ####",
            "+81-3-####-####", "+86 138 #### ####", "###-###-####", "+41-79-###-##-##", "+7 (###) ###-##-##",
            "+34 ### ### ###", "+39 02 #### ####", "0800 ### ###", "+61 4## ### ###", "+31 (0)20 ### ####",
        ]
        var result = ""
        for character in patterns.randomElement(using: &g)! {
            result.append(character == "#" ? Character(String(Int.random(in: 0...9, using: &g))) : character)
        }
        return result
    }

    static func email(_ g: inout SeededGenerator) -> String {
        let locals = ["john.doe", "anna+receipts", "Max.Mustermann", "o'connor", "x", "first_last", "üser", "user.name+tag+sorting", "UPPER.CASE", "a.b.c.d"]
        let domains = ["example.com", "mail.example.co.uk", "sub.domain.ch", "gmail.com", "bücher.de", "xn--bcher-kva.de", "EXAMPLE.ORG", "a.io"]
        let at = ["@", "@", "@", "\u{FF20}"].randomElement(using: &g)!
        return locals.randomElement(using: &g)! + at + domains.randomElement(using: &g)!
    }

    static func fixtures() -> [Fixture] {
        var g = SeededGenerator(seed: 0x6733_6733)
        var result: [Fixture] = []
        for _ in 0..<250 {
            let card = digitString(luhnCard(&g, length: Int.random(in: 13...19, using: &g)))
            result.append(Fixture(kind: .card, value: obfuscate(card, &g)))
        }
        for index in 0..<200 {
            var value = iban(&g)
            if index % 2 == 0 {
                value = stride(from: 0, to: value.count, by: 4).map { start -> String in
                    let s = value.index(value.startIndex, offsetBy: start)
                    let e = value.index(s, offsetBy: min(4, value.count - start))
                    return String(value[s..<e])
                }.joined(separator: " ")
            }
            if index % 5 == 0 { value = value.lowercased() }
            result.append(Fixture(kind: .iban, value: value))
        }
        for _ in 0..<200 { result.append(Fixture(kind: .email, value: email(&g))) }
        for index in 0..<200 {
            let value = phone(&g)
            result.append(Fixture(kind: .phone, value: index % 4 == 0 ? value.replacingOccurrences(of: " ", with: "\u{00A0}") : value))
        }
        for _ in 0..<150 {
            let length = Int.random(in: 9...24, using: &g)
            let digits = (0..<length).map { _ in UInt8.random(in: 0...9, using: &g) }
            let embedded = ["ID", "Ref", "No", "", "#", "Kd-Nr."].randomElement(using: &g)! + digitString(digits) + ["", "X", "-A"].randomElement(using: &g)!
            result.append(Fixture(kind: .digitRun, value: embedded))
        }
        return result
    }

    // MARK: Tests

    @Test func thereAreAThousandFixtures() {
        #expect(Self.fixtures().count == 1_000)
    }

    @Test func guardRemovesEveryFixtureFromRawText() {
        for fixture in Self.fixtures() {
            let text = "Payment confirmation \(fixture.value) for November"
            let redacted = PIIGuard.redact(text).text
            #expect(!PIIGuard.containsPII(redacted), "\(fixture.kind): \(fixture.value) → \(redacted)")
            if fixture.kind == .email {
                #expect(!redacted.contains("@"), "\(fixture.value) → \(redacted)")
            } else {
                #expect(!redacted.contains(where: { $0.isNumber }), "\(fixture.kind): \(fixture.value) → \(redacted)")
            }
            #expect(redacted.contains("Payment") && redacted.contains("November"), "\(fixture.kind): \(fixture.value) → \(redacted)")
        }
    }

    /// Plants each fixture in generated fields and formats it with random styles; no digit
    /// from the fixture and no "@" may reach the name.
    @Test func noFixtureReachesAName() {
        var g = SeededGenerator(seed: 0x6733)
        for fixture in Self.fixtures() {
            for _ in 0..<4 {
                var style = FormatterPropertyTests.randomStyle(&g)
                style.template.removeAll { $0.kind == .text }
                guard StyleValidator.isValid(style) else { continue }
                var fields = NameFields(kind: .builtIn(.receipt), source: "Example Bank", subject: "payment confirmation november",
                                        date: DateValue(year: 2026, month: 11, day: 27), app: "Mail", original: "statement")
                switch Int.random(in: 0..<4, using: &g) {
                case 0: fields.subject = "payment \(fixture.value) confirmation"
                case 1: fields.source = fixture.value
                case 2: fields.app = "Mail \(fixture.value)"
                default: fields.original = "scan \(fixture.value)"
                }
                let name = NameFormatter.format(fields, style: style, context: FormatContext(fileExtension: "pdf"))
                let datePart = name.parts.first(where: { $0.token == .date })?.text ?? "\u{0}"
                let withoutDate = name.base.replacingOccurrences(of: datePart, with: "X")
                if fixture.kind == .email {
                    #expect(!withoutDate.contains("@"), "\(fixture.value) → \(name.base)")
                } else {
                    #expect(!withoutDate.contains(where: { $0.isNumber }), "\(fixture.kind): \(fixture.value) → \(name.base)")
                }
            }
        }
    }

    @Test func fixturesSplitAcrossFieldsDoNotReappearTogether() {
        var style = Presets.kebab
        style.template = [.source(), .subject(required: true), .app()]
        let fields = NameFields(source: "+41 44", subject: "123 45 67", app: "89")
        let name = NameFormatter.format(fields, style: style, context: FormatContext(fileExtension: "pdf"))
        #expect(!name.base.contains("44-123-45-67"))
        let digits = name.base.filter(\.isNumber)
        #expect(digits.count < 8, "\(name.base)")
    }

    @Test func ordinaryNumbersSurvive() {
        #expect(PIIGuard.redact("Q3 2026 report").text == "Q3 2026 report")
        #expect(PIIGuard.redact("Invoice 12345678").text == "Invoice 12345678")
        #expect(PIIGuard.redact("Order 4711 of 2026").text == "Order 4711 of 2026")
        #expect(PIIGuard.redact("v1.2.3 release").text == "v1.2.3 release")
    }

    @Test func checksums() {
        #expect(Luhn.isValid("4111 1111 1111 1111"))
        #expect(!Luhn.isValid("4111 1111 1111 1112"))
        #expect(IBAN.isValid("CH93 0076 2011 6238 5295 7"))
        #expect(IBAN.isValid("GB82 WEST 1234 5698 7654 32"))
        #expect(!IBAN.isValid("GB82 WEST 1234 5698 7654 33"))
    }

    @Test func typedNamesAreNotGuarded() throws {
        // The guard applies to generated text only (3.9); a typed name keeps its digits.
        let typed = try TypedName.prepare("Card 4111 1111 1111 1111", fileExtension: "pdf")
        #expect(typed.fileName == "Card 4111 1111 1111 1111.pdf")
    }
}
