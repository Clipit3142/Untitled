import Foundation
import Testing
import UntitledTestSupport
@testable import UntitledCore

/// E6 and G1 (dates), G2 and confidence (3.9), D4 (eligibility), K1 and K3 (rules),
/// H7 (style validation) and H9 (typed names).
struct DateCandidateTests {
    static func values(_ text: String, _ language: NameLanguage? = nil) -> [DateValue] {
        DateCandidateParser.candidates(in: text, language: language).map(\.value)
    }

    static func d(_ y: Int, _ m: Int, _ day: Int) -> DateValue { DateValue(year: y, month: m, day: day)! }

    @Test func findsUnambiguousFormats() {
        #expect(Self.values("Invoice date: 2026-11-27") == [Self.d(2026, 11, 27)])
        #expect(Self.values("Datum 2026/11/27, Ref 20261127") == [Self.d(2026, 11, 27), Self.d(2026, 11, 27)])
        #expect(Self.values("Paid on 27.11.2026") == [Self.d(2026, 11, 27)])
        #expect(Self.values("Due 11/27/2026") == [Self.d(2026, 11, 27)])
        #expect(Self.values("Same day 05/05/2026") == [Self.d(2026, 5, 5)])
        #expect(Self.values("27 November 2026") == [Self.d(2026, 11, 27)])
        #expect(Self.values("Nov 27, 2026 and November 3rd 2026") == [Self.d(2026, 11, 27), Self.d(2026, 11, 3)])
        #expect(Self.values("27. März 2026", .german) == [Self.d(2026, 3, 27)])
        #expect(Self.values("1er décembre 2026", .french) == [Self.d(2026, 12, 1)])
        #expect(Self.values("27 de noviembre de 2026", .spanish) == [Self.d(2026, 11, 27)])
        #expect(Self.values("27 novembre 2026", .italian) == [Self.d(2026, 11, 27)])
        #expect(Self.values("27 de novembro de 2026", .portuguese) == [Self.d(2026, 11, 27)])
        #expect(Self.values("27 november 2026", .dutch) == [Self.d(2026, 11, 27)])
        #expect(Self.values("発行日 2026年11月27日", .japanese) == [Self.d(2026, 11, 27)])
        #expect(Self.values("발행일 2026년 11월 27일", .korean) == [Self.d(2026, 11, 27)])
        #expect(Self.values("Version 10.15.7 and build 1.2.3.4").isEmpty)
    }

    /// E6: ambiguous numeric dates are never used.
    @Test func ambiguousNumericDatesAreDropped() {
        #expect(Self.values("Meeting 03/04/2026").isEmpty)
        #expect(Self.values("Meeting 03/04/2026", .english).isEmpty)
        #expect(Self.values("Termin 03.04.2026", .german) == [Self.d(2026, 4, 3)])
        #expect(Self.values("Paid 15/04/2026, due 03/04/2026") == [Self.d(2026, 4, 15), Self.d(2026, 4, 3)])
        #expect(Self.values("Paid 04/15/2026, due 03/04/2026") == [Self.d(2026, 4, 15), Self.d(2026, 3, 4)])
        #expect(Self.values("Conflicting 15/04/2026 and 04/15/2026 then 03/04/2026") == [Self.d(2026, 4, 15), Self.d(2026, 4, 15)])
    }

    @Test func ambiguousDatesNeverSurviveWithoutSettlingEvidence() {
        var g = SeededGenerator(seed: 0x4536)
        for _ in 0..<10_000 {
            var a = Int.random(in: 1...12, using: &g)
            let b = Int.random(in: 1...12, using: &g)
            if a == b { a = a % 12 + 1 }
            let separator = ["/", ".", "-"].randomElement(using: &g)!
            let year = Bool.random(using: &g) ? "2026" : "26"
            let text = "Document from \(a)\(separator)\(b)\(separator)\(year) about things"
            #expect(Self.values(text, [nil, .english, .japanese].randomElement(using: &g)!).isEmpty, "\(text)")
        }
    }

