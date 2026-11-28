import Foundation
import Testing
@testable import UntitledUI
import UntitledCore
import UntitledEngine
import UntitledModel
import UntitledTestSupport

@Suite("Motion (S1, S2)")
struct MotionTests {
    @Test("No animation exceeds 0.5 s")
    func limits() {
        for (name, curve) in Motion.all {
            #expect(curve.duration <= Motion.limit, "\(name)")
            #expect(curve.duration > 0, "\(name)")
        }
        #expect(Motion.standard.duration == 0.3)
        #expect(Motion.control.duration == 0.2)
        #expect(Motion.panelOpen.duration == 0.35 && Motion.panelOpen.bounce > 0)
        #expect(Motion.renameOut.duration == 0.2 && Motion.renameIn.duration == 0.25)
    }

    @Test("Reduce Motion leaves only crossfades of at most 0.2 s")
    func reduced() {
        for (name, curve) in Motion.all {
            let resolved = Motion.resolved(curve, reduceMotion: true)
            #expect(resolved.kind == .crossfade, "\(name)")
            #expect(resolved.duration <= 0.2, "\(name)")
            #expect(Motion.resolved(curve, reduceMotion: false) == curve)
        }
        #expect(!Motion.allowsMovement(reduceMotion: true))
    }
}

@Suite("Menu bar glyph (N1, R5)")
struct GlyphTests {
    @Test("Five states, each with its own shape")
    func distinctShapes() {
        let shapes = GlyphState.allCases.map { GlyphPath.shapes(for: $0) }
        #expect(Set(shapes).count == 5)
        #expect(Set(GlyphState.allCases.map(\.badge)).count == 5)
        // Every badge stays inside the 18-point box.
        for state in GlyphState.allCases {
            for shape in GlyphPath.shapes(for: state) {
                for element in shape.elements {
                    switch element {
                    case .move(let x, let y), .line(let x, let y):
                        #expect((0...18).contains(x) && (0...18).contains(y), "\(state)")
                    case .ellipse(let x, let y, let w, let h):
                        #expect(x >= 0 && y >= 0 && x + w <= 18 && y + h <= 18, "\(state)")
                    case .close: break
                    }
                }
            }
        }
    }

    @Test("State priority: problem, paused, working, review, idle")
    func priority() {
        #expect(GlyphState.state(status: .needsAttention(folderName: "Desktop"), reviewCount: 3, isWorking: true) == .problem)
        #expect(GlyphState.state(status: .paused(until: nil), reviewCount: 3, isWorking: true) == .paused)
        #expect(GlyphState.state(status: .held(.lowPowerMode), reviewCount: 0, isWorking: false) == .paused)
        #expect(GlyphState.state(status: .watching(folderNames: ["Desktop"]), reviewCount: 2, isWorking: true) == .working)
        #expect(GlyphState.state(status: .watching(folderNames: ["Desktop"]), reviewCount: 2, isWorking: false) == .needsReview)
        #expect(GlyphState.state(status: .basicNaming(folderNames: ["Desktop"]), reviewCount: 0, isWorking: false) == .idle)
        #expect(GlyphState.state(status: .waitingForAppleIntelligence, reviewCount: 0, isWorking: false) == .idle)
    }

    @Test("Only the working glyph animates, never with Reduce Motion")
    func animation() {
        for state in GlyphState.allCases {
            #expect(state.animates(reduceMotion: false) == (state == .working))
            #expect(!state.animates(reduceMotion: true))
        }
        #expect(GlyphPath.shapes(for: .working, frame: 0) != GlyphPath.shapes(for: .working, frame: 1))
        #expect(GlyphPath.shapes(for: .paused, frame: 0) == GlyphPath.shapes(for: .paused, frame: 1))
    }

    @Test("Every state has a VoiceOver label and renders as SVG")
    func labels() throws {
        // Set UNTITLED_GLYPH_OUT to a folder to export the glyphs for visual review.
        if let folder = ProcessInfo.processInfo.environment["UNTITLED_GLYPH_OUT"] {
            for state in GlyphState.allCases {
                for scale in [1.0, 2.0] {
                    try GlyphPath.svg(for: state, scale: scale)
                        .write(toFile: "\(folder)/\(state.rawValue)@\(Int(scale))x.svg", atomically: true, encoding: .utf8)
                }
            }
        }
        #expect(Set(GlyphState.allCases.map(\.accessibilityLabel)).count == 5)
        for state in GlyphState.allCases {
            let svg = GlyphPath.svg(for: state, scale: 2)
            #expect(svg.hasPrefix("<svg") && svg.contains("width=\"36.0\""))
        }
    }
}

