public import Foundation
public import UntitledModel

/// Apple Intelligence states in onboarding step 2 and Settings (B2).
public struct AppleIntelligencePane: Sendable, Hashable {
    public var availability: ModelAvailability

    public init(_ availability: ModelAvailability) { self.availability = availability }

    public var title: String {
        switch availability {
        case .available: "Apple Intelligence is ready"
        case .appleIntelligenceNotEnabled: "Apple Intelligence is turned off"
        case .deviceNotEligible: "This Mac doesn't support Apple Intelligence"
        case .modelNotReady: "Apple Intelligence is getting ready"
        case .basicOnly: "Using Basic naming only"
        }
    }

    public var symbol: String {
        switch availability {
        case .available: "checkmark.circle"
        case .appleIntelligenceNotEnabled: "power.circle"
        case .deviceNotEligible: "xmark.circle"
        case .modelNotReady: "arrow.down.circle"
        case .basicOnly: "text.magnifyingglass"
        }
    }

    public var explanation: String { availability.explanation }

    /// The button that opens System Settings, when there is something to change there.
    public var settingsButtonTitle: String? {
        switch availability {
        case .appleIntelligenceNotEnabled: "Open Apple Intelligence Settings"
        case .modelNotReady: "Check Download in Settings"
        case .available, .deviceNotEligible, .basicOnly: nil
        }
    }

    /// The Apple Intelligence & Siri pane of System Settings.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!
}
