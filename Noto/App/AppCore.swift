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
    @ObservationIgnored let settingsMirror: CloudSettingsMirror
    let cloudNotes = CloudNotesLocation()
    @ObservationIgnored private let notesWatcher = NotesWatcher()
    let updates = UpdateCoordinator()
    @ObservationIgnored let activationPolicy = ActivationPolicy()

    /// Window state, not a preference: it rides `UserDefaults` like the active note's filename.
    private nonisolated static let noteFormattingBarKey = "notesFormattingBarExpanded"
    private nonisolated static let noteSelectionKey = "notesActiveFileName"

    @ObservationIgnored private(set) lazy var notesCoordinator = NotesCoordinator(
        store: notesStore,
        settings: settings,
        cloudNotes: cloudNotes,
        dialogs: .alerts,
        isFormattingBarExpanded: UserDefaults.standard.bool(forKey: Self.noteFormattingBarKey),
        saveFormattingBarExpanded: {
            UserDefaults.standard.set($0, forKey: Self.noteFormattingBarKey)
        })

    @ObservationIgnored private lazy var settingsWindow = SettingsWindowController(
        activation: activationPolicy)

    private init() {
        let settings = NotoSettings()
        self.settings = settings
        hotKeys = HotKeyManager(settings: settings)
        settingsMirror = CloudSettingsMirror(settings: settings)
        notesStore = NotesStore(
            repository: NotesRepository(notesDirectory: AppPaths.contentFolder(settings.notesFolder, named: "Notes")),
            loadSelection: {
                UserDefaults.standard.string(forKey: Self.noteSelectionKey).map(NoteID.init(rawValue:))
            },
            saveSelection: { UserDefaults.standard.set($0?.rawValue, forKey: Self.noteSelectionKey) })
    }

    func start() {
        activationPolicy.showsInDock = settings.showsInDock
        hotKeys.start { [weak self] in self?.run($0) }
        settingsMirror.onRemoteChange = { [weak self] synced in
            if synced == .shortcuts { self?.hotKeys.registerAll() }
        }
        settingsMirror.start()
        updates.start()
        cloudNotes.start()
        notesWatcher.onChange = { [weak self] conflicts in
            guard let self else { return }
            Task {
                if !conflicts.isEmpty {
                    await self.notesStore.resolveConflicts(conflicts)
                } else if self.notesStore.isLoaded {
                    // Nothing lists before the window first shows; that listing sees the change.
                    _ = await self.notesStore.reload()
                }
            }
        }
        observeNotesLocation()
        Task { await applyNotesLocation() }
        observeShowsInDock()
        // A Dock app that launches to nothing looks broken; the menu-bar agent stays quiet.
        if settings.showsInDock { notesCoordinator.show() }
    }

    func run(_ command: HotKeyCommand) {
        switch command {
        case .showNotes: notesCoordinator.toggle()
        case .createNote: notesCoordinator.createNote()
        case .searchNotes: notesCoordinator.searchNotes()
        case .toggleKeepOnTop: notesCoordinator.toggleKeepOnTop()
        }
    }

    func showSettings() {
        settingsWindow.show { navigation in
            SettingsView()
                .environment(navigation)
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
    private func observeNotesLocation() {
        withObservationTracking {
            _ = settings.notesFolder
            _ = settings.syncsWithICloud
            _ = cloudNotes.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.applyNotesLocation()
                self.observeNotesLocation()
            }
        }
    }

    /// iCloud while sync is on and iCloud is there, else the folder on this Mac.
    private func applyNotesLocation() async {
        guard settings.syncsWithICloud else {
            notesWatcher.stop()
            await notesStore.relocate(to: NotesRepository(
                notesDirectory: AppPaths.contentFolder(settings.notesFolder, named: "Notes")))
            return
        }
        switch cloudNotes.state {
        case .unknown:
            // The answer changes the state, which applies the location again.
            await cloudNotes.refresh()
        case .unavailable:
            // Settings says why; the notes on this Mac stay usable meanwhile.
            notesWatcher.stop()
            await notesStore.relocate(to: NotesRepository(
                notesDirectory: AppPaths.contentFolder(settings.notesFolder, named: "Notes")))
        case .available(let documents):
            await notesStore.relocate(to: NotesRepository(notesDirectory: documents))
            notesWatcher.start(directory: documents)
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

}
