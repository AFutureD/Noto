import AppKit
import SwiftUI

/// The `:` emoji list in a child window under the caret. Like a bar menu, it never takes key, so
/// the editor keeps the caret and reads the arrows and Return itself.
@MainActor
final class NoteEmojiPickerWindowController {
    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?

    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    /// `anchor` is the screen rect of the query's `:`.
    func show(rows: Int, anchor: NSRect, above host: NSWindow) {
        let panel = ensurePanel()
        panel.staysOnTop = (host as? NotesPanel)?.staysOnTop ?? false
        place(panel, rows: rows, anchor: anchor, screen: host.screen)
        if panel.parent !== host {
            panel.parent?.removeChildWindow(panel)
            host.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func ensurePanel() -> NotesPanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: NoteEmojiPickerView().environment(coordinator))
        hosting.sizingOptions = []
        let panel = NotesPanel(
            content: hosting,
            size: Theme.Size.noteEmojiPicker(rows: NoteEmojiPicker.rowLimit),
            styleMask: .borderless,
            acceptsMain: false)
        panel.acceptsKey = false
        self.panel = panel
        return panel
    }

    /// Below the line, left-aligned to the `:`; above it when the screen ends first.
    private func place(_ panel: NotesPanel, rows: Int, anchor: NSRect, screen: NSScreen?) {
        let size = Theme.Size.noteEmojiPicker(rows: rows)
        let visible = screen?.visibleFrame ?? .infinite
        var origin = CGPoint(x: anchor.minX - Theme.Spacing.md, y: anchor.minY - size.height - Theme.Spacing.xs)
        if origin.y < visible.minY { origin.y = anchor.maxY + Theme.Spacing.xs }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
