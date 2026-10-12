import AppKit
import SwiftUI

/// A child window, so a menu can outgrow a short note window; it never takes key from the editor.
@MainActor
final class NoteBarMenuWindowController {
    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?

    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    func show(_ menu: NoteBarMenu, above host: NSWindow) {
        let panel = ensurePanel()
        panel.staysOnTop = (host as? NotesPanel)?.staysOnTop ?? false
        anchor(panel, for: menu, above: host)
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
        let hosting = NSHostingView(rootView: NoteBarMenuView().environment(coordinator))
        hosting.sizingOptions = []
        let panel = NotesPanel(
            content: hosting,
            size: Theme.Size.noteBarMenu(rows: NoteBarMenu.heading.rows.count),
            styleMask: .borderless,
            acceptsMain: false)
        panel.acceptsKey = false
        self.panel = panel
        return panel
    }

    /// Hangs off the menu's own button, whose frame arrives flipped from the SwiftUI bar.
    private func anchor(_ panel: NotesPanel, for menu: NoteBarMenu, above host: NSWindow) {
        let button = coordinator.barMenuButtonFrames[menu] ?? .zero
        let size = Theme.Size.noteBarMenu(rows: menu.rows.count)
        // Right-aligned to its button when the menu would otherwise leave the window.
        let x = min(host.frame.minX + button.minX, host.frame.maxX - size.width - Theme.Spacing.xs)
        let origin = CGPoint(x: x, y: host.frame.maxY - button.minY + Theme.Spacing.xs)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }
}
