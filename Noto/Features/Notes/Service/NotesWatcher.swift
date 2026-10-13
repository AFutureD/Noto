import Foundation
import os

/// Watches the notes in iCloud for changes made on other devices. It downloads every note iCloud
/// holds without content, and reports notes with versions iCloud could not merge. See
/// docs/features/sync.md.
@MainActor
final class NotesWatcher {
    /// Called once a burst of changes settles, with the notes that have unresolved conflicts.
    var onChange: ([NoteID]) -> Void = { _ in }

    private var query: NSMetadataQuery?
    private var observations: [NotificationToken] = []
    private var settle: Task<Void, Never>?
    private var directory: URL?

    /// Watches the notes under `directory`, an iCloud container's `Documents` folder.
    func start(directory: URL) {
        guard directory != self.directory else { return }
        stop()
        self.directory = directory
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, NotesRepository.contentFileName)
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            let token = center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scan() }
            }
            observations.append(NotificationToken(token, center: center))
        }
        self.query = query
        query.start()
        Logger.sync.info("watching iCloud notes")
    }

    func stop() {
        query?.stop()
        query = nil
        observations = []
        settle?.cancel()
        settle = nil
        directory = nil
    }

    private func scan() {
        guard let query, let directory else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        var conflicts: [NoteID] = []
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let folder = url.deletingLastPathComponent()
            // Only `text.md` directly inside a note folder directly inside the notes folder.
            guard folder.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == root
            else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                } catch {
                    Logger.sync.error("could not download a note: \(error.localizedDescription, privacy: .public)")
                }
            }
            if item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool == true {
                conflicts.append(NoteID(rawValue: folder.lastPathComponent))
            }
        }
        settle?.cancel()
        settle = Task { [weak self] in
            // A sync lands as several updates; one reload after the last is enough.
            guard (try? await Task.sleep(for: .milliseconds(500))) != nil else { return }
            self?.onChange(conflicts)
        }
    }
}
