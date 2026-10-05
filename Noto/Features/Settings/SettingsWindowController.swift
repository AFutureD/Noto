import AppKit
import SwiftUI

/// The pane the Settings window shows; the toolbar writes it and `SettingsView` reads it.
@MainActor
@Observable
final class SettingsNavigation {
    var pane = SettingsPane.general
    /// The laid-out height of the pane on screen, reported by `SettingsView` after each layout.
    @ObservationIgnored var onContentHeight: (CGFloat) -> Void = { _ in }
}

private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// Built on first show, torn down on close so its SwiftUI tree deallocates. Never quits the app.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private let activation: ActivationPolicy
    private let navigation = SettingsNavigation()
    private var window: NSWindow?
    private var hosting: NSHostingView<AnyView>?

    init(activation: ActivationPolicy) {
        self.activation = activation
    }

    func show<Content: View>(@ViewBuilder content: (SettingsNavigation) -> Content) {
        if let window {
            raise(window)
            return
        }
        let hosting = NSHostingView(rootView: AnyView(content(navigation)))
        // The window follows the pane's height through `fit`, never through SwiftUI.
        hosting.sizingOptions = []
        let window = makeWindow(content: hosting)
        self.hosting = hosting
        self.window = window
        hosting.layoutSubtreeIfNeeded()
        fit(window, height: hosting.fittingSize.height, animated: false)
        window.center()
        // Asking the hosting view right after a pane change returns the old pane's height.
        navigation.onContentHeight = { [weak self, weak window] height in
            guard let self, let window, self.window === window else { return }
            self.fit(window, height: height, animated: true)
        }
        activation.windowDidOpen(window)
        raise(window)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        self.window = nil
        hosting = nil
        navigation.onContentHeight = { _ in }
        activation.windowDidClose(window)
    }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = SettingsPane(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.title
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }

    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane(rawValue: sender.itemIdentifier.rawValue), let window else { return }
        navigation.pane = pane
        window.title = pane.title
        // A real click selects the item itself; an accessibility press only sends the action.
        window.toolbar?.selectedItemIdentifier = sender.itemIdentifier
    }

    // MARK: - Private

    private func makeWindow(content: NSView) -> NSWindow {
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: Theme.Size.settingsWidth, height: 1)),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = navigation.pane.title
        window.isReleasedWhenClosed = false
        // AppKit would otherwise resurrect the window at launch, before anything is wired up.
        window.isRestorable = false
        window.delegate = self
        let toolbar = NSToolbar(identifier: "Settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(navigation.pane.rawValue)
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        window.contentView = content
        return window
    }

    /// The top edge stays where it is, so the toolbar does not move as the panes change height.
    private func fit(_ window: NSWindow, height: CGFloat, animated: Bool) {
        let content = CGSize(width: Theme.Size.settingsWidth, height: height.rounded(.up))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: animated)
    }

    private func raise(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // `NSApp.activate` is async, so re-assert next turn — never onto a window closed since.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window, self?.window === window else { return }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