    @Test func snippetsAreExactSubstrings() {
        let text = "Rechnung vom 27. November 2026, fällig am 2026-12-15"
        for candidate in DateCandidateParser.candidates(in: text, language: .german) {
            #expect(text.contains(candidate.snippet))
        }
    }

    /// G1: every date in a name traces to a candidate snippet or a file date.
    @Test func everyDateTracesToEvidence() {
        var g = SeededGenerator(seed: 0x4731)
        for _ in 0..<5_000 {
            let candidates = DateCandidateParser.candidates(in: "Issued 2026-11-27, paid 3 Dec 2026, ref 15.01.2027", language: .english)
            let evidence = Evidence(text: "x", dateCandidates: candidates,
                                    captureDate: Bool.random(using: &g) ? DateValue(year: 2026, month: 1, day: 2, hour: 3, minute: 4) : nil,
                                    dateAdded: Bool.random(using: &g) ? Self.d(2025, 6, 7) : nil,
                                    creationDate: Self.d(2024, 8, 9))
            var style = Presets.clean
            style.dateOrder = DateSource.allCases.shuffled(using: &g)
            let generated = GeneratedFields(kind: .other, source: nil, subject: "x", dateChoice: Int.random(in: -2...5, using: &g))
            let validated = ProposalValidator.validate(generated, evidence: evidence, style: style, app: nil, original: nil, path: .model)
            let allowed = candidates.map(\.value) + [evidence.captureDate, evidence.dateAdded, evidence.creationDate].compactMap { $0 }
            if let date = validated.fields.date {
                #expect(allowed.contains(date))
                #expect(validated.evidence.contains { $0.token == .date })
            }
        }
    }
}

struct ValidatorTests {
    /// G2: every source traces to evidence.
    @Test func sourcesNeedEvidence() {
        let evidence = Evidence(text: "Swisscom (Schweiz) AG\nRechnung November", downloadDomain: "www.sunrise.ch", appName: nil)
        func source(_ value: String, app: String? = nil) -> String? {
            ProposalValidator.validate(GeneratedFields(kind: .other, source: value, subject: "x", dateChoice: nil),
                                       evidence: evidence, style: Presets.clean, app: app, original: nil, path: .model).fields.source
        }
        #expect(source("Swisscom") == "Swisscom")
        #expect(source("swisscom") == "swisscom")
        #expect(source("Sunrise") == "Sunrise")
        #expect(source("Safari", app: "Safari") == "Safari")
        #expect(source("Salt") == nil)
        #expect(source("Swisscom Schweiz") == "Swisscom Schweiz")
        #expect(source("Schweizerische Post") == nil)
        let accented = Evidence(text: "Société Générale relevé")
        #expect(ProposalValidator.sourceEvidence("Societe Generale", evidence: accented, app: nil) != nil)
        #expect(ProposalValidator.sourceEvidence("Générale Société", evidence: accented, app: nil) == nil)
    }

    @Test func randomSourcesAreKeptOnlyWithEvidence() {
        var g = SeededGenerator(seed: 0x4732)
        let words = ["Swisscom", "Migros", "Coop", "Galaxus", "Amazon", "Apple", "Lufthansa", "Helvetia"]
        for _ in 0..<5_000 {
            let present = Array(words.shuffled(using: &g).prefix(3))
            let evidence = Evidence(text: present.joined(separator: " and "), downloadDomain: "example.com")
            let candidate = words.randomElement(using: &g)!
            let validated = ProposalValidator.validate(GeneratedFields(kind: .other, source: candidate, subject: "x", dateChoice: nil),
                                                       evidence: evidence, style: Presets.clean, app: nil, original: nil, path: .model)
            #expect((validated.fields.source != nil) == present.contains(candidate))
        }
    }

