import AppKit
import Sparkle

/// The updater's owner, and the menu's and Settings' way to reach it. See docs/features/updates.md.
@MainActor
@Observable
final class UpdateCoordinator: NSObject {
    /// Sparkle keeps this under its own `SUEnableAutomaticChecks` key, so it is not a `NotoSettings` key.
    var checksAutomatically = false {
        didSet { updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    /// Off while a check is already on screen; the menu item and Check Now follow it.
    private(set) var canCheckForUpdates = false
    /// The version a scheduled check found, named in the menu until the user looks at it.
    private(set) var pendingVersion: String?

    @ObservationIgnored private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private var updater: SPUUpdater { controller.updater }

    func start() {
        controller.startUpdater()
        checksAutomatically = updater.automaticallyChecksForUpdates
        // KVO hands the change to a Sendable closure; the hop back puts the write on the main actor.
        canCheckObservation = updater.observe(
            \.canCheckForUpdates, options: [.initial, .new]
        ) { [weak self] _, change in
            guard let canCheck = change.newValue else { return }
            Task { @MainActor in self?.canCheckForUpdates = canCheck }
        }
    }

    /// Starts a check, or brings the update already on screen to the front.
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

/// A menu-bar agent must not have a scheduled update steal focus; the menu carries the reminder.
extension UpdateCoordinator: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !state.userInitiated else { return }
        pendingVersion = update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        pendingVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingVersion = nil
    }
}
