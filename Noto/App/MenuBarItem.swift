import SwiftUI

/// Noto's menu-bar item. It stays in both modes, so the app is reachable with no Dock icon.
struct MenuBarLabel: View {
    let appName: String

    var body: some View {
        Image(systemName: "text.page")
            .accessibilityLabel(appName)
    }
}

struct MenuBarMenu: View {
    let appName: String

    var body: some View {
        Button("Show Notes") { AppCore.shared.run(.showNotes) }
        Button("New Note") { AppCore.shared.run(.createNote) }
        Button("Search Notes") { AppCore.shared.run(.searchNotes) }
        Divider()
        Button("Settings…") { AppCore.shared.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit \(appName)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
