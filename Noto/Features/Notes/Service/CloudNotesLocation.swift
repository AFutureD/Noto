import Foundation
import os

/// Where iCloud keeps the notes: the `Documents` folder of the app's iCloud container, which Finder
/// shows as iCloud Drive › Noto. See docs/features/sync.md.
@MainActor
@Observable
final class CloudNotesLocation {
    enum State: Equatable, Sendable {
        /// Not asked yet.
        case unknown
        case available(URL)
        /// No iCloud account, or iCloud Drive is off.
        case unavailable
    }

    nonisolated static let containerIdentifier = "iCloud.app.huanan.noto"

    private(set) var state = State.unknown
    @ObservationIgnored private var identityObservation: NotificationToken?

    /// Asks again whenever the iCloud account changes.
    func start() {
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
        identityObservation = NotificationToken(token, center: center)
    }

    /// The container lookup can block while iCloud sets the container up, so it runs off-main.
    @discardableResult
    func refresh() async -> URL? {
        let documents = await Task.detached(priority: .userInitiated) { () -> URL? in
            // `NotesRepository` creates the folder on its first listing and reports a failure there.
            FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier)?
                .appending(path: "Documents", directoryHint: .isDirectory)
        }.value
        let updated = documents.map(State.available) ?? .unavailable
        if updated != state {
            Logger.sync.info("iCloud notes folder: \(String(describing: updated), privacy: .private)")
            state = updated
        }
        return documents
    }
}