@Suite("Settings explanations (O4)")
struct SettingsCatalogTests {
    @Test("Every setting has a one-line explanation")
    func explanations() {
        var titles = Set<String>()
        for key in SettingKey.allCases {
            let descriptor = SettingsCatalog.descriptor(key)
            #expect(!descriptor.title.isEmpty, "\(key)")
            #expect(!descriptor.explanation.isEmpty, "\(key)")
            #expect(!descriptor.explanation.contains("\n"), "\(key)")
            #expect(descriptor.explanation.hasSuffix("."), "\(key)")
            #expect(descriptor.explanation.count <= 110, "\(key): \(descriptor.explanation.count)")
            titles.insert((descriptor.tab?.rawValue ?? "window") + descriptor.title)
        }
        #expect(titles.count == SettingKey.allCases.count)
    }

    @Test("Every Settings tab has the settings 3.15 lists")
    func tabs() {
        let general = SettingsCatalog.settings(in: .general).map(\.key)
        #expect(general == [.launchAtLogin, .showInDock, .pauseInLowPowerMode, .renameSound])
        #expect(SettingsCatalog.settings(in: .appleIntelligence).map(\.key) == [.appleIntelligenceStatus, .basicNamingOnly, .onBattery])
        #expect(SettingsCatalog.settings(in: .privacy).map(\.key) == [.clearHistory, .clearLearnedData, .resetEverything])
        #expect(SettingsCatalog.settings(in: .advanced).map(\.key) == [.stabilityWait, .pdfPages, .historyRetention, .exportDiagnostics])
        #expect(!SettingsCatalog.settings(in: .notifications).isEmpty)
        #expect(SettingsCatalog.privacyStatement.contains("Everything stays on this Mac. Untitled has no internet access."))
    }
}

@Suite("Onboarding flow (B7, B6)")
struct OnboardingTests {
    @Test("Seven steps, back and forward, finishing allows watching")
    func steps() throws {
        var flow = OnboardingFlow()
        #expect(OnboardingFlow.Step.allCases.count == 7)
        #expect(!flow.allowsWatching && !flow.canGoBack)
        for expected in 2...7 {
            flow.next()
            #expect(flow.step.rawValue == expected)
            #expect(!flow.allowsWatching)
        }
        flow.back()
        #expect(flow.step == .permissions)
        flow.next()
        flow.next()
        #expect(flow.completion == .finished && flow.allowsWatching)
        let decoded = try JSONDecoder().decode(OnboardingFlow.self, from: JSONEncoder().encode(flow))
        #expect(decoded == flow)
        var skipped = OnboardingFlow(step: .style)
        skipped.skip()
        #expect(skipped.allowsWatching && skipped.completion == .skipped)
    }

    @Test("Step 1 carries the privacy promise")
    func promise() {
        #expect(OnboardingFlow.Step.welcome.subtitle == "Everything stays on this Mac. Untitled has no internet access.")
    }

    @Test("The saved-elsewhere tip appears after 10 s without a screenshot")
    func demoTip() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var demo = ScreenshotDemo(started: start)
        #expect(!demo.showsSavedElsewhereTip(now: start.addingTimeInterval(9.9)))
        #expect(demo.showsSavedElsewhereTip(now: start.addingTimeInterval(10)))
        demo.renamedName = "2026-11-27 Safari Flight Booking.png"
        #expect(!demo.showsSavedElsewhereTip(now: start.addingTimeInterval(30)))
        #expect(ScreenshotDemo.screenshotFolder(location: nil, home: "/Users/a") == "/Users/a/Desktop")
        #expect(ScreenshotDemo.screenshotFolder(location: "~/Pictures/Shots/", home: "/Users/a") == "/Users/a/Pictures/Shots")
        #expect(ScreenshotDemo.screenshotFolder(location: "/Volumes/X", home: "/Users/a") == "/Volumes/X")
    }
}

