#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledCore
import UntitledStore

/// Rules (3.15): an ordered list (first match wins), an editor, and the tester (K1).
struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: String?
    @State private var reorderTick = 0

    var body: some View {
        HSplitView {
            List(selection: $selectedID) {
                ForEach(model.rules) { rule in
                    RuleRow(rule: rule).tag(rule.id)
                }
                .onMove { source, destination in
                    var rules = model.rules
                    RuleEditing.move(&rules, from: source, to: destination)
                    reorderTick += 1
                    Task { await model.saveRules(rules) }
                }
            }
            .frame(minWidth: 240, idealWidth: 300, maxWidth: 380)
            .sensoryFeedback(.alignment, trigger: reorderTick)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("New Rule", systemImage: "plus") { Task { await addRule() } }
                        .disabled(model.destinations.isEmpty && model.folders(role: .destination).isEmpty)
                    Button("Delete Rule", systemImage: "minus") { Task { await deleteRule() } }
                        .disabled(selectedID == nil)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .padding(Spacing.s)
            }
            if let rule = model.rules.first(where: { $0.id == selectedID }) {
                RuleEditor(original: rule).id(rule)
            } else {
                ContentUnavailableView("No Rule Selected", systemImage: "arrow.triangle.branch",
                                       description: Text("Rules move renamed files into folders. Files move only when a rule matches."))
            }
        }
        .navigationTitle("Rules")
    }

    private func addRule() async {
        var destination = model.destinations.first
        if destination == nil, let folder = model.folders(role: .destination).first {
            let created = Destination(folderID: folder.id)
            await model.saveDestination(created)
            destination = created
        }
        guard let destination else { return }
        let rule = Rule(id: UUID().uuidString, name: "New Rule", conditions: [.kindIs(.builtIn(.invoice))], destinationID: destination.id)
        await model.saveRules(model.rules + [rule])
        selectedID = rule.id
    }

    private func deleteRule() async {
        guard let id = selectedID else { return }
        await model.saveRules(model.rules.filter { $0.id != id })
        selectedID = nil
    }
}

private struct RuleRow: View {
    var rule: Rule
    @Environment(AppModel.self) private var model
    @State private var warning = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack {
                Text(rule.name).appText(.fileName)
                if warning {
                    Label("Destination missing", systemImage: "exclamationmark.triangle").labelStyle(.iconOnly)
                        .help("The destination folder is missing. Files were renamed in place instead.")
                }
                if !rule.enabled { Text("Off").appText(.caption).foregroundStyle(.secondary) }
            }
            Text(RuleEditing.summary(rule, destination: model.destinationName(rule.destinationID)))
                .appText(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .task(id: rule) { warning = await model.ruleHasWarning(rule.id) }
    }
}

private struct RuleEditor: View {
    var original: Rule
    @Environment(AppModel.self) private var model
    @State private var draft: Rule
    @State private var results: [(name: String, matches: Bool)] = []

    init(original: Rule) {
        self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                Toggle("Enabled", isOn: $draft.enabled)
                Picker("Match", selection: $draft.match) {
                    Text("All conditions").tag(RuleMatchMode.all)
                    Text("Any condition").tag(RuleMatchMode.any)
                }
            }
            Section {
                ForEach(Array(draft.conditions.enumerated()), id: \.offset) { index, condition in
                    ConditionRow(condition: Binding(get: { draft.conditions[index] }, set: { draft.conditions[index] = $0 }),
                                 remove: { draft.conditions.remove(at: index) })
                }
                Menu("Add Condition") {
                    ForEach(RuleEditing.ConditionKind.allCases) { kind in
                        Button(kind.title) { draft.conditions.append(kind.placeholder) }
                    }
                }
            } header: {
                SettingLabel(.ruleConditions)
            }
            Section {
                Picker(selection: $draft.destinationID) {
                    ForEach(model.destinations) { destination in
                        Text(model.folder(id: destination.folderID)?.displayName ?? "Missing folder").tag(destination.id)
                    }
                } label: { SettingLabel(.ruleDestination) }
                TextField(text: $draft.subfolderPattern, prompt: Text("{year}/{source}")) { SettingLabel(.ruleSubfolderPattern) }
            }
            Section("Tester: the Last 50 Files") {
                if results.isEmpty {
                    Text("Files Untitled names appear here, so you can check this rule before saving.")
                        .appText(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                    Label {
                        FileNameText(name: result.name, style: .secondary)
                    } icon: {
                        Image(systemName: result.matches ? "checkmark.circle.fill" : "circle")
                    }
                    .accessibilityLabel("\(result.name), \(result.matches ? "matches" : "doesn't match")")
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            Button("Save") { Task { await save() } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(draft == original)
        }
        .task(id: draft) { results = await model.testRule(draft) }
    }

    private func save() async {
        var rules = model.rules
        guard let index = rules.firstIndex(where: { $0.id == draft.id }) else { return }
        rules[index] = draft
        await model.saveRules(rules)
    }
}

private struct ConditionRow: View {
    @Binding var condition: RuleCondition
    var remove: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Text(RuleEditing.kind(of: condition).title)
            switch condition {
            case .kindIs(let kind):
                Picker("Kind", selection: Binding(get: { kind }, set: { condition = .kindIs($0) })) {
                    ForEach(FieldEditing.kindOptions(customKinds: model.customKinds)) { Text($0.label).tag($0.kind) }
                }
                .labelsHidden()
            case .isScreenshot(let value):
                Picker("Screenshot", selection: Binding(get: { value }, set: { condition = .isScreenshot($0) })) {
                    Text("Yes").tag(true)
                    Text("No").tag(false)
                }
                .labelsHidden()
            default:
                TextField("Value", text: Binding(get: { RuleEditing.text(of: condition) ?? "" },
                                                 set: { condition = RuleEditing.with(text: $0, condition) }))
                    .labelsHidden()
            }
            Button("Remove Condition", systemImage: "minus.circle", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }
}
#endif
