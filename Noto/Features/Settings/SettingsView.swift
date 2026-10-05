import SwiftUI

struct SettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(NotoSettings.self) private var settings

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
    }
}
