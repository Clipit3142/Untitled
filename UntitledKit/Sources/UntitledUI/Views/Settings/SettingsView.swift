#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledCore
import UntitledEngine
import UntitledModel

/// Settings (3.15): standard tabs; every setting carries its one-line explanation (O4).
struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = SettingsTab.general.rawValue

    var body: some View {
        TabView(selection: $tab) {
            ForEach(SettingsTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab.rawValue) {
                    content(tab)
                        .formStyle(.grouped)
                        .frame(width: 520)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings()
        case .appleIntelligence: AppleIntelligenceSettings()
        case .notifications: NotificationSettings()
        case .privacy: PrivacySettings()
        case .advanced: AdvancedSettings()
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Toggle(isOn: model.preference(\.launchAtLogin)) { SettingLabel(.launchAtLogin) }
            Toggle(isOn: model.preference(\.showInDock)) { SettingLabel(.showInDock) }
            Toggle(isOn: model.engineSetting(\.processing.pauseInLowPowerMode)) { SettingLabel(.pauseInLowPowerMode) }
            Toggle(isOn: model.preference(\.renameSound)) { SettingLabel(.renameSound) }
        }
    }
}

private struct AppleIntelligenceSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        Form {
            AppleIntelligenceStatusView(pane: AppleIntelligencePane(model.availability))
            Toggle(isOn: model.engineSetting(\.basicNamingOnly)) { SettingLabel(.basicNamingOnly) }
            Picker(selection: model.engineSetting(\.processing.waitUntilPluggedIn)) {
                Text("Process normally").tag(false)
                Text("Wait until plugged in").tag(true)
            } label: {
                SettingLabel(.onBattery)
            }
        }
    }
}

/// The Apple Intelligence status, shared by Settings and onboarding step 2 (B2).
struct AppleIntelligenceStatusView: View {
    var pane: AppleIntelligencePane
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label(pane.title, systemImage: pane.symbol).appText(.headline)
            Text(pane.explanation).appText(.secondary).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let button = pane.settingsButtonTitle {
                Button(button) { router.openURL(AppleIntelligencePane.settingsURL) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appleIntelligenceStatus")
    }
}

private struct NotificationSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        Form {
            Toggle(isOn: model.preference(\.notifyRenamed)) { SettingLabel(.notifyRenamed) }
            Toggle(isOn: model.preference(\.notifyReview)) { SettingLabel(.notifyReview) }
            LabeledContent {
                Button(SettingsCatalog.descriptor(.systemNotificationSettings).title) {
                    router.openURL(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            } label: {
                SettingLabel(.systemNotificationSettings)
            }
        }
    }
}

private struct PrivacySettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirm: SettingKey?

    var body: some View {
        Form {
            Section {
                Text(SettingsCatalog.privacyStatement).fixedSize(horizontal: false, vertical: true)
            }
            Section {
                ForEach([SettingKey.clearHistory, .clearLearnedData, .resetEverything], id: \.self) { key in
                    LabeledContent {
                        Button(SettingsCatalog.descriptor(key).title, role: key == .resetEverything ? .destructive : nil) { confirm = key }
                    } label: {
                        SettingLabel(key)
                    }
                }
            }
        }
        .confirmationDialog(confirm.map { SettingsCatalog.descriptor($0).title.replacingOccurrences(of: "…", with: "?") } ?? "",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { key in
            Button(key == .resetEverything ? "Reset" : "Clear", role: .destructive) {
                Task {
                    switch key {
                    case .clearHistory: await model.clearHistory()
                    case .clearLearnedData: await model.clearLearnedData()
                    default: await model.resetEverything()
                    }
                }
            }
        } message: { key in
            Text(SettingsCatalog.descriptor(key).explanation)
        }
    }
}

private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        Form {
            LabeledContent {
                HStack {
                    Slider(value: model.engineSetting(\.stabilityWait), in: Defaults.stabilityWaitRange, step: 0.5)
                        .frame(width: 180)
                    Text(model.settings.stabilityWait, format: .number.precision(.fractionLength(1))).monospacedDigit()
                    Text("s")
                }
            } label: {
                SettingLabel(.stabilityWait)
            }
            Stepper(value: model.engineSetting(\.pdfPages), in: Defaults.pdfPagesRange) {
                LabeledContent { Text("\(model.settings.pdfPages)").monospacedDigit() } label: { SettingLabel(.pdfPages) }
            }
            Picker(selection: model.engineSetting(\.historyRetentionDays)) {
                Text("30 days").tag(Int?.some(30))
                Text("90 days").tag(Int?.some(90))
                Text("1 year").tag(Int?.some(365))
                Text("Forever").tag(Int?.none)
            } label: {
                SettingLabel(.historyRetention)
            }
            LabeledContent {
                Button(SettingsCatalog.descriptor(.exportDiagnostics).title) {
                    Task { router.exportDiagnostics(await model.diagnosticsReport()) }
                }
            } label: {
                SettingLabel(.exportDiagnostics)
            }
        }
    }
}

extension AppModel {
    /// A binding to an app preference that saves through the model.
    func preference(_ keyPath: WritableKeyPath<AppPreferences, Bool> & Sendable) -> Binding<Bool> {
        Binding(get: { self.preferences[keyPath: keyPath] }, set: { value in
            Task { await self.update { $0[keyPath: keyPath] = value } }
        })
    }

    /// A binding to an engine setting that saves through the model.
    func engineSetting<Value: Sendable>(_ keyPath: WritableKeyPath<EngineSettings, Value> & Sendable) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { value in
            Task { await self.updateSettings { $0[keyPath: keyPath] = value } }
        })
    }
}
#endif
