import Foundation
import os

/// Watches the notes in iCloud for changes made on other devices. It downloads every note iCloud
/// holds without content, and reports notes with versions iCloud could not merge. A query sees a
/// `.noto` package as one item, never the files in it. See docs/features/sync.md.
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
        // A plain note folder still comes from a Mac with Noto 0.4 or earlier. Its `text.md` must
        // download, so that the next listing can migrate it into a package.
        query.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "%K ENDSWITH[c] %@", NSMetadataItemFSNameKey, ".\(NotesRepository.packageExtension)"),
            NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, NotesRepository.contentFileName),
        ])
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
            let package = NotesRepository.noteID(forPackage: url)
            // A package, or the `text.md` of a plain folder, directly inside the notes folder.
            let note = package == nil ? url.deletingLastPathComponent() : url
            guard note.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == root
            else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                } catch {
                    Logger.sync.error("could not download a note: \(error.localizedDescription, privacy: .public)")
                }
            }
            // Only a package resolves conflicts; a plain folder becomes a package first.
            if let package, item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool == true {
                conflicts.append(package)
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
