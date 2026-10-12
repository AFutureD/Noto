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
    }

    @ObservationIgnored private let defaults: UserDefaults

    var showsFormattingBar: Bool {
        didSet { defaults.set(showsFormattingBar, forKey: Key.showsFormattingBar) }
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
        }
    }
    /// Nil draws `Theme.Colors.highlight`, which follows the appearance; a chosen colour does not.
    var highlightColor: NoteHighlightColor? {
        didSet { defaults.set(highlightColor?.hex, forKey: Key.highlightColor) }
    }
    /// Unbound commands are absent; nothing is bound until the user records a shortcut.
    var shortcuts: [HotKeyCommand: KeyShortcut] {
        didSet {
            guard shortcuts != oldValue else { return }
            let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
            defaults.set(try? JSONEncoder().encode(stored), forKey: Key.shortcuts)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsFormattingBar = defaults.object(forKey: Key.showsFormattingBar) as? Bool ?? true
        notesFolder = defaults.string(forKey: Key.notesFolder)
        showsInDock = defaults.bool(forKey: Key.showsInDock)
        keepsOnTop = defaults.bool(forKey: Key.keepsOnTop)
        fonts = NoteFontSettings(
            textFamily: defaults.string(forKey: Key.textFont),
            headingFamily: defaults.string(forKey: Key.headingFont),
            cjkFamily: defaults.string(forKey: Key.cjkFont),
            codeFamily: defaults.string(forKey: Key.codeFont),
            size: (defaults.object(forKey: Key.fontSize) as? Double)
                .map { min(max($0, NoteFontSettings.sizeRange.lowerBound), NoteFontSettings.sizeRange.upperBound) })
        highlightColor = defaults.string(forKey: Key.highlightColor).flatMap(NoteHighlightColor.init(hex:))
        let stored = defaults.data(forKey: Key.shortcuts)
            .flatMap { try? JSONDecoder().decode([String: KeyShortcut].self, from: $0) }
        shortcuts = (stored ?? [:]).reduce(into: [:]) { shortcuts, entry in
            guard let command = HotKeyCommand(rawValue: entry.key) else { return }
            shortcuts[command] = entry.value
        }
    }
}