@Suite("Panel placement (N2)")
struct PlacementTests {
    @Test("The menu bar panel is never off-screen, on any screen layout")
    func neverOffScreen() {
        var generator = SeededGenerator(seed: 2026)
        for _ in 0..<5_000 {
            let width = Double.random(in: 600...6_000, using: &generator)
            let height = Double.random(in: 600...6_000, using: &generator)
            let screen = ScreenRect(x: Double.random(in: -5_000...5_000, using: &generator),
                                    y: Double.random(in: -5_000...5_000, using: &generator), width: width, height: height)
            // The status item sits in the menu bar at the top, anywhere along it, even partly past an edge.
            let itemX = Double.random(in: (screen.minX - 30)...(screen.maxX + 10), using: &generator)
            let item = ScreenRect(x: itemX, y: screen.maxY, width: 24, height: 24)
            let panelHeight = Double.random(in: 200...7_000, using: &generator)
            let frame = PanelPlacement.menuBarPanel(size: (360, panelHeight), statusItem: item, visibleFrame: screen)
            #expect(screen.contains(frame), "\(frame) in \(screen)")
            #expect(frame.width > 0 && frame.height > 0)
        }
    }

    @Test("The panel hangs below the status item when there is room")
    func belowItem() {
        let screen = ScreenRect(x: 0, y: 0, width: 1_440, height: 875)
        let item = ScreenRect(x: 1_200, y: 875, width: 24, height: 24)
        let frame = PanelPlacement.menuBarPanel(size: (360, 400), statusItem: item, visibleFrame: screen)
        #expect(frame.maxY == 875 - Metrics.panelGap)
        #expect(abs(frame.midX - item.midX) < 0.001)
        let edge = PanelPlacement.menuBarPanel(size: (360, 400), statusItem: ScreenRect(x: 1_420, y: 875, width: 24, height: 24), visibleFrame: screen)
        #expect(edge.maxX == 1_440 - Metrics.screenMargin)
    }

    @Test("Quick Rename sits in the upper third of the active screen")
    func quickRename() {
        let screen = ScreenRect(x: 0, y: 0, width: 1_440, height: 900)
        let frame = PanelPlacement.quickRename(size: (520, 200), visibleFrame: screen)
        #expect(abs(frame.midX - 720) < 0.001)
        let center = frame.y + frame.height / 2
        #expect(center >= 600 - 0.001 && center <= 900)
        #expect(screen.contains(frame))
        let vertical = ScreenRect(x: 1_440, y: -500, width: 1_080, height: 1_920)
        #expect(vertical.contains(PanelPlacement.quickRename(size: (520, 2_400), visibleFrame: vertical)))
    }
}

@Suite("Dock policy (O1)")
struct DockPolicyTests {
    @Test("In the Dock while a window is open, or when Show in Dock is on")
    func presence() {
        #expect(DockPolicy(showInDock: false).presence == .accessory)
        #expect(DockPolicy(showInDock: false, openWindows: 1).presence == .regular)
        #expect(DockPolicy(showInDock: true).presence == .regular)
        let closed = DockPolicy(showInDock: false, openWindows: 0)
        #expect(closed.delay(from: .regular) <= 1)
        #expect(closed.delay(from: .regular) > 0)
        #expect(DockPolicy(showInDock: false, openWindows: 1).delay(from: .accessory) == 0)
    }
}

@Suite("Row text and grouping (3.17)")
struct RowTextTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }

    @Test("Rows read naturally for VoiceOver")
    func voiceOver() {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let label = RowText.renamedLabel(oldName: "Screenshot 2026-11-27 at 14.03.11.png", newName: "Safari Flight Booking.png",
                                         time: now.addingTimeInterval(-120), now: now, calendar: calendar)
        #expect(label == "Renamed Screenshot 2026-11-27 at 14.03.11.png to Safari Flight Booking.png, 2 minutes ago")
        #expect(RowText.relative(now.addingTimeInterval(-20), now: now, calendar: calendar) == "just now")
        #expect(RowText.relative(now.addingTimeInterval(-60), now: now, calendar: calendar) == "1 minute ago")
        #expect(RowText.reviewLabel(proposedName: "A.pdf", currentName: "B.pdf", lowConfidence: true, destination: "Invoices")
                == "A.pdf, proposed for B.pdf, moves to Invoices, low confidence")
        #expect(RowText.was("x.png") == "was x.png")
    }

    @Test("Activity groups by local day")
    func grouping() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 15))!
        let times = [now.addingTimeInterval(-60), now.addingTimeInterval(-3_600), now.addingTimeInterval(-86_400),
                     now.addingTimeInterval(-4 * 86_400)]
        let groups = ActivityGrouping.byDay(times, time: { $0 }, now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Today", "Yesterday", "Monday 23 November"])
        #expect(groups.map(\.items.count) == [2, 1, 1])
    }
}

