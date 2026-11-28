#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledCore
import UntitledEngine
import UntitledStore

/// The inspector (3.15): a preview, editable fields that re-format the name instantly, the final
/// name, evidence for every part, and the destination (M2).
struct ReviewInspector: View {
    var item: QueueItem?
    var editRequest: Int
    @Environment(AppModel.self) private var model
    @State private var source = ""
    @State private var subject = ""
    @State private var dateText = ""
    @State private var typedName = ""
    @State private var typedNotice: String?
    @State private var dateInvalid = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        if let item, let proposal = item.proposal {
            Form {
                Section {
                    ThumbnailView(path: item.path, size: Metrics.inspectorPreview)
                        .frame(maxWidth: .infinity)
                }
                Section("Name") {
                    TextField("Final name", text: $typedName)
                        .focused($nameFocused)
                        .onSubmit { accept(item) }
                        .accessibilityLabel("Final name")
                    if let typedNotice {
                        Label(typedNotice, systemImage: "info.circle").appText(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("Was") { FileNameText(name: item.expected.name, style: .secondary) }
                }
                Section("Fields") {
                    Picker("Kind", selection: Binding(get: { proposal.fields.kind }, set: { kind in update(item) { $0.kind = kind } })) {
                        ForEach(FieldEditing.kindOptions(customKinds: model.customKinds)) { option in
                            Text(option.label).tag(option.kind)
                        }
                    }
                    TextField("Source", text: $source)
                        .onSubmit { update(item) { $0.source = source.isEmpty ? nil : source } }
                    TextField("Subject", text: $subject)
                        .onSubmit { update(item) { $0.subject = subject } }
                    TextField("Date", text: $dateText, prompt: Text("2026-11-27"))
                        .monospacedDigit()
                        .onSubmit { commitDate(item) }
                    if dateInvalid {
                        Label("Type a date like 2026-11-27.", systemImage: "exclamationmark.circle").appText(.caption)
                    }
                }
                Section("Why This Name?") {
                    WhyThisNameList(proposal: proposal)
                }
                if let destination = model.destinationName(proposal.destinationID) {
                    Section("Destination") {
                        Label(([destination] + proposal.subfolder).joined(separator: " › "), systemImage: "folder")
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: item.id, initial: true) { load(item) }
            .onChange(of: proposal.fileName) { typedName = FileNameParts.base(proposal.fileName) }
            .onChange(of: typedName) { previewTyped(item) }
            .onChange(of: editRequest) { nameFocused = true }
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right",
                                   description: Text("Select a file to see its name and why it was chosen."))
        }
    }

    private func load(_ item: QueueItem) {
        guard let proposal = item.proposal else { return }
        source = proposal.fields.source ?? ""
        subject = proposal.fields.subject
        dateText = FieldEditing.dateText(proposal.fields.date)
        typedName = FileNameParts.base(proposal.fileName)
        typedNotice = nil
        dateInvalid = false
    }

    private func update(_ item: QueueItem, _ change: (inout NameFields) -> Void) {
        guard var fields = item.proposal?.fields else { return }
        change(&fields)
        Task { _ = await model.updateFields(itemID: item.id, fields: fields) }
    }

    private func commitDate(_ item: QueueItem) {
        guard let parsed = FieldEditing.parseDate(dateText) else {
            dateInvalid = true
            return
        }
        dateInvalid = false
        update(item) { fields in
            fields.date = parsed
            fields.dateSource = parsed == nil ? nil : .content
        }
    }

    private func previewTyped(_ item: QueueItem) {
        guard let proposal = item.proposal, typedName != FileNameParts.base(proposal.fileName) else {
            typedNotice = nil
            return
        }
        Task {
            let result = await model.previewTyped(itemID: item.id, name: typedName)
            typedNotice = result.map { $0.changed ? "Will be saved as “\($0.fileName)”." : nil } ?? "Type a name."
        }
    }

    private func accept(_ item: QueueItem) {
        guard let proposal = item.proposal else { return }
        let edited = typedName != FileNameParts.base(proposal.fileName)
        Task { _ = await model.accept([item.id], edits: edited ? [item.id: .typed(typedName)] : [:]) }
    }
}

/// Splits a file name into base and extension with the formatter's rules (3.10).
enum FileNameParts {
    static func base(_ name: String) -> String { FileExtension.split(name).base }
}
#endif
