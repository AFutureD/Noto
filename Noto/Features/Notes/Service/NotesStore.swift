import Foundation
import os

@MainActor
@Observable
final class NotesStore {
    enum Issue: Sendable {
        case load(NotesRepository.Failure)
        case save(NotesRepository.Failure)
        case operation(NotesRepository.Failure)
    }

    private(set) var summaries: [NoteSummary] = []
    private(set) var activeID: NoteID?
    private(set) var source = ""
    private(set) var editorEpoch = 0
    private(set) var isDirty = false
    private(set) var isLoaded = false
    private(set) var searchQuery = ""
    private(set) var searchResults: [NoteSearchResult] = []
    private(set) var isSearching = false
    /// Derived from the live draft, not the last listing, so an unnamed note titles itself as typed.
    var activeTitle: String {
        guard let activeID else { return "Notes" }
        let title =
            summaries.first(where: { $0.id == activeID })?.title ?? activeID.rawValue
        guard NoteTitle.isUnnamed(title) else { return title }
        return NoteTitle.firstLine(of: source) ?? title
    }
    var activeFolderURL: URL? { activeID.map(repository.packageURL(for:)) }
    private(set) var notesDirectory: URL
    var onIssue: ((Issue) -> Void)?

    private var repository: NotesRepository
    private let loadSelection: @Sendable () -> NoteID?
    private let saveSelection: @Sendable (NoteID?) -> Void
    @ObservationIgnored private var saveDebounce: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchWorker: Task<[NoteSearchResult], Never>?
    private var saveFailed = false
    /// A folder change that waits on a draft the old folder could not take yet.
    @ObservationIgnored private var pendingRelocation: NotesRepository?
    private var searchGeneration = 0
    @ObservationIgnored private var sourceRevision = 0
    /// The file's content as this store last read or wrote it; a save that finds anything else
    /// on disk keeps that as a conflict copy.
    @ObservationIgnored private var baseSource = ""
    /// The texts the active note's editing session started from: the load, and each reload of the
    /// same note, also after a restore in the version browser. An image one of them names, and the session's text drops, goes.
    @ObservationIgnored private var sessionSources: [String] = []
    /// The image files the session imported, by name.
    @ObservationIgnored private var sessionImports: Set<String> = []
    /// When the session last added a version; nil before its first save.
    @ObservationIgnored private var lastSnapshot: Date?
    @ObservationIgnored private var migrationTask: Task<Void, Never>?
    @ObservationIgnored private var reportedMigrationFailures: [String] = []
    private let now: @Sendable () -> Date

    /// A note outside iCloud gets a version at most this often while the user types.
    static let snapshotInterval: TimeInterval = 10 * 60
    /// The version browser opens with the iCloud server versions of this period downloaded…
    static let serverVersionPeriod: TimeInterval = 3 * 24 * 60 * 60
    /// …as far as this wait allows; the rest show Load Version.
    static let serverVersionWait: TimeInterval = 10

    init(
        repository: NotesRepository,
        loadSelection: @escaping @Sendable () -> NoteID? = { nil },
        saveSelection: @escaping @Sendable (NoteID?) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.loadSelection = loadSelection
        self.saveSelection = saveSelection
        self.now = now
        notesDirectory = repository.notesDirectory
    }

    isolated deinit {
        saveDebounce?.cancel()
        searchTask?.cancel()
        searchWorker?.cancel()
    }

    func start() async -> Bool {
        if let saveTask { await saveTask.value }
        return await reload()
    }

    /// Moves to another folder once the open draft is saved where it was, then the new one lists.
    func relocate(to repository: NotesRepository) async {
        pendingRelocation = nil
        guard repository.notesDirectory != notesDirectory else { return }
        guard await flush() else {
            pendingRelocation = repository
            return
        }
        await endSession()
        cancelSearch()
        self.repository = repository
        notesDirectory = repository.notesDirectory
        guard isLoaded else { return }
        // Cleared first, so a folder that fails to load leaves no old note to save into it.
        apply(nil, summaries: [])
        _ = await reload(preferredID: nil)
    }

    func reload() async -> Bool {
        await reload(preferredID: activeID ?? loadSelection())
    }

    func updateSource(_ updated: String) {
        guard activeID != nil, updated != source else { return }
        source = updated
        sourceRevision &+= 1
        isDirty = true
        saveFailed = false
        scheduleSave()
    }