@Suite("Style preview (3.19)")
struct StylePreviewTests {
    @Test("Presets render the reference names, from stored fields only")
    func presets() {
        let clean = StylePreview.rows(style: Presets.clean)
        #expect(clean[0].fileName == "2026-11-27 Swisscom Invoice Mobile Subscription November.pdf")
        let compact = StylePreview.rows(style: Presets.compact)
        #expect(compact[0].fileName == "20261127_swisscom_invoice_mobile_subscription_november.pdf")
        let descriptive = StylePreview.rows(style: Presets.descriptive)
        #expect(descriptive[0].fileName == "Invoice – Mobile Subscription November – Swisscom – 2026-11-27.pdf")
        let kebab = StylePreview.rows(style: Presets.kebab)
        #expect(kebab[0].fileName == "2026-11-27-swisscom-invoice-mobile-subscription-november.pdf")
        #expect(clean[2].isScreenshot)
    }

    @Test("The preview takes at most 50 ms")
    func speed() {
        let clock = ContinuousClock()
        var worst = Duration.zero
        for style in Presets.all {
            let start = clock.now
            _ = StylePreview.rows(style: style)
            worst = max(worst, clock.now - start)
        }
        #expect(worst < .milliseconds(50))
    }
}

@Suite("Apple Intelligence states (B2)")
struct AppleIntelligencePaneTests {
    @Test("Each state has its own title, and a settings button where something can change")
    func states() {
        let all: [ModelAvailability] = [.available, .appleIntelligenceNotEnabled, .deviceNotEligible, .modelNotReady, .basicOnly]
        #expect(Set(all.map { AppleIntelligencePane($0).title }).count == all.count)
        #expect(AppleIntelligencePane(.appleIntelligenceNotEnabled).settingsButtonTitle != nil)
        #expect(AppleIntelligencePane(.deviceNotEligible).settingsButtonTitle == nil)
        #expect(AppleIntelligencePane.settingsURL.scheme == "x-apple.systempreferences")
    }
}

@Suite("Why this name? (M2)")
struct WhyThisNameTests {
    @Test("Every part of the name has an explanation, with or without stored evidence")
    func coversEveryPart() {
        var generator = SeededGenerator(seed: 7)
        let kinds: [KindRef] = [.builtIn(.invoice), .builtIn(.webPage), .other]
        for _ in 0..<500 {
            let fields = NameFields(kind: kinds.randomElement(using: &generator)!, source: Bool.random(using: &generator) ? "Swisscom" : nil,
                                    subject: ["Mobile subscription", "Flight booking", ""].randomElement(using: &generator)!,
                                    date: DateValue(year: 2026, month: 11, day: Int.random(in: 1...28, using: &generator)),
                                    dateSource: DateSource.allCases.randomElement(using: &generator), app: "Safari", original: "Draft")
            var style = Presets.all.randomElement(using: &generator)!
            style.template.append(.original())
            style.template.append(.text("v1"))
            let screenshot = Bool.random(using: &generator)
            let formatted = NameFormatter.format(fields, style: style, context: FormatContext(fileExtension: "pdf", isScreenshot: screenshot))
            let evidence = Bool.random(using: &generator) ? [PartEvidence(token: .source, explanation: "“Swisscom AG” on page 1")] : []
            let proposal = Proposal(fields: fields, fileName: formatted.fileName, parts: formatted.parts, evidence: evidence,
                                    confidence: .high, lowReasons: [], styleID: style.id, styleVersion: 1, path: .model,
                                    language: .english, isScreenshot: screenshot)
            let rows = WhyThisName.rows(for: proposal)
            #expect(rows.count >= formatted.parts.count)
            for (part, row) in zip(formatted.parts, rows) {
                #expect(row.text == part.text)
                #expect(!row.explanation.isEmpty)
            }
        }
    }

    @Test("Basic naming and low confidence are explained")
    func basicAndLow() {
        let proposal = Proposal(fields: NameFields(subject: "Scan"), fileName: "Scan.pdf", parts: [RenderedPart(token: .subject, text: "Scan", required: true)],
                                evidence: [], confidence: .low, lowReasons: [.littleContent], styleID: "x", styleVersion: 1, path: .basic,
                                language: .english, isScreenshot: false)
        let rows = WhyThisName.rows(for: proposal)
        #expect(rows.map(\.label) == ["Subject", "Naming", "Low confidence"])
    }
}

