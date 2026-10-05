import SwiftUI

struct SettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(NotoSettings.self) private var settings
    @State private var families = FontCatalog.Families()

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section("Editor") {
                Toggle(isOn: $settings.rendersMarkdown) {
                    Text("Render Markdown")
                    Text("Formats as you type.")
                }
                Toggle("Show Formatting Bar", isOn: $settings.showsFormattingBar)
                    .disabled(!settings.rendersMarkdown)
            }

            Section("Fonts") {
                FontFamilyPicker(
                    title: "Text Font", standard: "System", families: families.all,
                    selection: $settings.fonts.textFamily)
                FontFamilyPicker(
                    title: "CJK Font", standard: "Automatic", families: families.cjk,
                    selection: $settings.fonts.cjkFamily)
                FontFamilyPicker(
                    title: "Code Font", standard: "System Mono", families: families.fixedPitch,
                    selection: $settings.fonts.codeFamily)
                Stepper(value: fontSize, in: NoteFontSettings.sizeRange, step: 1) {
                    LabeledContent("Size", value: "\(Int(fontSize.wrappedValue)) pt")
                }
                LabeledContent {
                    Button("Reset to Defaults") { settings.fonts = .standard }
                        .disabled(settings.fonts == .standard)
                } label: {
                    Text("Defaults")
                    Text("The system fonts at the standard size.")
                }
            }

            Section("Storage") {
                LabeledContent {
                    if settings.notesFolder != nil {
                        Button("Use Default", action: core.notesCoordinator.resetNotesFolder)
                    }
                    Button("Choose…", action: core.notesCoordinator.chooseNotesFolder)
                } label: {
                    Text("Notes Folder")
                    Text((core.notesStore.notesDirectory.path as NSString).abbreviatingWithTildeInPath)
                }
            }

            Section("Window") {
                Toggle(isOn: $settings.keepsOnTop) {
                    Text("Keep on Top")
                    Text("Stays above other windows and shows on every Space.")
                }
            }

            Section("App") {
                Toggle(isOn: $settings.showsInDock) {
                    Text("Show in Dock")
                    Text("The menu bar item stays either way.")
                }
            }

            Section("Shortcuts") {
                ForEach(HotKeyCommand.allCases, id: \.self) { command in
                    // Not `LabeledContent`: in a grouped form it swallows the recorder's click.
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(command.title)
                            Text(command.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Theme.Spacing.md)
                        ShortcutRecorder(command: command)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .shortcutRecorderPopoverHost()
        .task { families = await FontCatalog.families() }
    }

    /// An unset size shows as the standard one; the first step makes it explicit.
    private var fontSize: Binding<Double> {
        Binding(
            get: { settings.fonts.size ?? Double(NoteMarkdownTypography.standardBodySize) },
            set: { settings.fonts.size = $0 })
    }
}

/// One family menu. The first row is the system's own choice, stored as nil.
private struct FontFamilyPicker: View {
    let title: String
    let standard: String
    let families: [String]
    @Binding var selection: String?

    var body: some View {
        Picker(title, selection: $selection) {
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
    }
}