    @discardableResult
    func retrySave() async -> Bool {
        saveFailed = false
        return await flush()
    }

    /// The one place a write starts, so a debounced save and a flush can never overlap on one file.
    @discardableResult
    func flush() async -> Bool {
        saveDebounce?.cancel()
        saveDebounce = nil
        // Two rounds: one for a write already in flight, one for an edit that landed while it ran.
        for _ in 0..<2 {
            if let saveTask {
                await saveTask.value
                continue
            }
            guard isDirty, !saveFailed else { break }
            let task = Task { [weak self] in
                await self?.write()
                self?.saveTask = nil
            }
            saveTask = task
            await task.value
        }
        return !isDirty
    }

    /// Quit: the draft reaches disk, and the session's dropped images go.
    func finish() async {
        guard await flush() else { return }
        await endSession()
    }

    @discardableResult
    func create() async -> Bool {
        guard await flush() else { return false }
        await endSession()
        await migrateLegacyNotes()
        cancelSearch()
        let repository = repository
        let result = await detached {
            let document = try repository.create()
            return (document, try repository.list())
        } recover: {
            repository.notesDirectory
        }
        switch result {
        case .success(let payload):
            apply(payload.0, summaries: payload.1)
            return true
        case .failure(let failure):
            publish(.operation(failure))
            return false
        }
    }

    /// Writes imported notes as new files and re-lists, leaving the open draft where it was.
    func importNotes(_ notes: [NotesRepository.Incoming]) async -> Int {
        guard !notes.isEmpty else { return 0 }
        let repository = repository
        let result = await detached {
            (try repository.importNotes(notes), try repository.list())
        } recover: {
            repository.notesDirectory
        }
        switch result {
        case .success(let payload):
            summaries = payload.1
            return payload.0
        case .failure(let failure):
            publish(.operation(failure))
            return 0
        }
    }

    /// Copies the notes of another folder in, leaving the open draft where it was.
    func copyNotes(from other: NotesRepository) async -> Int {
        let repository = repository
        let result = await detached {
            // The other folder can still hold plain folders; only packages copy.
            _ = other.migrateLegacyNotes()
            return (try repository.copyNotes(from: other), try repository.list())
        } recover: {
            other.notesDirectory
        }
        switch result {
        case .success(let payload):
            summaries = payload.1
            return payload.0
        case .failure(let failure):
            publish(.operation(failure))
            return 0
        }
    }

    /// Keeps the versions iCloud could not merge as conflict copies, then lists and reloads.
    func resolveConflicts(_ ids: [NoteID]) async {
        guard !ids.isEmpty else { return }
        let repository = repository
        let result = await detached {
            for id in ids { _ = try repository.resolveConflicts(id: id) }
        } recover: {
            repository.notesDirectory
        }
        if case .failure(let failure) = result { publish(.operation(failure)) }
        // A store that has not loaded yet lists when the window first shows.
        guard isLoaded else { return }
        _ = await reload()
    }

    /// Copies files into the active note's assets. Nil means nothing to insert: no active note, a
    /// different note by the time the copy lands, or a failure, which is reported.
    func importAssets(_ files: [URL], into id: NoteID) async -> [String]? {
        guard !files.isEmpty, id == activeID else { return nil }
        let repository = repository
        let result = await detached {
            try repository.importAssets(files, into: id)
        } recover: {
            repository.packageURL(for: id)
        }
        switch result {
        case .success(let paths):
            guard id == activeID else { return nil }
            sessionImports.formUnion(paths.map { URL(fileURLWithPath: $0).lastPathComponent })
            return paths
        case .failure(let failure):
            publish(.operation(failure))
            return nil
        }
    }

    @discardableResult
    func select(
        _ id: NoteID,
        permitsApply: @MainActor () -> Bool = { true }
    ) async -> Bool {
        guard id != activeID else { return true }
        guard await flush() else { return false }
        guard permitsApply() else { return false }
        await endSession()
        cancelSearch()
        let repository = repository
        let result = await detached {
            try repository.load(id)
        } recover: {
            repository.fileURL(for: id)
        }
        guard permitsApply(), !Task.isCancelled else { return false }
        switch result {
        case .success(let document):
            apply(document, summaries: summaries)
            return true
        case .failure(let failure):
            publish(.load(failure))
            return false
        }
    }

