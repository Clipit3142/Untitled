import Foundation
import Testing
import NomenTestSupport
@testable import NomenCore

/// G6 and G7: the sanitizer always produces a valid filename.
struct SanitizerTests {
    /// G6: 100,000 random Unicode inputs produce valid output: NFC, ≤ 255 bytes, no
    /// forbidden or invisible control characters.
    @Test func hundredThousandRandomInputsAreValid() {
        var generator = SeededGenerator(seed: 0x6E6F_6D65_6E06)
        var produced = 0
        for _ in 0..<100_000 {
            let input = generator.troublesomeString(maxLength: 300)
            guard let output = Sanitizer.sanitizeFileName(input) else { continue }
            produced += 1
            #expect(Sanitizer.isValidFileName(output), "input: \(input.unicodeScalars.map { String($0.value, radix: 16) })")
            #expect(output.utf8.count <= 255)
            #expect(output == output.precomposedStringWithCanonicalMapping)
            #expect(!output.contains("/") && !output.contains(":"))
            #expect(!output.unicodeScalars.contains { $0.properties.generalCategory == .control })
            #expect(!output.unicodeScalars.contains { $0.properties.isBidiControl })
        }
        #expect(produced > 50_000)
    }

    @Test func removesForbiddenAndInvisibleCharacters() throws {
        let tricky = "invoice\u{202E}fdp.exe"
        let cleaned = try #require(Sanitizer.sanitizeFileName(tricky))
        #expect(cleaned == "invoicefdp.exe")
        #expect(Sanitizer.sanitizeFileName("a/b:c\u{0}d") == "abcd")
        #expect(Sanitizer.sanitizeFileName("zero\u{200B}width\u{FEFF}") == "zerowidth")
        #expect(Sanitizer.sanitizeFileName("tab\there\nnewline") == "tab here newline")
        #expect(Sanitizer.sanitizeFileName("nbsp\u{00A0}space") == "nbsp space")
        #expect(Sanitizer.sanitizeFileName("...hidden") == "hidden")
        #expect(Sanitizer.sanitizeFileName("  --trim me--  ") == "trim me")
        #expect(Sanitizer.sanitizeFileName("\u{200B}\u{202E}") == nil)
    }

    @Test func normalizesToNFC() throws {
        let decomposed = "Cafe\u{301}"
        let cleaned = try #require(Sanitizer.sanitizeFileName(decomposed))
        #expect(cleaned.unicodeScalars.count == 4)
        #expect(cleaned == "Café")
    }

    @Test func collapsesRepeatedSeparators() {
        #expect(Sanitizer.collapseAndTrim("a  b", partSeparator: " ", wordSeparator: " ") == "a b")
        #expect(Sanitizer.collapseAndTrim("a--b__c..d", partSeparator: "-", wordSeparator: "-") == "a-b_c.d")
        #expect(Sanitizer.collapseAndTrim("a - - b", partSeparator: " - ", wordSeparator: " ") == "a - b")
        #expect(Sanitizer.collapseAndTrim("a – b", partSeparator: " – ", wordSeparator: " ") == "a – b")
    }

    @Test func keepsEmojiSequencesOnlyWhenAllowed() {
        let family = "Family 👨‍👩‍👧 trip"
        #expect(Sanitizer.stripForbidden(family, allowEmoji: true).contains("👨‍👩‍👧"))
        let noEmoji = Sanitizer.applyCharacterOptions(family, CharacterOptions(allowEmoji: false))
        let hasEmoji = noEmoji.contains { $0.isEmojiGrapheme }
        #expect(!hasEmoji)
        #expect(Sanitizer.applyCharacterOptions("Brand™ ©", CharacterOptions()) == "Brand™ ©")
    }

    @Test func cutsToTwoHundredFiftyFiveBytesKeepingTheExtension() throws {
        let long = String(repeating: "東", count: 200) + ".pdf"
        let cleaned = try #require(Sanitizer.sanitizeFileName(long))
        #expect(cleaned.utf8.count <= 255)
        #expect(cleaned.hasSuffix(".pdf"))
    }

    // MARK: G7

    @Test func windowsSafeRemovesReservedCharactersAndNames() throws {
        let cleaned = try #require(Sanitizer.sanitizeFileName("a\\b*c?d\"e<f>g|h.", windowsSafe: true))
        #expect(cleaned == "abcdefgh")
        #expect(Sanitizer.sanitizeFileName("CON.txt", windowsSafe: true) == "CON_.txt")
        #expect(Sanitizer.sanitizeFileName("lpt1", windowsSafe: true) == "lpt1_")
        #expect(Sanitizer.sanitizeFileName("COM¹.pdf", windowsSafe: true) == "COM¹_.pdf")
        #expect(Sanitizer.sanitizeFileName("Console.txt", windowsSafe: true) == "Console.txt")
    }

    @Test func windowsSafePropertyHoldsForRandomInput() {
        var generator = SeededGenerator(seed: 77)
        let reserved = ["CON", "PRN", "AUX", "NUL", "COM1", "LPT9", "com3", "Nul"]
        for index in 0..<20_000 {
            var input = generator.troublesomeString(maxLength: 60)
            if index % 10 == 0 { input = reserved.randomElement(using: &generator)! + (index % 20 == 0 ? ".txt" : "") }
            guard let output = Sanitizer.sanitizeFileName(input, windowsSafe: true) else { continue }
            #expect(Sanitizer.isValidFileName(output, windowsSafe: true), "\(input) → \(output)")
            #expect(!output.contains(where: { "\\*?\"<>|".contains($0) }))
            #expect(!output.hasSuffix(" ") && !output.hasSuffix("."))
        }
    }

    @Test func formatterWithWindowsSafeStyleNeverProducesReservedNames() {
        var style = Presets.clean
        style.characters.windowsSafe = true
        style.template = [.subject(required: true)]
        for word in ["con", "PRN", "aux", "nul", "COM1", "lpt3"] {
            let name = NameFormatter.format(NameFields(subject: word), style: style, context: FormatContext(fileExtension: "txt"))
            #expect(Sanitizer.isValidFileName(name.fileName, windowsSafe: true), "\(word) → \(name.fileName)")
        }
    }
}
