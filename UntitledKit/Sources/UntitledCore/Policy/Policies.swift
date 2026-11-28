public import Foundation

/// Retry schedule for rate limits and concurrent requests (3.8): 5 s, 15 s, 60 s, then every 5 min.
public enum RateLimitBackoff {
    public static func delay(afterAttempt attempt: Int) -> TimeInterval {
        let schedule = Defaults.rateLimitBackoff
        return attempt < schedule.count ? schedule[max(0, attempt)] : Defaults.rateLimitRepeatInterval
    }
}

/// Burst guard (3.6). When more than 10 eligible files arrive in one folder within 30 s,
/// the burst begins: files still waiting at that moment, and files arriving until 30 s pass
/// without an arrival, go to Review as one group (SPEC Part 5 #37).
public struct BurstGuard: Sendable, Hashable {
    public private(set) var arrivals: [Date] = []
    public private(set) var activeUntil: Date?
    public private(set) var groupNumber = 0

    public init() {}

    /// Records an eligible arrival. Returns the burst group number when a burst is active.
    @discardableResult
    public mutating func recordArrival(at date: Date) -> Int? {
        arrivals.append(date)
        arrivals.removeAll { $0 <= date.addingTimeInterval(-Defaults.burstWindow) }
        if let until = activeUntil, date < until {
            activeUntil = date.addingTimeInterval(Defaults.burstWindow)
            return groupNumber
        }
        if arrivals.count > Defaults.burstThreshold {
            groupNumber += 1
            activeUntil = date.addingTimeInterval(Defaults.burstWindow)
            return groupNumber
        }
        activeUntil = nil
        return nil
    }

    /// The active burst group at a given time, if any.
    public func activeGroup(at date: Date) -> Int? {
        guard let until = activeUntil, date < until else { return nil }
        return groupNumber
    }
}

/// Plans notification grouping (3.15): 4 or more operations within 10 s become one summary
/// with Undo All. In-app actions never reach the planner.
public struct NotificationBatcher: Sendable, Hashable {
    public enum Action: Sendable, Hashable {
        case postSingle(operationID: String)
        case removeSingles(operationIDs: [String])
        case postSummary(summaryID: String, operationIDs: [String])
    }

    private var recent: [(id: String, date: Date)] = []
    private var summaryID: String?
    private var summaryOperations: [String] = []
    private var summaryCounter = 0

    public init() {}

    public static func == (lhs: NotificationBatcher, rhs: NotificationBatcher) -> Bool {
        lhs.summaryID == rhs.summaryID && lhs.summaryOperations == rhs.summaryOperations && lhs.recent.map(\.id) == rhs.recent.map(\.id)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(summaryID)
        hasher.combine(summaryOperations)
    }

    public mutating func record(operationID: String, at date: Date) -> [Action] {
        recent.removeAll { $0.date <= date.addingTimeInterval(-Defaults.notificationBatchWindow) }
        if recent.isEmpty { summaryID = nil; summaryOperations = [] }
        recent.append((operationID, date))
        if let summaryID {
            summaryOperations.append(operationID)
            return [.postSummary(summaryID: summaryID, operationIDs: summaryOperations)]
        }
        if recent.count >= Defaults.notificationBatchThreshold {
            summaryCounter += 1
            let id = "summary-\(summaryCounter)"
            summaryID = id
            let singles = recent.dropLast().map(\.id)
            summaryOperations = recent.map(\.id)
            return [.removeSingles(operationIDs: singles), .postSummary(summaryID: id, operationIDs: summaryOperations)]
        }
        return [.postSingle(operationID: operationID)]
    }
}

/// Pause options in the panel (3.15) and when they end (N4).
public enum PauseOption: String, Codable, Sendable, Hashable, CaseIterable {
    case oneHour, untilTomorrow, indefinitely

    /// When processing resumes, or nil for "indefinitely".
    public func resumeDate(from now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .oneHour:
            return now.addingTimeInterval(3_600)
        case .untilTomorrow:
            return PauseOption.nextResume(after: now, calendar: calendar)
        case .indefinitely:
            return nil
        }
    }

    /// The next 06:00 local time strictly after `now`.
    public static func nextResume(after now: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = Defaults.pauseResumeHour
        components.minute = 0
        components.second = 0
        let today = calendar.date(from: components) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
    }
}

/// A persisted pause.
public struct PauseState: Codable, Sendable, Hashable {
    public var option: PauseOption?
    public var until: Date?

    public init(option: PauseOption? = nil, until: Date? = nil) {
        self.option = option
        self.until = until
    }

    public static let none = PauseState()

    public static func paused(_ option: PauseOption, now: Date, calendar: Calendar) -> PauseState {
        PauseState(option: option, until: option.resumeDate(from: now, calendar: calendar))
    }

    public func isPaused(at now: Date) -> Bool {
        guard let option else { return false }
        if option == .indefinitely { return true }
        guard let until else { return false }
        return now < until
    }
}

/// The one-time offer to switch a folder to Automatic (3.4, O6).
public struct AutomaticOfferState: Codable, Sendable, Hashable {
    public var acceptedCount = 0
    public var editCount = 0
    public var offered = false

    public init() {}

    public mutating func recordAccepted(edited: Bool) {
        acceptedCount += 1
        if edited { editCount += 1 }
    }

    /// True exactly when the offer should be shown now. The caller marks it offered.
    public func shouldOffer(mode: FolderMode) -> Bool {
        mode == .review && !offered && acceptedCount >= Defaults.automaticOfferAccepted && editCount <= Defaults.automaticOfferMaxEdits
    }
}

/// History retention (3.14): 30, 90, 365 days or forever.
public enum Retention {
    /// The cutoff before which finished entries are purged, or nil to keep forever.
    public static func cutoff(now: Date, days: Int?) -> Date? {
        guard let days else { return nil }
        return now.addingTimeInterval(-Double(days) * 86_400)
    }
}

/// Why processing is held right now (3.19). nil means processing runs.
public enum HoldReason: String, Codable, Sendable, Hashable {
    case userPaused, lowPowerMode, thermal, waitingForPower
}

public enum ThermalLevel: Int, Codable, Sendable, Hashable, Comparable {
    case nominal, fair, serious, critical
    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct PowerConditions: Sendable, Hashable {
    public var lowPowerMode: Bool
    public var thermal: ThermalLevel
    public var onBattery: Bool

    public init(lowPowerMode: Bool = false, thermal: ThermalLevel = .nominal, onBattery: Bool = false) {
        self.lowPowerMode = lowPowerMode
        self.thermal = thermal
        self.onBattery = onBattery
    }
}

public struct ProcessingSettings: Codable, Sendable, Hashable {
    public var pauseInLowPowerMode = true
    public var waitUntilPluggedIn = false

    public init(pauseInLowPowerMode: Bool = true, waitUntilPluggedIn: Bool = false) {
        self.pauseInLowPowerMode = pauseInLowPowerMode
        self.waitUntilPluggedIn = waitUntilPluggedIn
    }
}

public enum ProcessingGate {
    /// Serious or critical thermal state always holds; Low Power Mode holds by default;
    /// "Wait until plugged in" holds on battery (3.19, V2, V3).
    public static func holdReason(pause: PauseState, power: PowerConditions, settings: ProcessingSettings, now: Date) -> HoldReason? {
        if pause.isPaused(at: now) { return .userPaused }
        if power.thermal >= .serious { return .thermal }
        if power.lowPowerMode, settings.pauseInLowPowerMode { return .lowPowerMode }
        if power.onBattery, settings.waitUntilPluggedIn { return .waitingForPower }
        return nil
    }
}