    @Test func confidenceRules() {
        let fields = PresetTests.referenceFields
        let good = NameFormatter.format(fields, style: Presets.clean, context: PresetTests.context)
        let rich = Evidence(text: String(repeating: "Swisscom invoice ", count: 3))
        #expect(ProposalValidator.confidence(formatted: good, evidence: rich, guardrailOrRefusal: false, currentName: "x.pdf").0 == .high)
        #expect(ProposalValidator.confidence(formatted: good, evidence: Evidence(text: "short"), guardrailOrRefusal: false, currentName: "x.pdf").1 == [.littleContent])
        #expect(ProposalValidator.confidence(formatted: good, evidence: Evidence(text: "", topLabelConfidence: 0.8), guardrailOrRefusal: false, currentName: "x.pdf").0 == .high)
        #expect(ProposalValidator.confidence(formatted: good, evidence: rich, guardrailOrRefusal: true, currentName: "x.pdf").1 == [.guardrailOrRefusal])
        #expect(ProposalValidator.confidence(formatted: good, evidence: rich, guardrailOrRefusal: false, currentName: good.fileName).1 == [.nameUnchanged])
        var metadataOnly = rich
        metadataOnly.metadataOnly = true
        #expect(ProposalValidator.confidence(formatted: good, evidence: metadataOnly, guardrailOrRefusal: false, currentName: "x").0 == .low)

        var piiFields = fields
        piiFields.subject = "4111 1111 1111 1111 john@example.com november"
        let guarded = NameFormatter.format(piiFields, style: Presets.clean, context: PresetTests.context)
        #expect(ProposalValidator.confidence(formatted: guarded, evidence: rich, guardrailOrRefusal: false, currentName: "x").1.contains(.guardsRemovedMostOfSubject))

        var other = fields
        other.kind = .other
        var style = Presets.clean
        style.template = [.date(required: true), .kind(), .subject(required: true)]
        let optionalKind = NameFormatter.format(other, style: style, context: PresetTests.context)
        #expect(ProposalValidator.confidence(formatted: optionalKind, evidence: rich, guardrailOrRefusal: false, currentName: "x").0 == .high,
                "Other only counts when Kind is required")
        style.template = [.date(required: true), .kind(required: true), .subject(required: true)]
        let requiredKind = NameFormatter.format(other, style: style, context: PresetTests.context)
        #expect(ProposalValidator.confidence(formatted: requiredKind, evidence: rich, guardrailOrRefusal: false, currentName: "x").1 == [.missingRequiredToken])
    }
}

