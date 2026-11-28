#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledCore

/// Onboarding (3.15): seven steps, fully usable from the keyboard (Return continues, ⌘[ goes
/// back), resuming where the user left off (B1, B7).
struct OnboardingView: View {
    @Bindable var onboarding: OnboardingModel
    var close: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ProgressView(value: model.onboarding.progress)
                .accessibilityLabel("Step \(onboarding.step.rawValue) of 7")
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(onboarding.step.title).appText(.title).accessibilityAddTraits(.isHeader)
                Text(onboarding.step.subtitle).appText(.secondary).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(onboarding.step)
                .transition(MotionReader(reduceMotion: reduceMotion).transition(.push(from: .trailing)))
            NoticeStack()
            footer
        }
        .padding(Spacing.xxl)
        .frame(width: 600, height: 520)
        .animation(MotionReader(reduceMotion: reduceMotion).animation(Motion.standard), value: onboarding.step)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch onboarding.step {
        case .welcome: WelcomeStep()
        case .appleIntelligence: AppleIntelligenceStatusView(pane: AppleIntelligencePane(model.availability))
        case .folders: FoldersStep(onboarding: onboarding)
        case .style: StyleStep(onboarding: onboarding)
        case .mode: ModeStep(onboarding: onboarding)
        case .permissions: PermissionsStep(onboarding: onboarding)
        case .demo: DemoStep(onboarding: onboarding)
        }
    }

    private var footer: some View {
        HStack {
            if onboarding.step == .welcome {
                Button("Skip Setup") { Task { await onboarding.skip(); close() } }
            } else {
                Button("Back") { Task { await onboarding.back() } }
                    .keyboardShortcut("[", modifiers: .command)
            }
            Spacer()
            if onboarding.step == .demo {
                Button("Done") { Task { await onboarding.finish(); close() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(onboarding.step == .appleIntelligence && model.availability != .available ? "Continue with Basic Naming" : "Continue") {
                    Task { await onboarding.next() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(onboarding.step == .folders && model.watchedFolders.isEmpty)
                .accessibilityIdentifier("onboardingContinue")
            }
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label("New screenshots and downloads get clear names, in your style.", systemImage: "doc.text.magnifyingglass")
            Label("Everything stays on this Mac. Untitled has no internet access.", systemImage: "lock.shield")
            Label("Every rename can be undone.", systemImage: "arrow.uturn.backward.circle")
        }
        .appText(.body)
    }
}

private struct FoldersStep: View {
    var onboarding: OnboardingModel
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            row("Desktop", symbol: "menubar.dock.rectangle", added: onboarding.desktopAdded) { Task { await onboarding.addDesktop() } }
            row("Downloads", symbol: "arrow.down.circle", added: onboarding.downloadsAdded) { Task { await onboarding.addDownloads() } }
            Button("Add Another Folder…") { Task { await onboarding.addOther() } }
            ForEach(model.watchedFolders.filter { !$0.isDownloads && $0.path != onboarding.router.desktopFolder()?.path }) { folder in
                Label(folder.displayName, systemImage: "folder")
            }
        }
    }

    private func row(_ title: String, symbol: String, added: Bool, add: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if added {
                Label("Added", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
            } else {
                Button("Add \(title)", action: add)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct StyleStep: View {
    @Bindable var onboarding: OnboardingModel
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Picker("Style", selection: $onboarding.styleID) {
                ForEach(Presets.all) { preset in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(preset.name)
                        Text(StylePreview.rows(style: preset).first?.fileName ?? "").appText(.caption).foregroundStyle(.secondary)
                    }
                    .tag(preset.id)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Button("Learn from a Folder…") { Task { await learn() } }
            if let message { Text(message).appText(.caption).foregroundStyle(.secondary) }
        }
    }

    private func learn() async {
        guard let choice = await router.chooseFolder(nil, "Learn") else { return }
        do {
            let inferred = try await model.learnStyle(fromFolder: choice.url.path)
            var style = inferred.applied(to: Presets.clean)
            style.id = UUID().uuidString
            style.name = "Learned from \(choice.url.lastPathComponent)"
            if await model.save(style).isEmpty {
                onboarding.styleID = style.id
                message = "Learned a style from \(inferred.sampleCount) names in “\(choice.url.lastPathComponent)”."
            }
        } catch {
            switch error {
            case .tooFewNames(let minimum, let found):
                message = "That folder has \(found) files; Untitled needs at least \(minimum) to learn a style."
            }
        }
    }
}

private struct ModeStep: View {
    @Bindable var onboarding: OnboardingModel

    var body: some View {
        Picker("Mode", selection: $onboarding.mode) {
            VStack(alignment: .leading) {
                Text("Review")
                Text("Untitled proposes names; you accept them in Review.").appText(.caption).foregroundStyle(.secondary)
            }
            .tag(FolderMode.review)
            VStack(alignment: .leading) {
                Text("Automatic")
                Text("Untitled renames new files right away. Low-confidence names still go to Review.").appText(.caption).foregroundStyle(.secondary)
            }
            .tag(FolderMode.automatic)
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
    }
}

private struct PermissionsStep: View {
    var onboarding: OnboardingModel
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack {
                Label("Notifications", systemImage: "bell.badge")
                Spacer()
                switch onboarding.notificationsAllowed {
                case true?: Label("Allowed", systemImage: "checkmark.circle.fill")
                case false?: Text("Not allowed").foregroundStyle(.secondary)
                case nil: Button("Allow Notifications") { Task { await onboarding.requestNotifications() } }
                }
            }
            Toggle(isOn: model.preference(\.launchAtLogin)) { SettingLabel(.launchAtLogin) }
            HStack {
                Label("Finder extension", systemImage: "contextualmenu.and.cursorarrow")
                Spacer()
                if onboarding.finderExtensionEnabled {
                    Label("Enabled", systemImage: "checkmark.circle.fill")
                } else {
                    Button("Enable in System Settings…") { onboarding.router.openFinderExtensionSettings() }
                }
            }
        }
        .task {
            // B8: the status updates within 2 s after the user enables it.
            while !Task.isCancelled {
                onboarding.refreshFinderExtension()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct DemoStep: View {
    var onboarding: OnboardingModel
    @Environment(AppModel.self) private var model
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let renamed = onboarding.demoRenamed {
                Label { FileNameText(name: renamed) } icon: { Image(systemName: "checkmark.circle.fill") }
                Text("That's it. Undo is in the menu bar and in Activity.").appText(.secondary)
            } else {
                Label("Waiting for a screenshot…", systemImage: "camera.viewfinder")
                if onboarding.showsSavedElsewhereTip(now: now) {
                    Text("No screenshot yet. Screenshots may be saved somewhere else: check the Options menu in the Screenshot app (⌘⇧5).")
                        .appText(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Add the Screenshots Folder…") { Task { await onboarding.addOther() } }
                }
            }
        }
        .task {
            while !Task.isCancelled && onboarding.demoRenamed == nil {
                onboarding.checkDemo()
                now = Date()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}
#endif
