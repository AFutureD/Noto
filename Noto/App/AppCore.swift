import AppKit
import SwiftUI

/// The single owner of every long-lived object. See docs/architecture.md#single-owner-core.
@MainActor
@Observable
final class AppCore {
    static let shared = AppCore()

    let settings: NotoSettings
    let notesStore: NotesStore
    let hotKeys: HotKeyManager
    @ObservationIgnored let activationPolicy = ActivationPolicy()

    /// Window state, not a preference: it rides `UserDefaults` like the active note's filename.
    private nonisolated static let noteFormattingBarKey = "notesFormattingBarExpanded"
    private nonisolated static let noteSelectionKey = "notesActiveFileName"

    @ObservationIgnored private(set) lazy var notesCoordinator = NotesCoordinator(
        store: notesStore,
        settings: settings,
        dialogs: .alerts,
        isFormattingBarExpanded: UserDefaults.standard.bool(forKey: Self.noteFormattingBarKey),
        saveFormattingBarExpanded: {
            UserDefaults.standard.set($0, forKey: Self.noteFormattingBarKey)
        })

    @ObservationIgnored private lazy var settingsWindow = AppWindowController(
        title: "\(Bundle.main.appDisplayName) Settings",
        contentSize: Theme.Size.settingsWindow,
        activation: activationPolicy,
        closesOnEscape: true)

    private init() {
        let settings = NotoSettings()
        self.settings = settings
        hotKeys = HotKeyManager(settings: settings)
        notesStore = NotesStore(
            repository: Self.notesRepository(for: settings),
            loadSelection: {
                UserDefaults.standard.string(forKey: Self.noteSelectionKey).map(NoteID.init(rawValue:))
            },
            saveSelection: { UserDefaults.standard.set($0?.rawValue, forKey: Self.noteSelectionKey) })
    }

    func start() {
        activationPolicy.showsInDock = settings.showsInDock
        hotKeys.start { [weak self] in self?.run($0) }
        observeNotesFolder()
        observeShowsInDock()
        // A Dock app that launches to nothing looks broken; the menu-bar agent stays quiet.
        if settings.showsInDock { notesCoordinator.show() }
    }

    func run(_ command: HotKeyCommand) {
        switch command {
        case .showNotes: notesCoordinator.toggle()
        case .createNote: notesCoordinator.createNote()
        case .searchNotes: notesCoordinator.searchNotes()
        }
    }

    func showSettings() {
        settingsWindow.show {
            SettingsView()
                .environment(self)
                .environment(settings)
                .environment(hotKeys)
        }
    }

    /// A click on the Dock icon.
    func handleReopen() {
        notesCoordinator.show()
    }

    func flushNotesForTermination() async {
        await notesCoordinator.prepareForTermination()
    }

    // MARK: - Private

    /// Re-armed after every change: `withObservationTracking` fires once per registration.
    private func observeNotesFolder() {
        withObservationTracking {
            _ = settings.notesFolder
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let repository = Self.notesRepository(for: self.settings)
                await self.notesStore.relocate(to: repository)
                self.observeNotesFolder()
            }
        }
    }

    private func observeShowsInDock() {
        withObservationTracking {
            _ = settings.showsInDock
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.activationPolicy.showsInDock = self.settings.showsInDock
                self.observeShowsInDock()
            }
        }
    }

    private static func notesRepository(for settings: NotoSettings) -> NotesRepository {
        NotesRepository(notesDirectory: AppPaths.contentFolder(settings.notesFolder, named: "Notes"))
    }
}