struct EligibilityTests {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)
    static let folder = FolderPolicy(mode: .review, watchStart: start)
    static func facts(_ name: String = "Screenshot 2026-11-27 at 14.05.12.png") -> FileFacts {
        FileFacts(name: name, dateAdded: start.addingTimeInterval(60), size: 1_000)
    }

    /// D4: every exclusion in 3.6 has a fixture, and all of them are skipped.
    @Test func everyExclusionIsSkipped() {
        var cases: [(FileFacts, FolderPolicy, Bool, SkipReason)] = []
        func add(_ modify: (inout FileFacts) -> Void, folder: FolderPolicy = Self.folder, paused: Bool = false, _ reason: SkipReason) {
            var f = Self.facts()
            modify(&f)
            cases.append((f, folder, paused, reason))
        }
        add({ $0.isTopLevel = false }, .notTopLevel)
        add({ _ in }, folder: FolderPolicy(mode: .off, watchStart: Self.start), .folderOff)
        add({ _ in }, paused: true, .paused)
        add({ $0.isRegularFile = false }, .notRegularFile)
        add({ $0.isDirectory = true; $0.isRegularFile = false }, .directory)
        add({ $0.isPackage = true }, .package)
        add({ $0.isSymlink = true }, .symlink)
        add({ $0.isAlias = true }, .alias)
        add({ $0.isHidden = true }, .hidden)
        add({ $0.name = ".DS_Store" }, .systemFile)
        add({ $0.name = ".localized" }, .systemFile)
        add({ $0.name = "Icon\r" }, .systemFile)
        for suffix in ["download", "crdownload", "part", "partial", "opdownload", "tmp"] {
            add({ $0.name = "IMG_1234.jpg.\(suffix)" }, .inProgress)
        }
        add({ $0.name = ".IMG_1234.jpg" }, .hidden)
        add({ $0.name = "IMG_1234.mov" }, .disallowedType)
        add({ $0.name = "archive.zip" }, .disallowedType)
        add({ $0.dateAdded = Self.start.addingTimeInterval(-1) }, .beforeWatchStart)
        add({ $0.dateAdded = nil }, .beforeWatchStart)
        add({ $0.hasMarker = true }, .hasMarker)
        add({ $0.seenInHistory = true }, .seenBefore)
        add({ $0.onIgnoreList = true }, .ignored)
        add({ $0.isLocked = true }, .locked)
        add({ $0.parentWritable = false }, .notWritable)
        add({ $0.isDataless = true }, .dataless)
        add({ $0.name = "Tax return 2025.pdf" }, .notGeneric)
        for (facts, folder, paused, reason) in cases {
            #expect(Eligibility.evaluate(facts, folder: folder, request: .automatic, paused: paused) == .skip(reason), "\(facts.name) \(reason)")
        }
        let reasons = Set(cases.map { $0.3 })
        #expect(reasons == Set(SkipReason.allCases))
    }

    @Test func eligibleFilesAndAllowedTypes() {
        for ext in Eligibility.allowedExtensions {
            #expect(Eligibility.evaluate(Self.facts("IMG_0001.\(ext)"), folder: Self.folder, request: .automatic, paused: false) == .process, "\(ext)")
            #expect(Eligibility.evaluate(Self.facts("IMG_0001.\(ext.uppercased())"), folder: Self.folder, request: .automatic, paused: false) == .process)
        }
        var noGenericCheck = Self.folder
        noGenericCheck.onlyGenericNames = false
        #expect(Eligibility.evaluate(Self.facts("Tax return 2025.pdf"), folder: noGenericCheck, request: .automatic, paused: false) == .process)
    }

    @Test func explicitRequestsKeepSafetyButSkipArrivalConditions() {
        var f = Self.facts("Tax return 2025.pdf")
        f.dateAdded = nil
        f.hasMarker = true
        f.isTopLevel = false
        #expect(Eligibility.evaluate(f, folder: nil, request: .explicit, paused: true) == .process)
        f.isSymlink = true
        #expect(Eligibility.evaluate(f, folder: nil, request: .explicit, paused: false) == .skip(.symlink))
        var dataless = Self.facts()
        dataless.isDataless = true
        #expect(Eligibility.evaluate(dataless, folder: nil, request: .explicit, paused: false) == .metadataOnly(.dataless))
        #expect(Eligibility.evaluate(Self.facts("movie.mov"), folder: nil, request: .explicit, paused: false) == .metadataOnly(.disallowedType))
        var huge = Self.facts()
        huge.size = Defaults.contentReadingSizeLimit + 1
        #expect(Eligibility.evaluate(huge, folder: nil, request: .explicit, paused: false) == .metadataOnly(.tooLarge))
        var locked = Self.facts()
        locked.isLocked = true
        #expect(Eligibility.evaluate(locked, folder: nil, request: .explicit, paused: false) == .skip(.locked))
    }
}

struct RuleEngineTests {
    static func facts(kind: KindRef = .builtIn(.invoice), source: String? = "Swisscom AG", domain: String? = "www.swisscom.ch",
                      screenshot: Bool = false, app: String? = nil, name: String = "IMG_1.PDF") -> RuleFacts {
        RuleFacts(kind: kind, source: source, downloadDomain: domain, isScreenshot: screenshot, app: app, fileName: name, originalName: name)
    }

