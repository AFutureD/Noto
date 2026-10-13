import SwiftUI

struct SettingsView: View {
    @Environment(SettingsNavigation.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            switch navigation.pane {
            case .general: GeneralSettingsPane()
            case .editor: EditorSettingsPane()
            case .shortcuts: ShortcutsSettingsPane()
            case .sync: SyncSettingsPane()
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
        @Bindable var updates = core.updates
        SettingsRow("Window") {
            Toggle("Keep on top", isOn: $settings.keepsOnTop)
            SettingsCaption("The note window stays above other windows and shows on every Space.")
        }
        SettingsRow("Dock") {
            Toggle("Show in Dock", isOn: $settings.showsInDock)
            SettingsCaption("The menu bar item stays either way.")
        }
        Divider()
        SettingsRow("Updates") {
            Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
            Button("Check Now", action: updates.checkForUpdates)
                .disabled(!updates.canCheckForUpdates)
            SettingsCaption("Version \(Bundle.main.appVersion)")
        }
        Divider()
        SettingsRow("Notes folder") {
            HStack(spacing: Theme.Spacing.md) {
                Button("Choose…", action: core.notesCoordinator.chooseNotesFolder)
                if settings.notesFolder != nil {
                    Button("Use Default", action: core.notesCoordinator.resetNotesFolder)
                }
            }
            // The folder applies again once sync is off, so it stays visible but cannot change.
            .disabled(settings.syncsWithICloud)
            SettingsCaption(notesFolderCaption)
        }
    }

    /// Finder's name for the iCloud folder, not the container path behind it.
    private var notesFolderCaption: String {
        let folder = core.notesStore.notesDirectory
        if case .available(let documents) = core.cloudNotes.state, documents == folder {
            return "iCloud Drive › Noto"
        }
        return (folder.path as NSString).abbreviatingWithTildeInPath
    }
}

private struct EditorSettingsPane: View {
    @Environment(NotoSettings.self) private var settings
    @State private var families = FontCatalog.Families()

