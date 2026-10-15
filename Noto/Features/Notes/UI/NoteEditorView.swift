import AppKit
import MDTextKit
import MDTextKitUI
import SFThemeKit
import SwiftUI
import os

struct NoteEditorView: NSViewRepresentable {
    let input: NoteEditorInput
    /// The base of the note's relative image paths; nil shows every image as a placeholder.
    var noteFolder: URL?
    var fonts = NoteFontSettings.standard
    var highlight: NoteHighlightColor?
    var accent: NoteAccentColor?
    let onSourceChange: (String) -> Void
    let onCharacterCountChange: (NoteEditorInput, Int) -> Void
    let onFormattingChange: (NoteEditorInput, NoteFormatting) -> Void
    /// Copies pasted or dropped files into the note and returns their relative paths.
    let onImportFiles: ([URL], NoteID) async -> [String]?
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
        context.coordinator.setNoteFolder(noteFolder)
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
        private var noteFolder: URL?
        /// Set when the folder changed and no install has resolved the images against it yet.
        private var needsImageRestyle = false
        /// Counts edits, so an import that lands late knows whether its paste range still holds.
        private var editCount = 0
        private var fonts: NoteFontSettings
        private var highlight: NoteHighlightColor?
        private var accent: NoteAccentColor?
        private var isInstalling = false
        private var observers: [NotificationToken] = []

        init(parent: NoteEditorView) {
            self.parent = parent
            input = parent.input
            noteFolder = parent.noteFolder
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
            textView.imageFileResolver = { [weak self] path in
                guard let folder = self?.noteFolder, let file = NoteAssets.resolve(path, in: folder) else {
                    return nil
                }
                return Self.downloadedFile(file)
            }
            textView.addFilesBlock = { [weak self] files, range in
                self?.importFiles(files, replacing: range)
            }
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

        /// Set before `update`, so an install resolves its images against the new note.
        func setNoteFolder(_ folder: URL?) {
            guard folder != noteFolder else { return }
            noteFolder = folder
            needsImageRestyle = true
        }

        func update(_ next: NoteEditorInput) {
            let authoritative =
                next != input
                && (next.id != input.id || next.epoch != input.epoch || next.source != textView.markdown)
            input = next
            if authoritative {
                install(next)
            } else if needsImageRestyle {
                // The notes folder moved under the same note: the images resolve somewhere else now.
                editorController.restyleAll(in: textView)
                textView.needsDisplay = true
            }
            needsImageRestyle = false
        }

        /// The image decodes on the main actor while it styles, so a file iCloud has not downloaded
        /// shows the placeholder and starts its download instead of blocking the editor.
        private static func downloadedFile(_ file: URL) -> URL? {
            let status = (try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
                .ubiquitousItemDownloadingStatus
            guard let status, status != .current else { return file }
            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
            return nil
        }

        /// The copy runs off-main. The Markdown goes where the paste was while no edit has moved it,
        /// else at the caret. A switch to another note or a reload drops it, with a log line.
        private func importFiles(_ files: [URL], replacing range: NSRange) {
            // `NoteTextView` passes only images; a pasted image is a temporary PNG.
            let images = files.filter(NoteAssets.isImage)
            guard !images.isEmpty else { return }
            let target = input
            let edits = editCount
            Task { [weak self] in
                guard let self, let paths = await parent.onImportFiles(images, target.id), !paths.isEmpty else {
                    return
                }
                guard input.id == target.id, input.epoch == target.epoch else {
                    Logger.notes.notice("dropped the Markdown of \(paths.count) imported images: the note changed")
                    return
                }
                let target =
                    edits == editCount && NSMaxRange(range) <= textView.mdTextStorage.length
                    ? range : textView.selectedRange()
                let text = textView.mdTextStorage.string as NSString
                let previous = target.location > 0
                    ? Character(text.substring(with: NSRange(location: target.location - 1, length: 1))) : nil
                let next = NSMaxRange(target) < text.length
                    ? Character(text.substring(with: NSRange(location: NSMaxRange(target), length: 1))) : nil
                let markdown = NoteAssets.paragraph(
                    paths.map(NoteAssets.markdown(for:)).joined(separator: "\n"), after: previous, before: next)
                let before = textView.mdTextStorage.length
                editorController.replaceCharacters(
                    in: target, with: NSAttributedString(string: markdown), in: textView)
                // Styling turns each image into one attachment character, so the caret goes by the
                // storage's growth, not by the Markdown's length.
                let inserted = target.length + textView.mdTextStorage.length - before
                textView.setSelectedRange(NSRange(location: target.location + inserted, length: 0))
                // A replacement writes the storage directly; this reports it, so autosave sees it.
                textView.didChangeText()
            }
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
            editCount &+= 1
            textView.updateEmojiPicker()
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
            textView.updateEmojiPicker()
            guard !isInstalling else { return }
            reportFormatting()
        }

        private func reportCharacterCount() {
            parent.onCharacterCountChange(input, (input.source as NSString).length)
        }

        private func reportFormatting() {
            parent.onFormattingChange(input, textView.formatting)
        }

        /// The theme's colours and fonts, then Noto's own frame: no column, no background, a top inset.
        /// No horizontal inset: the theme's side margin is the whole margin, so the markers centre in it.
        static func configure(_ textView: NoteTextView, with themeManager: SFThemeManager) {
            textView.applyTheme(themeManager)
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 0, height: Theme.Size.noteEditorTopInset)
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