    /// K1: first match wins and evaluation is deterministic.
    @Test func firstMatchingEnabledRuleWins() {
        let rules = [
            Rule(id: "1", name: "Disabled", enabled: false, conditions: [.kindIs(.builtIn(.invoice))], destinationID: "d0"),
            Rule(id: "2", name: "Receipts", conditions: [.kindIs(.builtIn(.receipt))], destinationID: "d1"),
            Rule(id: "3", name: "Swisscom invoices", conditions: [.kindIs(.builtIn(.invoice)), .sourceContains("swisscom")], destinationID: "d2"),
            Rule(id: "4", name: "All invoices", conditions: [.kindIs(.builtIn(.invoice))], destinationID: "d3"),
        ]
        #expect(RuleEngine.firstMatch(rules, facts: Self.facts())?.id == "3")
        #expect(RuleEngine.firstMatch(rules, facts: Self.facts(source: "Sunrise"))?.id == "4")
        #expect(RuleEngine.firstMatch(rules, facts: Self.facts(kind: .other)) == nil)
        for _ in 0..<100 { #expect(RuleEngine.firstMatch(rules, facts: Self.facts())?.id == "3") }
    }

    @Test func everyConditionType() {
        func matches(_ condition: RuleCondition, _ facts: RuleFacts) -> Bool {
            RuleEngine.matches(Rule(id: "r", name: "r", conditions: [condition], destinationID: "d"), facts: facts)
        }
        #expect(matches(.downloadDomainIs("swisscom.ch"), Self.facts()))
        #expect(!matches(.downloadDomainIs("ch"), Self.facts()))
        #expect(matches(.downloadDomainEndsWith("ch"), Self.facts()))
        #expect(!matches(.downloadDomainEndsWith("com.ch"), Self.facts()))
        #expect(matches(.isScreenshot(true), Self.facts(screenshot: true)))
        #expect(matches(.appIs("safari"), Self.facts(app: "Safari")))
        #expect(matches(.fileTypeIs("pdf"), Self.facts()))
        #expect(matches(.fileTypeIs(".jpeg"), Self.facts(name: "a.JPG")))
        #expect(matches(.originalNameContains("img"), Self.facts()))
        #expect(matches(.sourceContains("SWISSCOM"), Self.facts()))
        let any = Rule(id: "a", name: "a", match: .any, conditions: [.kindIs(.builtIn(.receipt)), .fileTypeIs("pdf")], destinationID: "d")
        #expect(RuleEngine.matches(any, facts: Self.facts()))
        #expect(!RuleEngine.matches(Rule(id: "e", name: "e", conditions: [], destinationID: "d"), facts: Self.facts()))
    }

    /// K3: subfolder patterns can't escape the destination.
    @Test func subfolderPatterns() {
        let fields = NameFields(kind: .builtIn(.invoice), source: "../../etc", date: DateValue(year: 2026, month: 3, day: 4))
        #expect(SubfolderPattern.components("{year}/{month}", fields: fields, language: .english, customKinds: []) == ["2026", "03"])
        #expect(SubfolderPattern.components("{source}", fields: fields, language: .english, customKinds: []) == ["etc"])
        #expect(SubfolderPattern.components("/../{kind}/./", fields: fields, language: .german, customKinds: []) == ["Rechnung"])
        let absolute = NameFields(kind: .other, source: "/Applications", date: nil)
        #expect(SubfolderPattern.components("{source}/{year}", fields: absolute, language: .english, customKinds: []) == ["Applications"])
    }
}

struct StyleAndTypedNameTests {
    /// H7: invalid combinations and vocabulary loops can't be saved, and the UI explains why.
    @Test func invalidStylesAreRefusedWithReasons() {
        var style = Presets.clean
        style.wordSeparator = .none
        #expect(StyleValidator.issues(style) == [.noSeparatorRequiresCamelOrPascal])
        style = Presets.clean
        style.vocabulary = [VocabularyRule(from: "Bill", to: "Invoice"), VocabularyRule(from: "invoice", to: "bill")]
        #expect(StyleValidator.issues(style).contains { if case .vocabularyLoop = $0 { true } else { false } })
        style.vocabulary = [VocabularyRule(from: "a", to: "b"), VocabularyRule(from: "b", to: "c"), VocabularyRule(from: "c", to: "a")]
        #expect(!StyleValidator.isValid(style))
        style = Presets.clean
        style.maxLength = 19
        style.subjectWords = 13
        #expect(StyleValidator.issues(style) == [.maxLengthOutOfRange(19), .subjectWordsOutOfRange(13)])
        style = Presets.clean
        style.dateFormat = .yearMonth
        style.timeFormat = .dotted
        #expect(StyleValidator.issues(style) == [.timeNeedsDay])
        style = Presets.clean
        style.dateFormat = .dayMonthNameYear
        style.neverInclude = ["Nov"]
        #expect(StyleValidator.issues(style) == [.neverIncludeRemovesMonthName("Nov")])
        style = Presets.clean
        style.template = [.date(), .date()]
        #expect(StyleValidator.issues(style).contains(.noNamingToken(screenshot: false)))
        style = Presets.clean
        style.characters.asciiOnly = true
        style.partSeparator = .spacedEnDash
        #expect(StyleValidator.issues(style) == [.asciiOnlyWithEnDash])
        for issue in StyleValidator.issues(style) { #expect(!issue.description.isEmpty) }
    }

    @Test func camelAndPascalForceNoWordSeparator() {
        var style = Presets.clean
        style.caseMode = .camel
        #expect(StyleValidator.normalized(style).wordSeparator == .none)
        #expect(style.effectiveWordSeparator == "")
        style.caseMode = .title
        style.wordSeparator = .none
        #expect(StyleValidator.normalized(style).wordSeparator == .space)
    }

    /// H9: typed names are never restyled, and any sanitizer change is shown before saving.
    @Test func typedNamesAreOnlySanitized() throws {
        let plain = try TypedName.prepare("my FAVOURITE photo_of the BEACH", fileExtension: "JPG")
        #expect(plain.fileName == "my FAVOURITE photo_of the BEACH.JPG")
        #expect(!plain.changed && plain.notice == nil)
        let ownExtension = try TypedName.prepare("Report.pdf", fileExtension: "pdf")
        #expect(ownExtension.fileName == "Report.pdf")
        let changed = try TypedName.prepare("Q1/Q2: review\u{202E}", fileExtension: "pdf")
        #expect(changed.fileName == "Q1Q2 review.pdf")
        #expect(changed.changed && changed.notice != nil)
        let long = try TypedName.prepare(String(repeating: "é", count: 300), fileExtension: "pdf")
        #expect(long.fileName.utf8.count <= 255 && long.notice?.contains("255") == true)
        #expect(throws: TypedName.Failure.empty) { try TypedName.prepare("  /:  ", fileExtension: "pdf") }
    }
}

struct PolicyTests {
    static let t0 = Date(timeIntervalSince1970: 1_795_000_000)

