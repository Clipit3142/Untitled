#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledCore
import UntitledEngine

/// Styles (3.15): a token bar with draggable chips, the settings table, a live preview from
/// stored fields (never the model), the examples list and pending suggestions.
struct StylesView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: String?

    var body: some View {
        HSplitView {
            List(model.styles, selection: $selectedID) { style in
                Text(style.name).tag(style.id)
            }
            .frame(minWidth: 160, idealWidth: 180, maxWidth: 240)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("New Style", systemImage: "plus") { Task { await duplicate() } }
                    Button("Delete Style", systemImage: "minus") { Task { await delete() } }
                        .disabled(selectedID.map { id in Presets.all.contains { $0.id == id } } ?? true)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .padding(Spacing.s)
            }
            if let style = model.styles.first(where: { $0.id == selectedID }) {
                StyleEditor(original: style)
                    .id(style.id + "-\(style.version)")
            } else {
                ContentUnavailableView("Select a Style", systemImage: "textformat")
            }
        }
        .navigationTitle("Styles")
        .onAppear { selectedID = selectedID ?? model.styles.first?.id }
    }

    private func duplicate() async {
        var copy = model.style(id: selectedID ?? Presets.clean.id)
        copy.id = UUID().uuidString
        copy.name = copy.name + " Copy"
        copy.version = 1
        if await model.save(copy).isEmpty { selectedID = copy.id }
    }

    private func delete() async {
        guard let id = selectedID else { return }
        await model.deleteStyle(id: id)
        selectedID = model.styles.first?.id
    }
}

private struct StyleEditor: View {
    var original: NamingStyle
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var draft: NamingStyle
    @State private var examples = ExampleList()
    @State private var typedExamples = ""
    @State private var learnMessage: String?

    init(original: NamingStyle) {
        self.original = original
        _draft = State(initialValue: original)
    }

    private var issues: [StyleIssue] { StyleValidator.issues(draft) }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                TokenBar(template: $draft.template, screenshot: false)
                TokenBar(template: $draft.screenshotTemplate, screenshot: true)
            } header: {
                Text("Template")
            } footer: {
                Text(SettingsCatalog.descriptor(.styleTemplate).explanation).appText(.caption).foregroundStyle(.secondary)
            }
            Section("Preview") {
                ForEach(StylePreview.rows(style: draft, samples: model.previewSamples + StylePreview.samples, customKinds: model.customKinds)) { row in
                    Label { FileNameText(name: row.fileName) } icon: { Image(systemName: row.isScreenshot ? "camera.viewfinder" : "doc") }
                }
            }
            StyleSettingsSection(draft: $draft)
            Section("Learn") {
                Button("Learn from a Folder…") { Task { await learnFromFolder() } }
                TextField("Type 3–5 example names, one per line", text: $typedExamples, axis: .vertical)
                    .lineLimit(3...5)
                Button("Learn from Examples") { learnFromExamples() }
                    .disabled(typedExamples.split(separator: "\n").count < 3)
                if let learnMessage { Text(learnMessage).appText(.caption).foregroundStyle(.secondary) }
            }
            Section {
                ForEach(examples.names.reversed(), id: \.self) { name in
                    HStack {
                        FileNameText(name: name)
                        Spacer()
                        Button("Remove Example", systemImage: "minus.circle") {
                            Task {
                                await model.removeExample(name, styleID: draft.id)
                                examples = await model.examples(styleID: draft.id)
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                SettingLabel(.examples)
            }
            let suggestions = model.suggestions.filter { $0.styleID == draft.id }
            if !suggestions.isEmpty {
                Section("Suggestions") {
                    ForEach(suggestions) { SuggestionCard(suggestion: $0) }
                }
            }
            if !issues.isEmpty {
                Section("Can't Save Yet") {
                    ForEach(issues, id: \.self) { issue in
                        Label(issue.description, systemImage: "exclamationmark.circle")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            Button("Revert") { draft = original }
                .disabled(draft == original)
            Button("Save") { Task { await save() } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(draft == original || !issues.isEmpty)
        }
        .task(id: draft.id) { examples = await model.examples(styleID: draft.id) }
    }

    private func save() async {
        var copy = draft
        copy.version = original.version + 1
        _ = await model.save(copy)
    }

    private func learnFromFolder() async {
        guard let choice = await router.chooseFolder(nil, "Learn") else { return }
        do {
            let inferred = try await model.learnStyle(fromFolder: choice.url.path)
            draft = inferred.applied(to: draft)
            draft.version = original.version
            learnMessage = "Learned from \(inferred.sampleCount) names. Review the preview, then Save."
        } catch {
            switch error {
            case .tooFewNames(let minimum, let found):
                learnMessage = "That folder has \(found) files; Untitled needs at least \(minimum) to learn a style."
            }
        }
    }

    private func learnFromExamples() {
        let names = typedExamples.split(separator: "\n").map(String.init)
        do {
            let inferred = try StyleInference.inferFromExamples(names)
            draft = inferred.applied(to: draft)
            draft.version = original.version
            learnMessage = "Learned from \(inferred.sampleCount) examples. Review the preview, then Save."
        } catch {
            switch error {
            case .tooFewNames(let minimum, _): learnMessage = "Type at least \(minimum) example names."
            }
        }
    }
}
#endif
