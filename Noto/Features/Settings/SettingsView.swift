import SwiftUI

struct SettingsView: View {
    @Environment(SettingsNavigation.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            switch navigation.pane {
            case .general: GeneralSettingsPane()
            case .editor: EditorSettingsPane()
            case .shortcuts: ShortcutsSettingsPane()
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.settingsWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .shortcutRecorderPopoverHost()
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { navigation.onContentHeight($0) }
        // Pinned to the top: a centred pane would slide while the window changes height.
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Panes

private struct GeneralSettingsPane: View {
    @Environment(AppCore.self) private var core
    @Environment(NotoSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsRow("Window") {
            Toggle("Keep on top", isOn: $settings.keepsOnTop)
            SettingsCaption("The note window stays above other windows and shows on every Space.")
        }
        SettingsRow("Dock") {
            Toggle("Show in Dock", isOn: $settings.showsInDock)
            SettingsCaption("The menu bar item stays either way.")
        }
        Divider()
        SettingsRow("Notes folder") {
            HStack(spacing: Theme.Spacing.md) {
                Button("Choose…", action: core.notesCoordinator.chooseNotesFolder)
                if settings.notesFolder != nil {
                    Button("Use Default", action: core.notesCoordinator.resetNotesFolder)
                }
            }
            SettingsCaption((core.notesStore.notesDirectory.path as NSString).abbreviatingWithTildeInPath)
        }
    }
}

private struct EditorSettingsPane: View {
    @Environment(NotoSettings.self) private var settings
    @State private var families = FontCatalog.Families()

    var body: some View {
        @Bindable var settings = settings
        SettingsRow("Text size") {
            HStack(spacing: Theme.Spacing.md) {
                Text("A").font(.caption)
                Slider(value: fontSize, in: NoteFontSettings.sizeRange, step: 1)
                    .frame(width: Theme.Size.settingsSlider)
                    .accessibilityLabel("Text size")
                Text("A").font(.title2)
                Text("\(Int(fontSize.wrappedValue)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        Divider()
        SettingsRow("Text font") {
            FontFamilyPicker(standard: "System", families: families.all, selection: $settings.fonts.textFamily)
        }
        SettingsRow("Heading font") {
            FontFamilyPicker(
                standard: "Same as Text", families: families.all, selection: $settings.fonts.headingFamily)
        }
        SettingsRow("CJK font") {
            FontFamilyPicker(standard: "Automatic", families: families.cjk, selection: $settings.fonts.cjkFamily)
        }
        SettingsRow("Code font") {
            FontFamilyPicker(
                standard: "System Mono", families: families.fixedPitch, selection: $settings.fonts.codeFamily)
        }
        SettingsRow("Defaults") {
            Button("Reset Fonts") { settings.fonts = .standard }
                .disabled(settings.fonts == .standard)
        }
        Divider()
        SettingsRow("Markdown") {
            Toggle("Render Markdown", isOn: $settings.rendersMarkdown)
            Toggle("Show formatting bar", isOn: $settings.showsFormattingBar)
                .disabled(!settings.rendersMarkdown)
            SettingsCaption("With rendering off, the editor shows the source as you type it.")
        }
        .task { families = await FontCatalog.families() }
    }

    /// An unset size shows as the standard one; the first move of the slider makes it explicit.
    private var fontSize: Binding<Double> {
        Binding(
            get: { settings.fonts.size ?? Double(NoteMarkdownTypography.standardBodySize) },
            set: { settings.fonts.size = $0 })
    }
}

private struct ShortcutsSettingsPane: View {
    var body: some View {
        ForEach(HotKeyCommand.allCases, id: \.self) { command in
            SettingsRow(command.title) {
                ShortcutRecorder(command: command)
                SettingsCaption(command.subtitle)
            }
        }
        Divider()
        SettingsRow("") {
            SettingsCaption("Click a field and press the keys. Press Delete to remove a shortcut.")
        }
    }
}

// MARK: - Parts

/// One line of a pane: a right-aligned label with a colon, then its controls stacked beside it.
private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(label.isEmpty ? "" : "\(label):")
                .frame(width: Theme.Size.settingsLabelColumn, alignment: .trailing)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) { content }
            Spacer(minLength: 0)
        }
    }
}

private struct SettingsCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One family menu. The first row is the system's own choice, stored as nil.
private struct FontFamilyPicker: View {
    let standard: String
    let families: [String]
    @Binding var selection: String?

    var body: some View {
        Picker(standard, selection: $selection) {
            Text(standard).tag(String?.none)
            Divider()
            // A stored family that is not in the list stays selectable, so the menu shows it.
            if let selection, !families.contains(selection) {
                Text(families.isEmpty ? selection : "\(selection) (Not Installed)")
                    .tag(String?.some(selection))
            }
            ForEach(families, id: \.self) { family in
                Text(family).tag(String?.some(family))
            }
        }
        .labelsHidden()
        // A menu of short names is narrower than the frame, and would sit centred in it.
        .frame(width: Theme.Size.settingsPicker, alignment: .leading)
    }
}