    @discardableResult
    func rename(_ id: NoteID, to title: String) async -> NoteID? {
        guard await flush() else { return nil }
        cancelSearch()
        let repository = repository
        let result = await detached {
            let renamed = try repository.rename(id: id, title: title)
            return (renamed, try repository.list())
        } recover: {
            repository.fileURL(for: id)
        }
        switch result {
        case .success(let payload):
            summaries = payload.1
            if id == activeID {
                activeID = payload.0
                saveSelection(payload.0)
            }
            return payload.0
        case .failure(let failure):
            publish(.operation(failure))
            return nil
        }
    }

    @discardableResult
    func trash(_ id: NoteID) async -> Bool {
        guard await flush() else { return false }
        let repository = repository
        let replacesActive = id == activeID
        let result = await detached {
            try repository.trash(id: id)
            let summaries = try repository.list()
            let successor = replacesActive ? summaries.first : nil
            return (try successor.map { try repository.load($0.id) }, summaries)
        } recover: {
            repository.fileURL(for: id)
        }
        switch result {
        case .success(let payload):
            cancelSearch()
            // An empty collection is a legal resting state; only creating brings a note back.
            if replacesActive {
                apply(payload.0, summaries: payload.1)
            } else {
                summaries = payload.1
            }
            return true
        case .failure(let failure):
            publish(.operation(failure))
            return false
        }
    }

