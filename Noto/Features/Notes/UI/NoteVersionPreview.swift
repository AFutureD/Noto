import AppKit
import MDTextKit
import MDTextKitUI
import SFThemeKit
import SwiftUI

/// The text of one version of a note, and the package its images resolve against.
struct NoteVersionContent: Equatable {
    let source: String
    let folder: URL
}

/// One version of a note, rendered and read-only. It has the editor's theme and fonts, and resolves
/// images against the version's own package, so it shows the images as they were.
struct NoteVersionPreview: NSViewRepresentable {
    let content: NoteVersionContent
    var fonts = NoteFontSettings.standard
    var highlight: NoteHighlightColor?
    var accent: NoteAccentColor?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = context.coordinator.textView
        context.coordinator.show(content, fonts: fonts, highlight: highlight, accent: accent)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.show(content, fonts: fonts, highlight: highlight, accent: accent)
    }

    @MainActor
    final class Coordinator {
        let editorController = MDEditorController()
        let themeManager = SFThemeManager(theme: NoteEditorTheme.make())
        let textView: NoteTextView
        private var shown: NoteVersionContent?
        private var folder: URL?
        private var style: Style?

        private struct Style: Equatable {
            let fonts: NoteFontSettings
            let highlight: NoteHighlightColor?
            let accent: NoteAccentColor?
        }

        init() {
            editorController.autoHideMarkdown = true
            textView = NoteTextView(
                frame: NSRect(x: 0, y: 0, width: Theme.Size.noteWindow.width, height: 1),
                editorController: editorController)
            textView.installTableEditing(themeManager: themeManager)
            NoteEditorView.Coordinator.configure(textView, with: themeManager)
            textView.isEditable = false
            textView.imageFileResolver = { [weak self] path in
                guard let folder = self?.folder else { return nil }
                return NoteAssets.resolve(path, in: folder)
            }
            // A link in an old version opens nothing; the preview is for reading and copying.
            textView.openURL = { _ in }
        }

        func show(
            _ content: NoteVersionContent, fonts: NoteFontSettings,
            highlight: NoteHighlightColor?, accent: NoteAccentColor?
        ) {
            let next = Style(fonts: fonts, highlight: highlight, accent: accent)
            let restyles = next != style
            if restyles {
                style = next
                themeManager.overrides = NoteEditorTheme.overrides(fonts: fonts, highlight: highlight, accent: accent)
                NoteEditorView.Coordinator.configure(textView, with: themeManager)
            }
            if content != shown {
                shown = content
                folder = content.folder
                editorController.loadString(content.source, into: textView)
                textView.scrollToBeginningOfDocument(nil)
            } else if restyles {
                editorController.restyleAll(in: textView)
                textView.needsDisplay = true
            }
        }
    }
}