@Suite("Field editing (M2)")
struct FieldEditingTests {
    @Test("Dates round-trip through the inspector field; invalid text is refused")
    func dates() {
        let date = DateValue(year: 2026, month: 11, day: 27, hour: 9, minute: 5)
        #expect(FieldEditing.dateText(date) == "2026-11-27 09:05")
        #expect(FieldEditing.parseDate("2026-11-27 09:05") == .some(date))
        #expect(FieldEditing.parseDate("2026-11-27") == .some(DateValue(year: 2026, month: 11, day: 27)))
        #expect(FieldEditing.parseDate("") == .some(nil))
        for bad in ["2026-02-30", "27.11.2026", "2026-11-27 25:00", "2026-11", "x", "2026-11-27 9:5", "2026-11-27 09:05 extra"] {
            #expect(FieldEditing.parseDate(bad) == nil, "\(bad)")
        }
    }

    @Test("Kind options include every built-in kind, custom kinds and Other")
    func kinds() {
        let options = FieldEditing.kindOptions(customKinds: [CustomKind(id: "c1", label: "Lab Result")])
        #expect(options.count == BuiltInKind.allCases.count + 2)
        #expect(options.last?.kind == .other)
        #expect(options.contains { $0.kind == .custom(id: "c1") })
        #expect(Set(options.map(\.id)).count == options.count)
    }
}

@Suite("Style editing (3.15, H7)")
struct StyleEditingTests {
    @Test("Chips move, toggle and disappear as the token bar shows")
    func tokenBar() {
        var template = Presets.clean.template
        StyleEditing.move(&template, from: 0, to: template.count)
        #expect(template.map(\.kind) == [.source, .kind, .subject, .date])
        StyleEditing.move(&template, from: 3, to: 0)
        #expect(template.map(\.kind) == [.date, .source, .kind, .subject])
        StyleEditing.move(&template, from: 9, to: 0)
        #expect(template.count == 4)
        StyleEditing.toggleRequired(&template, at: 1)
        #expect(template[1].required)
        #expect(StyleEditing.chipTitle(template[1]) == "Source (required)")
        StyleEditing.remove(&template, at: 1)
        #expect(!template.contains { $0.kind == .source })
        #expect(StyleEditing.addable(to: template, screenshot: false) == [.source, .original, .text])
        #expect(StyleEditing.addable(to: Presets.clean.screenshotTemplate, screenshot: true).contains(.kind))
    }

    @Test("Every option has a label, and invalid drafts report why")
    func labels() {
        #expect(Set(PartSeparator.allCases.map(StyleEditing.label)).count == PartSeparator.allCases.count)
        #expect(Set(WordSeparator.allCases.map(StyleEditing.label)).count == WordSeparator.allCases.count)
        #expect(Set(CaseMode.allCases.map(StyleEditing.label)).count == CaseMode.allCases.count)
        #expect(Set(TimeFormat.allCases.map(StyleEditing.label)).count == TimeFormat.allCases.count)
        #expect(Set(DateSource.allCases.map(StyleEditing.label)).count == DateSource.allCases.count)
        var draft = Presets.clean
        draft.template = []
        #expect(!StyleValidator.issues(draft).isEmpty)
        #expect(StyleEditing.list(" iPhone, PDF ,, macOS") == ["iPhone", "PDF", "macOS"])
    }
}

@Suite("Rule editing (3.12)")
struct RuleEditingTests {
    @Test("Conditions round-trip through the editor and rules reorder like a list")
    func editing() {
        for kind in RuleEditing.ConditionKind.allCases {
            let condition = kind.placeholder
            #expect(RuleEditing.kind(of: condition) == kind)
            if RuleEditing.text(of: condition) != nil {
                #expect(RuleEditing.text(of: RuleEditing.with(text: "x", condition)) == "x")
            }
        }
        let rule = Rule(id: "r", name: "Invoices", conditions: [.kindIs(.builtIn(.invoice)), .sourceContains("Swisscom")], destinationID: "d")
        #expect(RuleEditing.summary(rule, destination: "Invoices") == "When kind is Invoice and source contains “Swisscom” → Invoices")
        var rules = ["a", "b", "c", "d"].map { Rule(id: $0, name: $0, conditions: [], destinationID: "d") }
        RuleEditing.move(&rules, from: IndexSet(integer: 0), to: 3)
        #expect(rules.map(\.id) == ["b", "c", "a", "d"])
        RuleEditing.move(&rules, from: IndexSet([2, 3]), to: 0)
        #expect(rules.map(\.id) == ["a", "d", "b", "c"])
    }
}

@Suite("About (A5)")
struct LicenseTests {
    @Test("GRDB's MIT license appears in About")
    func grdb() {
        #expect(Licenses.aboutCredits.contains("GRDB"))
        #expect(Licenses.grdb.contains("Gwendal Roué"))
        #expect(Licenses.grdb.contains("Permission is hereby granted, free of charge"))
    }
}