    func updateSearchQuery(_ updated: String) {
        searchQuery = updated
        searchTask?.cancel()
        searchWorker?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        let query = NoteSearch.Query(updated)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            searchTask = nil
            searchWorker = nil
            return
        }
        isSearching = true
        // The previous query's rows must not linger under the new query text.
        searchResults = []
        let repository = repository
        let summaries = summaries
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                Signposts.interval("Notes.search") {
                    repository.search(query, summaries: summaries)
                }
            }
            self.searchWorker = worker
            let results = await worker.value
            guard !Task.isCancelled, generation == self.searchGeneration else { return }
            self.searchResults = results
            self.isSearching = false
            self.searchWorker = nil
            self.searchTask = nil
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchWorker?.cancel()
        searchWorker = nil
        searchGeneration &+= 1
        searchQuery = ""
        searchResults = []
        isSearching = false
    }

    /// Never cancels an in-flight write; every caller flushes first.
    func stop() {
        saveDebounce?.cancel()
        saveDebounce = nil
        cancelSearch()
    }

    private func reload(preferredID: NoteID?) async -> Bool {
        await migrateLegacyNotes()
        let repository = repository
        let selectedID = activeID
        let epoch = editorEpoch
        let revision = sourceRevision
        let reloadSource = !isDirty
        let result = await detached {
            if reloadSource { return try repository.load(preferredID: preferredID) }
            return (try repository.list(), nil)
        } recover: {
            repository.notesDirectory
        }
        guard !Task.isCancelled else { return false }
        guard repository.notesDirectory == notesDirectory, selectedID == activeID,
            epoch == editorEpoch, revision == sourceRevision
        else { return true }
        switch result {
        case .success(let (summaries, document)):
            if reloadSource, !isDirty, saveTask == nil,
                !isLoaded || document?.id != activeID || (document?.source ?? "") != source
            {
                apply(document, summaries: summaries)
            } else {
                self.summaries = summaries
            }
            return true
        case .failure(let failure):
            publish(.load(failure))
            // Only a first load may keep the window shut; a loaded store can still show its draft.
            return isLoaded
        }
    }

    private func scheduleSave() {
        saveDebounce?.cancel()
        saveDebounce = Task { [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(300))) != nil, let self else { return }
            saveDebounce = nil
            await flush()
        }
    }

    private func write() async {
        guard isDirty, let activeID else { return }
        let savedSource = source
        let base = baseSource
        // An edit that came back to the text on disk writes nothing; in iCloud a write would upload
        // the same note again, and the server would keep it as one more version.
        guard savedSource != base else {
            isDirty = false
            if let pending = pendingRelocation {
                Task { [weak self] in await self?.relocate(to: pending) }
            }
            return
        }
        let repository = repository
        // The first save of a session keeps the note as it was opened; later ones, one version each
        // interval. In iCloud the server keeps a version of each upload, so Noto adds none there.
        let snapshots = !base.isEmpty
            && (lastSnapshot.map { now().timeIntervalSince($0) >= Self.snapshotInterval } ?? true)
        if snapshots { lastSnapshot = now() }
        let result = await detached {
            if snapshots {
                do {
                    try repository.snapshot(id: activeID, onlyOutsideICloud: true)
                } catch {
                    Logger.notes.error(
                        "could not add a version before a save: \(error.localizedDescription, privacy: .public)")
                }
            }
            try repository.save(id: activeID, source: savedSource, base: base)
            return try repository.list()
        } recover: {
            repository.fileURL(for: activeID)
        }
        switch result {
        case .success(let summaries):
            self.summaries = summaries
            if activeID == self.activeID { baseSource = savedSource }
            isDirty = savedSource != source
            if !isDirty, let pending = pendingRelocation {
                Task { [weak self] in await self?.relocate(to: pending) }
            }
        case .failure(let failure):
            saveFailed = true
            publish(.save(failure))
        }
    }

    private func apply(_ document: NoteDocument?, summaries: [NoteSummary]) {
        self.summaries = summaries
        if document?.id != activeID {
            sessionSources = []
            sessionImports = []
            lastSnapshot = nil
        }
        if let document { sessionSources.append(document.source) }
        activeID = document?.id
        source = document?.source ?? ""
        baseSource = source
        editorEpoch &+= 1
        isDirty = false
        saveFailed = false
        isLoaded = true
        saveSelection(document?.id)
    }

    private func publish(_ issue: Issue) {
        onIssue?(issue)
    }

    /// Downloads the recent iCloud server versions of the active note before the version browser
    /// opens, so they show without Load Version. Nothing happens outside iCloud.
    func downloadRecentServerVersions() async {
        guard let id = activeID else { return }
        let repository = repository
        let since = now().addingTimeInterval(-Self.serverVersionPeriod)
        let deadline = now().addingTimeInterval(Self.serverVersionWait)
        _ = await Task.detached(priority: .userInitiated) {
            await repository.downloadServerVersions(of: id, since: since, until: deadline)
        }.value
    }

    // MARK: - Sessions and migration

    /// Deletes the images the ending session dropped. It runs as the one write in flight, after the
    /// draft is saved, so it reads the text that the session leaves on disk.
    private func endSession() async {
        guard let id = activeID,
            !sessionImports.isEmpty || sessionSources.contains(where: { $0.contains("\(NoteAssets.folderName)/") })
        else { return }
        let earlier = sessionSources
        let imported = sessionImports
        let repository = repository
        let result = await serialized { [weak self] in
            await self?.detached {
                try repository.removeDroppedAssets(of: id, earlier: earlier, imported: imported)
            } recover: {
                repository.packageURL(for: id)
            } ?? .success([])
        }
        if case .failure(let failure) = result {
            // The images stay; a later session can drop them again.
            Logger.notes.error(
                "could not delete the dropped images: \(failure.localizedDescription, privacy: .public)")
        }
    }

    /// One migration at a time; a caller that comes during one waits for it. Each listing runs one,
    /// because a Mac with an older Noto can still add a plain note folder to iCloud.
    private func migrateLegacyNotes() async {
        if let migrationTask {
            await migrationTask.value
            return
        }
        let repository = repository
        let task = Task { [weak self] in
            let report = await Task.detached(priority: .utility) { repository.migrateLegacyNotes() }.value
            guard let self else { return }
            // A failure shows once, not at each listing.
            if !report.failed.isEmpty, report.failed != reportedMigrationFailures {
                publish(.operation(.notMigrated(report.failed)))
            }
            reportedMigrationFailures = report.failed
        }
        migrationTask = task
        await task.value
        migrationTask = nil
    }

    /// Runs `work` as the one write in flight, after the write before it. Each write task clears
    /// `saveTask` as its last step, so `flush` and this never overlap on one note.
    private func serialized<Value: Sendable>(_ work: @escaping @MainActor () async -> Value) async -> Value {
        while let pending = saveTask { await pending.value }
        let task = Task { await work() }
        saveTask = Task { [weak self] in
            _ = await task.value
            self?.saveTask = nil
        }
        return await task.value
    }

    /// Every repository call is blocking IO, so it runs off-main and reports one typed failure.
    private func detached<Value: Sendable>(
        _ work: @escaping @Sendable () throws -> Value,
        recover fileURL: @escaping @Sendable () -> URL
    ) async -> Result<Value, NotesRepository.Failure> {
        await Task.detached(priority: .utility) {
            do {
                return .success(try work())
            } catch let failure as NotesRepository.Failure {
                return .failure(failure)
            } catch {
                return .failure(.io(fileURL: fileURL(), message: error.localizedDescription))
            }
        }.value
    }
}
