import AppKit
import SwiftUI

/// A `.noto` package as an `NSDocument`, only so that macOS can show its version browser: the
/// Time Machine-like view of "Browse All Versions". The browser opens each earlier version with this
/// class and shows its window; Restore replaces the package. Noto never edits or saves through it.
/// `Info.plist` names it as the document class of `app.huanan.noto.note`. See
/// docs/features/history.md.
@objc(NoteVersionDocument)
final class NoteVersionDocument: NSDocument {
    static let typeName = "app.huanan.noto.note"

    /// The editor settings the windows render with. `NotesCoordinator` sets them before each browse,
    /// because the browser creates the documents of the earlier versions itself.
    @MainActor static var style = Style()

    struct Style {
        var fonts = NoteFontSettings.standard
        var highlight: NoteHighlightColor?
        var accent: NoteAccentColor?
        var frame: NSRect?
    }

    /// The text the window shows. A restore reads the package again, so the window follows it.
    @MainActor private let shown = ShownSource()

    @MainActor @Observable
    final class ShownSource {
        var source = ""
    }

    override static var autosavesInPlace: Bool { true }
    override static var readableTypes: [String] { [typeName] }
    override static var writableTypes: [String] { [] }
    override static func isNativeType(_ type: String) -> Bool { type == typeName }

    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        guard let data = fileWrapper.fileWrappers?[NotesRepository.contentFileName]?.regularFileContents,
            let source = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        // `canConcurrentlyReadDocuments` is false, so AppKit reads on the main thread.
        MainActor.assumeIsolated { shown.source = source }
    }

    /// Nothing is edited, so AppKit has no reason to save; if it asks, the package on disk is the
    /// answer, and nothing changes.
    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        guard let fileURL else { throw CocoaError(.fileWriteUnknown) }
        return try FileWrapper(url: fileURL, options: .immediate)
    }

    /// The title without `.noto`, as Noto shows it. The browser names each version window this way too.
    override var displayName: String! {  // swiftlint:disable:this implicitly_unwrapped_optional
        get {
            let name: String = super.displayName ?? ""
            let suffix = ".\(NotesRepository.packageExtension)"
            return name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
        }
        // NSDocument declares the property this way; the override has to match it.
        set { super.displayName = newValue }
    }

    override func makeWindowControllers() {
        MainActor.assumeIsolated {
            let style = Self.style
            let view = ShownPreview(
                shown: shown, folder: fileURL ?? URL(fileURLWithPath: "/"), style: style)
            .padding(.horizontal, Theme.Size.noteSideMargin)
            .padding(.top, Theme.Spacing.xl)
            let window = NSWindow(
                contentRect: style.frame ?? NSRect(origin: .zero, size: Theme.Size.versionWindow),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false)
            window.contentView = NSHostingView(rootView: view)
            // A version window must not come back at the next launch.
            window.isRestorable = false
            if style.frame == nil { window.center() }
            addWindowController(NSWindowController(window: window))
        }
    }
}

/// Reads `Shown` in its body, so a restore that reads the package again redraws the window.
private struct ShownPreview: View {
    let shown: NoteVersionDocument.ShownSource
    let folder: URL
    let style: NoteVersionDocument.Style

    var body: some View {
        NoteVersionPreview(
            content: NoteVersionContent(source: shown.source, folder: folder),
            fonts: style.fonts, highlight: style.highlight, accent: style.accent)
    }
}
