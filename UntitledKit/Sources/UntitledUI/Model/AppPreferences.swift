/// Settings the app owns (3.15 Settings). The engine owns the rest.
public struct AppPreferences: Codable, Sendable, Hashable {
    public var launchAtLogin = false
    public var showInDock = false
    public var renameSound = false
    public var notifyRenamed = true
    public var notifyReview = true
    /// Set once the Finder extension has been seen enabled (B8).
    public var finderExtensionEnabled = false

    public init() {}
}

/// Persists app-owned state. The production store writes through the engine into config.sqlite,
/// so Reset clears it with everything else (O5).
public protocol PreferencesStoring: Sendable {
    func loadPreferences() async -> AppPreferences?
    func savePreferences(_ preferences: AppPreferences) async
    func loadOnboarding() async -> OnboardingFlow?
    func saveOnboarding(_ flow: OnboardingFlow) async
}
