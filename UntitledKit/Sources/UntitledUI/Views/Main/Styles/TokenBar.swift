#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import UntitledCore

/// The token bar: chips that drag to reorder, with a haptic tick when they snap (3.16). Every
/// drag action is also in the chip's menu, for the keyboard and VoiceOver (T2).
struct TokenBar: View {
    @Binding var template: [TemplateToken]
    var screenshot: Bool
    @State private var newText = ""

    var body: some View {
        LabeledContent {
            HStack(spacing: Spacing.xs) {
                ForEach(Array(template.enumerated()), id: \.offset) { index, token in
                    chip(token, index: index)
                }
                Menu("Add", systemImage: "plus") {
                    ForEach(StyleEditing.addable(to: template, screenshot: screenshot), id: \.self) { kind in
                        Button(WhyThisName.label(kind)) {
                            template.append(TemplateToken(kind, text: kind == .text ? "Text" : nil))
                        }
                    }
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } label: {
            SettingLabel(screenshot ? .screenshotTemplate : .styleTemplate)
        }
        .sensoryFeedback(.alignment, trigger: template.map(\.kind))
    }

    private func chip(_ token: TemplateToken, index: Int) -> some View {
        Text(StyleEditing.chipTitle(token))
            .appText(.secondary)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .background(token.required ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.quinary), in: .capsule)
            .overlay { Capsule().strokeBorder(.separator) }
            .draggable(String(index))
            .dropDestination(for: String.self) { items, _ in
                guard let source = items.first.flatMap(Int.init) else { return false }
                StyleEditing.move(&template, from: source, to: source < index ? index + 1 : index)
                return true
            }
            .contextMenu {
                Button(token.required ? "Make Optional" : "Make Required") { StyleEditing.toggleRequired(&template, at: index) }
                Button("Move Left") { StyleEditing.move(&template, from: index, to: index - 1) }.disabled(index == 0)
                Button("Move Right") { StyleEditing.move(&template, from: index, to: index + 2) }.disabled(index == template.count - 1)
                Divider()
                Button("Remove", role: .destructive) { StyleEditing.remove(&template, at: index) }
            }
            .accessibilityLabel(StyleEditing.chipTitle(token))
            .accessibilityAction(named: "Move Left") { StyleEditing.move(&template, from: index, to: index - 1) }
            .accessibilityAction(named: "Move Right") { StyleEditing.move(&template, from: index, to: index + 2) }
            .accessibilityAction(named: token.required ? "Make Optional" : "Make Required") { StyleEditing.toggleRequired(&template, at: index) }
    }
}
#endif
