import Foundation

/// Every preference, mirrored to `UserDefaults` as it changes. See docs/architecture.md.
@MainActor
@Observable
final class NotoSettings {
    private enum Key {
        static let showsFormattingBar = "notesShowsFormattingBar"
        static let notesFolder = "notesFolder"
        static let showsInDock = "showsInDock"
        static let keepsOnTop = "notesKeepsOnTop"
        static let shortcuts = "hotKeys"
        static let textFont = "notesTextFont"
        static let headingFont = "notesHeadingFont"
        static let cjkFont = "notesCJKFont"
        static let codeFont = "notesCodeFont"
        static let fontSize = "notesFontSize"
        static let highlightColor = "notesHighlightColor"
        static let accentColor = "notesAccentColor"
        static let syncsWithICloud = "iCloudSync"
    }

    /// A preference that rides iCloud, named for its property; it travels as the `UserDefaults` keys
    /// that hold it, so one parser reads a local and a remote value alike. See docs/features/sync.md.
    enum Synced: String, CaseIterable, Sendable {
        case syncsWithICloud
        case showsFormattingBar
        case fonts
        case highlightColor
        case accentColor
        case shortcuts

        var keys: [String] {
            switch self {
            case .syncsWithICloud: [Key.syncsWithICloud]
            case .showsFormattingBar: [Key.showsFormattingBar]
            case .fonts: [Key.textFont, Key.headingFont, Key.cjkFont, Key.codeFont, Key.fontSize]
            case .highlightColor: [Key.highlightColor]
            case .accentColor: [Key.accentColor]
            case .shortcuts: [Key.shortcuts]
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after a synced preference is stored, whatever changed it.
    @ObservationIgnored var onSyncedChange: (Synced) -> Void = { _ in }

    var showsFormattingBar: Bool {
        didSet {
            defaults.set(showsFormattingBar, forKey: Key.showsFormattingBar)
            onSyncedChange(.showsFormattingBar)
        }
    }
    /// Nil for the default folder in Application Support, else an absolute or `~/` path.
    var notesFolder: String? {
        didSet { defaults.set(notesFolder, forKey: Key.notesFolder) }
    }
    var showsInDock: Bool {
        didSet { defaults.set(showsInDock, forKey: Key.showsInDock) }
    }
    /// Off, the note window is an ordinary window that other windows can cover.
    var keepsOnTop: Bool {
        didSet { defaults.set(keepsOnTop, forKey: Key.keepsOnTop) }
    }
    var fonts: NoteFontSettings {
        didSet {
            guard fonts != oldValue else { return }
            defaults.set(fonts.textFamily, forKey: Key.textFont)
            defaults.set(fonts.headingFamily, forKey: Key.headingFont)
            defaults.set(fonts.cjkFamily, forKey: Key.cjkFont)
            defaults.set(fonts.codeFamily, forKey: Key.codeFont)
            defaults.set(fonts.size, forKey: Key.fontSize)
            onSyncedChange(.fonts)
        }
    }
    /// Nil draws `Theme.Colors.highlight`, which follows the appearance; a chosen colour does not.
    var highlightColor: NoteHighlightColor? {
        didSet {
            defaults.set(highlightColor?.hex, forKey: Key.highlightColor)
            onSyncedChange(.highlightColor)
        }
    }
    /// Nil follows the macOS accent colour; a chosen colour is fixed. Underlines, links and the selection use it.
    var accentColor: NoteAccentColor? {
        didSet {
            defaults.set(accentColor?.hex, forKey: Key.accentColor)
            onSyncedChange(.accentColor)
        }
    }
    /// Unbound commands are absent; nothing is bound until the user records a shortcut.
    var shortcuts: [HotKeyCommand: KeyShortcut] {
        didSet {
            guard shortcuts != oldValue else { return }
            let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
            // Sorted, so equal shortcuts encode to equal bytes on every Mac and iCloud sees no change.
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            defaults.set(try? encoder.encode(stored), forKey: Key.shortcuts)
            onSyncedChange(.shortcuts)
        }
    }
    /// On, the notes and the synced preferences live in iCloud. The switch itself always syncs.
    var syncsWithICloud: Bool {
        didSet {
            defaults.set(syncsWithICloud, forKey: Key.syncsWithICloud)
            onSyncedChange(.syncsWithICloud)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsFormattingBar = Self.readShowsFormattingBar(defaults)
        notesFolder = defaults.string(forKey: Key.notesFolder)
        showsInDock = defaults.bool(forKey: Key.showsInDock)
        keepsOnTop = defaults.bool(forKey: Key.keepsOnTop)
        fonts = Self.readFonts(defaults)
        highlightColor = Self.readHighlightColor(defaults)
        accentColor = Self.readAccentColor(defaults)
        shortcuts = Self.readShortcuts(defaults)
        syncsWithICloud = defaults.bool(forKey: Key.syncsWithICloud)
    }

    /// The stored keys of `synced`; empty while every one of them is at its default.
    func storedValue(of synced: Synced) -> [String: Any] {
        synced.keys.reduce(into: [:]) { value, key in value[key] = defaults.object(forKey: key) }
    }

    /// Stores `value` as `synced`'s keys, then parses them as a launch would. A key `value` lacks is
    /// removed, so the preference returns to its default.
    func restore(_ synced: Synced, from value: [String: Any]) {
        for key in synced.keys { defaults.set(value[key], forKey: key) }
        switch synced {
        case .syncsWithICloud: syncsWithICloud = defaults.bool(forKey: Key.syncsWithICloud)
        case .showsFormattingBar: showsFormattingBar = Self.readShowsFormattingBar(defaults)
        case .fonts: fonts = Self.readFonts(defaults)
        case .highlightColor: highlightColor = Self.readHighlightColor(defaults)
        case .accentColor: accentColor = Self.readAccentColor(defaults)
        case .shortcuts: shortcuts = Self.readShortcuts(defaults)
        }
    }

    private static func readShowsFormattingBar(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: Key.showsFormattingBar) as? Bool ?? true
    }

    private static func readFonts(_ defaults: UserDefaults) -> NoteFontSettings {
        NoteFontSettings(
            textFamily: defaults.string(forKey: Key.textFont),
            headingFamily: defaults.string(forKey: Key.headingFont),
            cjkFamily: defaults.string(forKey: Key.cjkFont),
            codeFamily: defaults.string(forKey: Key.codeFont),
            size: (defaults.object(forKey: Key.fontSize) as? Double)
                .map { min(max($0, NoteFontSettings.sizeRange.lowerBound), NoteFontSettings.sizeRange.upperBound) })
    }

    private static func readHighlightColor(_ defaults: UserDefaults) -> NoteHighlightColor? {
        defaults.string(forKey: Key.highlightColor).flatMap(NoteHighlightColor.init(hex:))
    }

    private static func readAccentColor(_ defaults: UserDefaults) -> NoteAccentColor? {
        defaults.string(forKey: Key.accentColor).flatMap(NoteAccentColor.init(hex:))
    }

    private static func readShortcuts(_ defaults: UserDefaults) -> [HotKeyCommand: KeyShortcut] {
        let stored = defaults.data(forKey: Key.shortcuts)
            .flatMap { try? JSONDecoder().decode([String: KeyShortcut].self, from: $0) }
        return (stored ?? [:]).reduce(into: [:]) { shortcuts, entry in
            guard let command = HotKeyCommand(rawValue: entry.key) else { return }
            shortcuts[command] = entry.value
        }
    }
}
