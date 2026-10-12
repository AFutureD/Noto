import AppKit
import MDTextKit
import MDTextKitUI
import SFThemeKit
import SwiftUI

struct NoteEditorView: NSViewRepresentable {
    let input: NoteEditorInput
    var fonts = NoteFontSettings.standard
    var highlight: NoteHighlightColor?
    var accent: NoteAccentColor?
    let onSourceChange: (String) -> Void
    let onCharacterCountChange: (NoteEditorInput, Int) -> Void
    let onFormattingChange: (NoteEditorInput, NoteFormatting) -> Void
    let onReady: (NoteTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        // `NotesView` lays out its own title-bar band, so AppKit must not inset this a second time.
        scrollView.automaticallyAdjustsContentInsets = false
        let textView = context.coordinator.textView
        scrollView.documentView = textView
        context.coordinator.install(input)
        onReady(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(input)
        context.coordinator.setFonts(fonts)
        context.coordinator.setHighlight(highlight)
        context.coordinator.setAccent(accent)
    }

    @MainActor
    final class Coordinator {
        var parent: NoteEditorView
        let textView: NoteTextView
        let editorController = MDEditorController()
        let themeManager = SFThemeManager(theme: NoteEditorTheme.make())
        var editorUndoManager: UndoManager { textView.editorUndoManager }

        private var input: NoteEditorInput
        private var fonts: NoteFontSettings
        private var highlight: NoteHighlightColor?
        private var accent: NoteAccentColor?
        private var isInstalling = false
        private var observers: [NotificationToken] = []

        init(parent: NoteEditorView) {
            self.parent = parent
            input = parent.input
            fonts = parent.fonts
            highlight = parent.highlight
            accent = parent.accent
            editorController.autoHideMarkdown = true
            textView = NoteTextView(
                frame: NSRect(x: 0, y: 0, width: Theme.Size.noteWindow.width, height: 1),
                editorController: editorController)
            themeManager.overrides = NoteEditorTheme.overrides(fonts: fonts, highlight: highlight, accent: accent)
            textView.installTableEditing(themeManager: themeManager)
            Self.configure(textView, with: themeManager)
            textView.openURL = { [weak self] url in
                guard let self, let scheme = url.scheme?.lowercased(), Self.openableSchemes.contains(scheme)
                else { return }
                open(url)
            }
            observers = [
                observe(MDTextViewTextDidChangeNotification) { [weak self] in self?.sourceDidChange() },
                observe(MDTextViewTextDidChangeSelectionNotification) { [weak self] in self?.selectionDidChange() }
            ]
        }

        /// The text view posts on the main thread, from its own delegate calls, so no hop is needed.
        private func observe(_ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) -> NotificationToken {
            let center = NotificationCenter.default
            let token = center.addObserver(forName: name, object: textView, queue: nil) { _ in
                MainActor.assumeIsolated(handler)
            }
            return NotificationToken(token, center: center)
        }

        /// Only `http`, `https` and `mailto` leave the editor; a `file:` link is inert.
        static let openableSchemes: Set<String> = ["http", "https", "mailto"]
        /// Replaced by the harness, which records a link instead of opening a browser.
        var open: (URL) -> Void = { NSWorkspace.shared.open($0) }

        func install(_ input: NoteEditorInput) {
            let wasEmpty = textView.mdTextStorage.length == 0
            self.input = input
            let caret = textView.selectedRange().location
            isInstalling = true
            editorController.loadString(input.source, into: textView)
            textView.setSelectedRange(NSRange(location: min(caret, textView.mdTextStorage.length), length: 0))
            if wasEmpty != input.source.isEmpty { textView.needsDisplay = true }
            isInstalling = false
            reportCharacterCount()
            reportFormatting()
        }

        func update(_ next: NoteEditorInput) {
            guard next != input else { return }
            let authoritative =
                next.id != input.id || next.epoch != input.epoch || next.source != textView.markdown
            input = next
            guard authoritative else { return }
            install(next)
        }

        func setFonts(_ fonts: NoteFontSettings) {
            guard fonts != self.fonts else { return }
            self.fonts = fonts
            applyOverrides()
        }

        func setHighlight(_ highlight: NoteHighlightColor?) {
            guard highlight != self.highlight else { return }
            self.highlight = highlight
            applyOverrides()
        }

        func setAccent(_ accent: NoteAccentColor?) {
            guard accent != self.accent else { return }
            self.accent = accent
            applyOverrides()
        }

        /// A restyle writes attributes with undo off, so neither the history nor the draft changes.
        private func applyOverrides() {
            themeManager.overrides = NoteEditorTheme.overrides(fonts: fonts, highlight: highlight, accent: accent)
            Self.configure(textView, with: themeManager)
            editorController.restyleAll(in: textView)
            textView.needsDisplay = true
        }

        private func sourceDidChange() {
            guard !isInstalling else { return }
            reportFormatting()
            let source = textView.markdown
            guard source != input.source else { return }
            if input.source.isEmpty != source.isEmpty { textView.needsDisplay = true }
            input = NoteEditorInput(id: input.id, source: source, epoch: input.epoch)
            parent.onSourceChange(source)
            reportCharacterCount()
        }

        private func selectionDidChange() {
            guard !isInstalling else { return }
            reportFormatting()
        }

        private func reportCharacterCount() {
            parent.onCharacterCountChange(input, (input.source as NSString).length)
        }

        private func reportFormatting() {
            parent.onFormattingChange(input, textView.formatting)
        }

        /// The theme's colours and fonts, then Noto's own frame: no column, no background, its insets.
        static func configure(_ textView: NoteTextView, with themeManager: SFThemeManager) {
            textView.applyTheme(themeManager)
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(
                width: Theme.Size.noteEditorInset,
                height: Theme.Size.noteEditorTopInset)
            textView.mdTextContainer.lineFragmentPadding = 0
            textView.insertionPointColor = NSColor(Theme.Colors.noteText)
            let accent = themeManager.color(forKey: "editor.accent color")
            textView.selectedTextAttributes = [
                .backgroundColor: accent.withAlphaComponent(NoteEditorTheme.selectionAlpha),
                .foregroundColor: NSColor(Theme.Colors.noteText)
            ]
            textView.linkTextAttributes = [.foregroundColor: accent, .cursor: NSCursor.pointingHand]
        }
    }
}
