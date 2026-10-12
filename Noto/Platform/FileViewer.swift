import AppKit

/// Reveals a file in the viewer the global `NSFileViewer` default names, or Finder when it is unset.
@MainActor
enum FileViewer {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        bringForwardIfRefused()
    }

    /// While `.regular` and inactive, cooperative activation refuses the viewer's own activation.
    private static func bringForwardIfRefused() {
        guard NSApp.activationPolicy() == .regular, !NSApp.isActive,
            let viewer = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: viewer, configuration: NSWorkspace.OpenConfiguration())
    }

    private static var bundleID: String {
        UserDefaults.standard.string(forKey: "NSFileViewer") ?? "com.apple.finder"
    }
}
