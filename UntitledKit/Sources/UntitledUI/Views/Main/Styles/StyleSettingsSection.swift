#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledCore

/// The style's settings table; every row carries its one-line explanation (O4).
struct StyleSettingsSection: View {
    @Binding var draft: NamingStyle

    var body: some View {
        Section("Settings") {
            Picker(selection: $draft.partSeparator) {
                ForEach(PartSeparator.allCases, id: \.self) { Text(StyleEditing.label($0)).tag($0) }
            } label: { SettingLabel(.partSeparator) }
            Picker(selection: $draft.wordSeparator) {
                ForEach(WordSeparator.allCases, id: \.self) { Text(StyleEditing.label($0)).tag($0) }
            } label: { SettingLabel(.wordSeparator) }
            .disabled(draft.caseMode.forcesNoWordSeparator)
            Picker(selection: $draft.caseMode) {
                ForEach(CaseMode.allCases, id: \.self) { Text(StyleEditing.label($0)).tag($0) }
            } label: { SettingLabel(.caseMode) }
            Picker(selection: $draft.dateFormat) {
                ForEach(DateFormat.allCases, id: \.self) { Text(StyleEditing.label($0)).monospacedDigit().tag($0) }
            } label: { SettingLabel(.dateFormat) }
            Picker(selection: $draft.timeFormat) {
                ForEach(TimeFormat.allCases, id: \.self) { Text(StyleEditing.label($0)).tag($0) }
            } label: { SettingLabel(.timeFormat) }
            LabeledContent {
                Text(draft.dateOrder.map(StyleEditing.label).joined(separator: " › ")).appText(.caption)
            } label: { SettingLabel(.dateOrder) }
            Stepper(value: $draft.maxLength, in: Defaults.maxNameLengthRange) {
                LabeledContent { Text("\(draft.maxLength)").monospacedDigit() } label: { SettingLabel(.maxLength) }
            }
            Stepper(value: $draft.subjectWords, in: Defaults.subjectWordsRange) {
                LabeledContent { Text("\(draft.subjectWords)").monospacedDigit() } label: { SettingLabel(.subjectWords) }
            }
            Picker(selection: $draft.nameLanguage) {
                Text("Same as content").tag(NameLanguage?.none)
                ForEach(NameLanguage.allCases, id: \.self) { Text($0.displayName).tag(NameLanguage?.some($0)) }
            } label: { SettingLabel(.nameLanguage) }
            Toggle(isOn: $draft.characters.removeAccents) { SettingLabel(.removeAccents) }
            Toggle(isOn: $draft.characters.asciiOnly) { SettingLabel(.asciiOnly) }
            Toggle(isOn: $draft.characters.windowsSafe) { SettingLabel(.windowsSafe) }
            Toggle(isOn: $draft.characters.allowEmoji) { SettingLabel(.allowEmoji) }
            Picker(selection: $draft.extensionCase) {
                Text("Keep as is").tag(ExtensionCase.keep)
                Text("Lowercase").tag(ExtensionCase.lowercase)
            } label: { SettingLabel(.extensionCase) }
            Toggle(isOn: $draft.removeFillerWords) { SettingLabel(.removeFillerWords) }
            ListField(key: .protectedWords, values: $draft.protectedWords)
            ListField(key: .neverInclude, values: $draft.neverInclude)
            VocabularyEditor(rules: $draft.vocabulary)
        }
    }
}

/// A comma-separated list setting.
private struct ListField: View {
    var key: SettingKey
    @Binding var values: [String]
    @State private var text = ""

    var body: some View {
        LabeledContent {
            TextField(SettingsCatalog.descriptor(key).title, text: $text, axis: .vertical)
                .labelsHidden()
                .onSubmit { values = StyleEditing.list(text) }
                .onAppear { text = values.joined(separator: ", ") }
        } label: {
            SettingLabel(key)
        }
    }
}

private struct VocabularyEditor: View {
    @Binding var rules: [VocabularyRule]
    @State private var from = ""
    @State private var to = ""

    var body: some View {
        DisclosureGroup {
            ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                HStack {
                    Text(verbatim: "\(rule.from) → \(rule.to)")
                    Spacer()
                    Button("Remove", systemImage: "minus.circle") { rules.remove(at: index) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Replace", text: $from)
                TextField("With", text: $to)
                Button("Add") {
                    rules.append(VocabularyRule(from: from, to: to))
                    from = ""
                    to = ""
                }
                .disabled(from.isEmpty)
            }
        } label: {
            SettingLabel(.vocabulary)
        }
    }
}
#endif
