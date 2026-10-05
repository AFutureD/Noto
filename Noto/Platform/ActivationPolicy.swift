import AppKit

/// Keyed by window identity, not a count: a repeated open or close can't strand the Dock icon.
@MainActor
final class ActivationPolicy {
    private var openWindows: Set<ObjectIdentifier> = []

    /// The Show in Dock preference; off, the Dock icon only stands for the open titled windows.
    var showsInDock = false {
        didSet { apply() }
    }

    var hasOpenWindows: Bool { !openWindows.isEmpty }

    func windowDidOpen(_ window: NSWindow) {
        openWindows.insert(ObjectIdentifier(window))
        apply()
    }

    func windowDidClose(_ window: NSWindow) {
        openWindows.remove(ObjectIdentifier(window))
        apply()
    }

    /// Each close reports back through `windowDidClose`, which drops the Dock icon after the last.
    func closeAll() {
        for window in NSApp.windows where openWindows.contains(ObjectIdentifier(window)) {
            window.close()
        }
    }

    private func apply() {
        let policy: NSApplication.ActivationPolicy =
            showsInDock || hasOpenWindows ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }
}
