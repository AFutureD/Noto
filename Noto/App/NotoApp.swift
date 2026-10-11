import SwiftUI

@main
struct NotoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // "Noto", or "Noto Dev" for a Debug build.
    private let appName = Bundle.main.appDisplayName

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(appName: appName)
        } label: {
            MenuBarLabel(appName: appName)
        }
        .commands { mainMenuCommands }
    }

    /// Declared, not assigned to `NSApp.mainMenu`: SwiftUI rebuilds the menu on any scene change.
    @CommandsBuilder
    private var mainMenuCommands: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { AppCore.shared.updates.checkForUpdates() }
                .disabled(!AppCore.shared.updates.canCheckForUpdates)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppCore.shared.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("New Note") { AppCore.shared.run(.createNote) }
                .keyboardShortcut("n")
            Button("Show Notes") { AppCore.shared.notesCoordinator.show() }
            Button("Search Notes") { AppCore.shared.run(.searchNotes) }
        }
    }
}