    var body: some View {
        @Bindable var settings = settings
        SettingsRow("Text font") {
            FontFamilyButton(standard: "System", families: families.all, selection: $settings.fonts.textFamily)
        }
        SettingsRow("Heading font") {
            FontFamilyButton(
                standard: "Same as Text", families: families.all, selection: $settings.fonts.headingFamily)
        }
        SettingsRow("CJK font") {
            FontFamilyButton(standard: "Automatic", families: families.cjk, selection: $settings.fonts.cjkFamily)
        }
        SettingsRow("Code font") {
            FontFamilyButton(
                standard: "System Mono", families: families.fixedPitch, selection: $settings.fonts.codeFamily)
        }
        Divider()
        SettingsRow("Text size", alignment: .center) {
            HStack(spacing: Theme.Spacing.lg) {
                Slider(value: fontSize, in: NoteFontSettings.sizeRange)
                    .frame(width: Theme.Size.settingsSlider)
                    .accessibilityLabel("Text size")
                Text("\(Int(fontSize.wrappedValue)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        Divider()
        SettingsRow("Highlight", alignment: .center) {
            HStack(spacing: Theme.Spacing.md) {
                ColorPicker("Highlight colour", selection: highlightColor)
                    .labelsHidden()
                if settings.highlightColor != nil {
                    Button("Use Default") { settings.highlightColor = nil }
                }
            }
        }
        SettingsRow("Accent", alignment: .center) {
            HStack(spacing: Theme.Spacing.md) {
                ColorPicker("Accent colour", selection: accentColor, supportsOpacity: false)
                    .labelsHidden()
                if settings.accentColor != nil {
                    Button("Use Default") { settings.accentColor = nil }
                }
            }
        }
        Divider()
        SettingsRow("Formatting bar") {
            Toggle("Show formatting bar", isOn: $settings.showsFormattingBar)
        }
        SettingsRow("") {
            Button("Restore Editor Defaults", action: restoreDefaults)
                .disabled(isAtDefaults)
        }
        .task { families = await FontCatalog.families() }
    }

    private var isAtDefaults: Bool {
        settings.fonts == .standard && settings.highlightColor == nil && settings.accentColor == nil
            && settings.showsFormattingBar
    }

    private func restoreDefaults() {
        settings.fonts = .standard
        settings.highlightColor = nil
        settings.accentColor = nil
        settings.showsFormattingBar = true
    }

    /// An unset colour shows the theme's own; the first pick makes it explicit and fixed.
    private var highlightColor: Binding<Color> {
        Binding(
            get: {
                guard let chosen = settings.highlightColor else { return Theme.Colors.highlight }
                return Color(
                    .sRGB, red: chosen.red, green: chosen.green, blue: chosen.blue, opacity: chosen.alpha)
            },
            set: {
                guard let srgb = NSColor($0).usingColorSpace(.sRGB) else { return }
                settings.highlightColor = NoteHighlightColor(
                    red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent,
                    alpha: srgb.alphaComponent)
            })
    }

    /// An unset colour shows the macOS accent; the first pick makes it explicit and fixed.
    private var accentColor: Binding<Color> {
        Binding(
            get: {
                guard let chosen = settings.accentColor else { return Color(nsColor: .controlAccentColor) }
                return Color(.sRGB, red: chosen.red, green: chosen.green, blue: chosen.blue)
            },
            set: {
                guard let srgb = NSColor($0).usingColorSpace(.sRGB) else { return }
                settings.accentColor = NoteAccentColor(
                    red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
            })
    }

    /// An unset size shows as the standard one; the first move of the slider makes it explicit.
    private var fontSize: Binding<Double> {
        Binding(
            get: { settings.fonts.size ?? Double(NoteEditorTheme.standardBodySize) },
            // Whole points, rounded here rather than by a slider step, which would draw tick marks.
            set: { settings.fonts.size = $0.rounded() })
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

private struct SyncSettingsPane: View {
    @Environment(AppCore.self) private var core
    @Environment(NotoSettings.self) private var settings

    var body: some View {
        SettingsRow("") {
            Toggle("iCloud Sync", isOn: syncsWithICloud)
            SettingsCaption(caption)
        }
    }

    /// Off goes through the coordinator too: only the Mac that turns sync on is asked about its notes.
    private var syncsWithICloud: Binding<Bool> {
        Binding(
            get: { settings.syncsWithICloud },
            set: { core.notesCoordinator.setSyncsWithICloud($0) })
    }

    private var caption: String {
        guard settings.syncsWithICloud, core.cloudNotes.state == .unavailable else {
            return "Turning sync off here turns it off on your other devices too."
        }
        return "iCloud Drive is off on this Mac, so notes stay on this Mac."
    }
}

// MARK: - Parts

/// One line of a pane: a right-aligned label with a colon, then its controls stacked beside it.
private struct SettingsRow<Content: View>: View {
    let label: String
    /// A row of text controls aligns on the baseline; a row of a slider or a colour well on the centre.
    let alignment: VerticalAlignment
    @ViewBuilder let content: Content

    init(_ label: String, alignment: VerticalAlignment = .firstTextBaseline, @ViewBuilder content: () -> Content) {
        self.label = label
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: Theme.Spacing.md) {
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

/// An Aa button that opens a searchable list of families, then the chosen family's name drawn in it.
/// The list's first row is the system's own choice, stored as nil.
private struct FontFamilyButton: View {
    let standard: String
    let families: [String]
    @Binding var selection: String?
    @State private var isPresented = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button("Aa") { isPresented.toggle() }
                .accessibilityLabel("Choose a font")
                .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                    FontFamilyList(standard: standard, families: families, selection: $selection) {
                        isPresented = false
                    }
                }
            Text(name)
                .font(FontFamilyList.sample(selection))
                .lineLimit(1)
        }
    }

    /// A stored family that is not installed says so, rather than drawing in a fallback silently.
    private var name: String {
        guard let selection else { return standard }
        guard families.isEmpty || families.contains(selection) else { return "\(selection) (Not Installed)" }
        return selection
    }
}

private struct FontFamilyList: View {
    let standard: String
    let families: [String]
    @Binding var selection: String?
    let dismiss: () -> Void
    @State private var query = ""

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollViewReader { proxy in
                List {
                    if query.isEmpty { row(nil) }
                    ForEach(matches, id: \.self) { row($0) }
                }
                .listStyle(.plain)
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: Theme.Size.settingsFontList.width, height: Theme.Size.settingsFontList.height)
    }

    static func sample(_ family: String?) -> Font {
        guard let family else { return .system(size: Theme.Size.settingsFontSample) }
        return .custom(family, size: Theme.Size.settingsFontSample)
    }

    private var matches: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return families }
        return families.filter { $0.localizedStandardContains(trimmed) }
    }

    private func row(_ family: String?) -> some View {
        Button {
            selection = family
            dismiss()
        } label: {
            HStack {
                Text(family ?? standard)
                    .font(Self.sample(family))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if family == selection { Image(systemName: "checkmark") }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .id(family)
    }
}
