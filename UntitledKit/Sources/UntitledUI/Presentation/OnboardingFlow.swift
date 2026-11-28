public import Foundation

/// Onboarding (3.15): seven steps, resumable (B7). Nothing is watched until it finishes or is skipped.
public struct OnboardingFlow: Codable, Sendable, Hashable {
    public enum Step: Int, Codable, Sendable, Hashable, CaseIterable, Identifiable {
        case welcome = 1, appleIntelligence, folders, style, mode, permissions, demo

        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .welcome: "Welcome to Untitled"
            case .appleIntelligence: "Apple Intelligence"
            case .folders: "Choose Folders"
            case .style: "Choose a Style"
            case .mode: "Review or Automatic"
            case .permissions: "Notifications and Finder"
            case .demo: "Try It"
            }
        }

        public var subtitle: String {
            switch self {
            case .welcome: "Everything stays on this Mac. Untitled has no internet access."
            case .appleIntelligence: "Untitled names files with Apple Intelligence on this Mac, or with Basic naming."
            case .folders: "Untitled watches the top level of these folders for new screenshots and downloads."
            case .style: "Pick how names look. You can change it later, and Untitled can learn from your edits."
            case .mode: "Start by reviewing names, or let Untitled rename new files right away. Undo works either way."
            case .permissions: "Get a notification with Undo after each rename, and rename from Finder's menu."
            case .demo: "Take a screenshot with ⌘⇧3 or ⌘⇧4 and watch it get a name."
            }
        }
    }

    public enum Completion: String, Codable, Sendable, Hashable { case finished, skipped }

    public var step: Step = .welcome
    public var completion: Completion?

    public init(step: Step = .welcome, completion: Completion? = nil) {
        self.step = step
        self.completion = completion
    }

    public var isComplete: Bool { completion != nil }
    /// Watching begins only once onboarding is finished or skipped (B7).
    public var allowsWatching: Bool { isComplete }
    public var canGoBack: Bool { step != .welcome && !isComplete }
    public var progress: Double { Double(step.rawValue) / Double(Step.allCases.count) }

    public mutating func next() {
        guard !isComplete else { return }
        if let following = Step(rawValue: step.rawValue + 1) { step = following } else { completion = .finished }
    }

    public mutating func back() {
        guard canGoBack, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    public mutating func skip() {
        completion = .skipped
    }

    public mutating func finish() {
        completion = .finished
    }
}

/// The live demo's timer (step 7, B6): after 10 s without a screenshot, explain that screenshots
/// may be saved elsewhere and offer to add that folder.
public struct ScreenshotDemo: Sendable, Hashable {
    public static let tipDelay: TimeInterval = 10

    public var started: Date
    public var renamedName: String?

    public init(started: Date) { self.started = started }

    public func showsSavedElsewhereTip(now: Date) -> Bool {
        renamedName == nil && now.timeIntervalSince(started) >= Self.tipDelay
    }

    /// Where screenshots go: the `location` in the screencapture defaults, or Desktop.
    public static func screenshotFolder(location: String?, home: String) -> String {
        guard let location, !location.isEmpty else { return home + "/Desktop" }
        let expanded = location.hasPrefix("~") ? home + location.dropFirst() : location
        return expanded.count > 1 && expanded.hasSuffix("/") ? String(expanded.dropLast()) : expanded
    }
}
