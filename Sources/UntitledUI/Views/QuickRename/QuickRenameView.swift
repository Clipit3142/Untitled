#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledCore

/// The Quick Rename panel's content (3.15). It sits on the panel's glass; controls use standard
/// styles, with the prominent style only for Rename (3.16).
struct QuickRenameView: View {
    @Bindable var quick: QuickRenameModel
    var close: () -> Void
    @FocusState private var focusedPath: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(quick.paths.count == 1 ? "Rename with Untitled" : "Rename \(quick.paths.count) Files with Untitled")
                .appText(.headline)
                .accessibilityAddTraits(.isHeader)
            content
            footer
        }
        .padding(Spacing.l)
        .frame(width: Metrics.quickRenameWidth)
        .animation(MotionReader(reduceMotion: reduceMotion).animation(Motion.standard), value: quick.phase)
        .task { await quick.load() }
        .onExitCommand(perform: close)
    }

    @ViewBuilder
    private var content: some View {
        switch quick.phase {
        case .loading:
            ForEach(quick.entries) { entry in
                HStack(spacing: Spacing.m) {
                    ThumbnailView(path: entry.path, size: 40)
                    ShimmerPlaceholder()
                }
            }
        case .needsAccess(let folder):
            AccessRequestView(folder: folder) { Task { await quick.requestAccess() } }
        case .failed(let reason):
            Label { Text(verbatim: reason).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.triangle") }
        case .ready, .copyOnly, .finished:
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    ForEach(quick.entries) { entry in
                        QuickRenameEntryView(quick: quick, entry: entry, focusedPath: $focusedPath)
                    }
                }
            }
            .frame(maxHeight: 420)
            .onAppear { focusedPath = quick.entries.first?.path }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", action: close)
                .keyboardShortcut(.cancelAction)
            Spacer()
            if quick.phase == .copyOnly {
                Button("Copy Name") {
                    quick.copyNames()
                    close()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Regenerate") { Task { await quick.regenerate() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(quick.phase != .ready)
                Button("Rename") {
                    Task { if await quick.apply() { close() } }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(quick.phase != .ready)
                .accessibilityIdentifier("quickRenameApply")
            }
        }
    }
}

private struct QuickRenameEntryView: View {
    @Bindable var quick: QuickRenameModel
    var entry: QuickRenameModel.Entry
    var focusedPath: FocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .center, spacing: Spacing.m) {
                ThumbnailView(path: entry.path, size: 40)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xxs) {
                        TextField("Name", text: Binding(get: { entry.baseName }, set: { quick.setBaseName($0, for: entry.path) }))
                            .textFieldStyle(.roundedBorder)
                            .focused(focusedPath, equals: entry.path)
                            .disabled(quick.phase != .ready)
                            .accessibilityLabel("New name for \(entry.currentName)")
                        if let ext = entry.fileExtension {
                            Text(verbatim: "." + ext).foregroundStyle(.secondary).accessibilityLabel("extension \(ext)")
                        }
                    }
                    Text(verbatim: RowText.was(entry.currentName)).appText(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            if let notice = quick.typedNotice(for: entry.path) {
                Label(notice, systemImage: "info.circle").appText(.caption).foregroundStyle(.secondary)
            }
            if let error = entry.error {
                Label(error, systemImage: "exclamationmark.triangle").appText(.caption)
            }
            if let destination = entry.proposal?.destinationName, quick.phase == .ready {
                Toggle("Move to \(destination)", isOn: Binding(get: { entry.moveEnabled }, set: { quick.setMove($0, for: entry.path) }))
                    .toggleStyle(.checkbox)
            }
            if let proposal = entry.proposal?.proposal {
                DisclosureGroup("Why this name?") {
                    WhyThisNameList(proposal: proposal)
                }
            }
        }
    }
}

/// Evidence for every part of a proposal (M2).
struct WhyThisNameList: View {
    var proposal: Proposal

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.xs) {
            ForEach(WhyThisName.rows(for: proposal)) { row in
                GridRow {
                    Text(verbatim: row.label).appText(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        if !row.text.isEmpty { Text(verbatim: row.text).appText(.body) }
                        Text(verbatim: row.explanation).appText(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, Spacing.xs)
    }
}

/// Asks for access to a folder before renaming there (M6).
private struct AccessRequestView: View {
    var folder: String
    var request: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label {
                Text("Untitled needs access to “\((folder as NSString).lastPathComponent)” to rename files there.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "folder.badge.questionmark")
            }
            Button("Choose Folder…", action: request)
                .buttonStyle(.borderedProminent)
        }
        .task { request() }
    }
}
#endif