    @Test func backoffSchedule() {
        #expect((0..<6).map { RateLimitBackoff.delay(afterAttempt: $0) } == [5, 15, 60, 300, 300, 300])
    }

    @Test func burstStartsAfterTenFilesInThirtySeconds() {
        var guardState = BurstGuard()
        for index in 0..<10 { #expect(guardState.recordArrival(at: Self.t0.addingTimeInterval(Double(index))) == nil) }
        #expect(guardState.recordArrival(at: Self.t0.addingTimeInterval(10)) == 1)
        #expect(guardState.activeGroup(at: Self.t0.addingTimeInterval(11)) == 1)
        #expect(guardState.recordArrival(at: Self.t0.addingTimeInterval(35)) == 1, "arrivals during a burst join it")
        #expect(guardState.activeGroup(at: Self.t0.addingTimeInterval(66)) == nil, "30 s without arrivals ends it")
        var slow = BurstGuard()
        for index in 0..<30 { #expect(slow.recordArrival(at: Self.t0.addingTimeInterval(Double(index) * 4)) == nil) }
    }

    @Test func notificationsBatchAtFourWithinTenSeconds() {
        var batcher = NotificationBatcher()
        #expect(batcher.record(operationID: "a", at: Self.t0) == [.postSingle(operationID: "a")])
        #expect(batcher.record(operationID: "b", at: Self.t0.addingTimeInterval(1)) == [.postSingle(operationID: "b")])
        #expect(batcher.record(operationID: "c", at: Self.t0.addingTimeInterval(2)) == [.postSingle(operationID: "c")])
        #expect(batcher.record(operationID: "d", at: Self.t0.addingTimeInterval(3))
                == [.removeSingles(operationIDs: ["a", "b", "c"]), .postSummary(summaryID: "summary-1", operationIDs: ["a", "b", "c", "d"])])
        #expect(batcher.record(operationID: "e", at: Self.t0.addingTimeInterval(4)) == [.postSummary(summaryID: "summary-1", operationIDs: ["a", "b", "c", "d", "e"])])
        #expect(batcher.record(operationID: "f", at: Self.t0.addingTimeInterval(30)) == [.postSingle(operationID: "f")])
    }

    @Test func pauseUntilTomorrowResumesAtSix() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Zurich"))
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 22, minute: 15)))
        let resume = try #require(PauseOption.untilTomorrow.resumeDate(from: evening, calendar: calendar))
        #expect(calendar.dateComponents([.day, .hour, .minute], from: resume) == DateComponents(day: 28, hour: 6, minute: 0))
        let night = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 2)))
        #expect(calendar.dateComponents([.day, .hour], from: PauseOption.untilTomorrow.resumeDate(from: night, calendar: calendar)!) == DateComponents(day: 28, hour: 6))
        let state = PauseState.paused(.untilTomorrow, now: evening, calendar: calendar)
        #expect(state.isPaused(at: evening.addingTimeInterval(3_600)))
        #expect(!state.isPaused(at: resume))
        #expect(PauseState.paused(.indefinitely, now: evening, calendar: calendar).isPaused(at: evening.addingTimeInterval(1e9)))
        #expect(PauseOption.oneHour.resumeDate(from: evening, calendar: calendar) == evening.addingTimeInterval(3_600))
        // Persisted pauses round-trip.
        let decoded = try JSONDecoder().decode(PauseState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }

    @Test func automaticOfferAppearsOnceAfterThreshold() {
        var offer = AutomaticOfferState()
        for index in 0..<19 { offer.recordAccepted(edited: index < 2) }
        #expect(!offer.shouldOffer(mode: .review))
        offer.recordAccepted(edited: false)
        #expect(offer.shouldOffer(mode: .review))
        #expect(!offer.shouldOffer(mode: .automatic))
        offer.offered = true
        #expect(!offer.shouldOffer(mode: .review))
        var edited = AutomaticOfferState()
        for index in 0..<25 { edited.recordAccepted(edited: index < 3) }
        #expect(!edited.shouldOffer(mode: .review))
    }

    @Test func processingGate() {
        let none = PauseState.none
        #expect(ProcessingGate.holdReason(pause: none, power: PowerConditions(), settings: ProcessingSettings(), now: Self.t0) == nil)
        #expect(ProcessingGate.holdReason(pause: none, power: PowerConditions(lowPowerMode: true), settings: ProcessingSettings(), now: Self.t0) == .lowPowerMode)
        #expect(ProcessingGate.holdReason(pause: none, power: PowerConditions(lowPowerMode: true), settings: ProcessingSettings(pauseInLowPowerMode: false), now: Self.t0) == nil)
        #expect(ProcessingGate.holdReason(pause: none, power: PowerConditions(thermal: .serious), settings: ProcessingSettings(pauseInLowPowerMode: false), now: Self.t0) == .thermal)
        #expect(ProcessingGate.holdReason(pause: none, power: PowerConditions(onBattery: true), settings: ProcessingSettings(), now: Self.t0) == nil)
        #expect(ProcessingGate.holdReason(pause: none, power: PowerConditions(onBattery: true), settings: ProcessingSettings(waitUntilPluggedIn: true), now: Self.t0) == .waitingForPower)
    }

    @Test func retentionCutoff() {
        #expect(Retention.cutoff(now: Self.t0, days: 90) == Self.t0.addingTimeInterval(-90 * 86_400))
        #expect(Retention.cutoff(now: Self.t0, days: nil) == nil)
    }
}
