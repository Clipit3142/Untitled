import Testing
@testable import NomenCore

/// H6: the four presets produce exactly the reference outputs in 3.10.
struct PresetTests {
    static let referenceFields = NameFields(
        kind: .builtIn(.invoice),
        source: "Swisscom",
        subject: "mobile subscription November",
        date: DateValue(year: 2026, month: 11, day: 27),
        dateSource: .content
    )

    static let context = FormatContext(language: .english, fileExtension: "pdf")

    @Test(arguments: [
        ("Clean", "2026-11-27 Swisscom Invoice Mobile Subscription November.pdf"),
        ("Compact", "20261127_swisscom_invoice_mobile_subscription_november.pdf"),
        ("Descriptive", "Invoice – Mobile Subscription November – Swisscom – 2026-11-27.pdf"),
        ("Kebab", "2026-11-27-swisscom-invoice-mobile-subscription-november.pdf"),
    ])
    func presetMatchesReference(presetName: String, expected: String) throws {
        let style = try #require(Presets.all.first { $0.name == presetName })
        let result = NameFormatter.format(Self.referenceFields, style: style, context: Self.context)
        #expect(result.fileName == expected)
        #expect(result.missingRequiredTokens.isEmpty)
    }

    @Test func presetsAreValidStyles() {
        for preset in Presets.all {
            #expect(StyleValidator.issues(preset).isEmpty, "\(preset.name): \(StyleValidator.issues(preset))")
        }
    }

    @Test func descriptivePresetWouldExceedSixtyCharacters() {
        // Part 5 #8: the Descriptive reference is 62 characters, hence max length 80.
        var sixty = Presets.descriptive
        sixty.maxLength = 60
        let result = NameFormatter.format(Self.referenceFields, style: sixty, context: Self.context)
        #expect(result.base.count <= 60)
        #expect(result.base != "Invoice – Mobile Subscription November – Swisscom – 2026-11-27")
    }
}
