import Foundation

struct NotesRepository: Sendable {
    typealias TrashOperation = @Sendable (URL) throws -> Void

    enum Failure: Error, LocalizedError, Sendable, Equatable {
        case invalidTitle(String)
        case unreadable(URL)
        case invalidLocation(URL)
        case io(fileURL: URL, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidTitle(let title):
                return "“\(title)” can't be used as a note title."
            case .unreadable(let fileURL):
                return "The note isn't valid UTF-8. (\(fileURL.deletingLastPathComponent().lastPathComponent))"
            case .invalidLocation(let fileURL):
                return "The note is outside the notes folder. (\(fileURL.path))"
            case .io(let fileURL, let message):
                return "Could not access \(fileURL.path): \(message)"
            }
        }
    }

    /// A note is a folder named for its title; this file inside it holds the Markdown.
    static let contentFileName = "text.md"

    let notesDirectory: URL
    private let trashOperation: TrashOperation

    init(
        notesDirectory: URL,
        trashOperation: @escaping TrashOperation = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        self.notesDirectory = notesDirectory
        self.trashOperation = trashOperation
    }

    func list() throws(Failure) -> [NoteSummary] {
        try mappedError(at: notesDirectory) {
            try ensureDirectory()
            let folderKeys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .isSymbolicLinkKey]
            let fileKeys: Set<URLResourceKey> = [
                .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey
            ]
            return try FileManager.default.contentsOfDirectory(
                at: notesDirectory,
                includingPropertiesForKeys: Array(folderKeys),
                options: [.skipsHiddenFiles]
            )
            // An unreadable entry is skipped: one bad folder must not hide the rest.
            .compactMap { folder -> NoteSummary? in
                guard let folderValues = try? folder.resourceValues(forKeys: folderKeys),
                    folderValues.isDirectory == true, folderValues.isSymbolicLink != true,
                    folderValues.isHidden != true,
                    let url = try? validatedFileURL(folder.appendingPathComponent(Self.contentFileName)),
                    let values = try? url.resourceValues(forKeys: fileKeys),
                    values.isRegularFile == true, values.isSymbolicLink != true
                else { return nil }
                let title = folder.lastPathComponent
                return NoteSummary(
                    id: NoteID(rawValue: title),
                    title: title,
                    firstLine: NoteTitle.isUnnamed(title) ? firstLine(of: url) : nil,
                    modifiedAt: values.contentModificationDate ?? .distantPast)
            }
            .sorted(by: summaryPrecedes)
        }
    }

    /// A `nil` document is an empty collection, not a failure: creating is always the user's move.
    func load(preferredID: NoteID?) throws(Failure) -> ([NoteSummary], NoteDocument?) {
        let summaries = try list()
        if let preferredID, summaries.contains(where: { $0.id == preferredID }) {
            return (summaries, try load(preferredID))
        }
        guard let first = summaries.first else { return (summaries, nil) }
        return (summaries, try load(first.id))
    }

    func load(_ id: NoteID) throws(Failure) -> NoteDocument {
        let candidate = fileURL(for: id)
        return try mappedError(at: candidate) {
            let url = try validatedFileURL(candidate)
            let data = try Data(contentsOf: url)
            guard let source = String(data: data, encoding: .utf8) else {
                throw Failure.unreadable(url)
            }
            return NoteDocument(id: NoteID(rawValue: url.deletingLastPathComponent().lastPathComponent), source: source)
        }
    }

    func create(title: String = "Untitled") throws(Failure) -> NoteDocument {
        try mappedError(at: notesDirectory) {
            let folder = try claimUniqueFolder(base: try validatedTitle(title)) {
                try createNoteFolder(at: $0, source: Data())
            }
            return try load(NoteID(rawValue: folder.lastPathComponent))
        }
    }

    /// One note as a backup carries it, before it has a file to live in.
    struct Incoming: Sendable, Equatable {
        let title: String
        let source: String
    }

    /// Beside the existing notes, never over them; an unusable title is skipped, not fatal.
    func importNotes(_ notes: [Incoming]) throws(Failure) -> Int {
        try mappedError(at: notesDirectory) {
            var imported = 0
            for note in notes {
                guard let base = try? validatedTitle(note.title) else { continue }
                _ = try claimUniqueFolder(base: base) {
                    try createNoteFolder(at: $0, source: Data(note.source.utf8))
                }
                imported += 1
            }
            return imported
        }
    }

    func save(id: NoteID, source: String) throws(Failure) {
        let candidate = fileURL(for: id)
        try mappedError(at: candidate) {
            let url = try validatedFileURL(candidate)
            let data = Data(source.utf8)
            try coordinatedWrite(at: url, options: .forReplacing) { coordinatedURL in
                try data.write(to: try validatedFileURL(coordinatedURL), options: .atomic)
            }
        }
    }

    func rename(id: NoteID, title: String) throws(Failure) -> NoteID {
        let candidate = folderURL(for: id)
        return try mappedError(at: candidate) {
            let sourceURL = try validatedFolderURL(candidate)
            let base = try validatedTitle(title)
            // Exact, not folded: a change of case or accents alone is a rename the user asked for.
            guard base != id.rawValue else { return id }
            let destination = try claimUniqueFolder(base: base, renaming: id) { destination in
                try coordinatedWrite(at: sourceURL, options: .forMoving) { coordinatedURL in
                    try FileManager.default.moveItem(
                        at: try validatedFolderURL(coordinatedURL), to: destination)
                }
            }
            return NoteID(rawValue: destination.lastPathComponent)
        }
    }

    func trash(id: NoteID) throws(Failure) {
        let candidate = folderURL(for: id)
        try mappedError(at: candidate) {
            let url = try validatedFolderURL(candidate)
            try coordinatedWrite(at: url, options: .forDeleting) { coordinatedURL in
                try trashOperation(try validatedFolderURL(coordinatedURL))
            }
        }
    }

    func search(
        _ query: NoteSearch.Query,
        summaries: [NoteSummary],
        limit: Int = 200
    ) -> [NoteSearchResult] {
        guard !query.isEmpty, limit > 0 else { return [] }
        var results: [NoteSearchResult] = []
        for summary in summaries {
            if Task.isCancelled { break }
            let source = try? load(summary.id).source
            if let result = NoteSearch.match(query: query, summary: summary, source: source) {
                results.append(result)
            }
        }
        return Array(results.sorted(by: NoteSearch.precedes).prefix(limit))
    }

    func folderURL(for id: NoteID) -> URL {
        notesDirectory.appendingPathComponent(id.rawValue, isDirectory: true)
    }

    func fileURL(for id: NoteID) -> URL {
        folderURL(for: id).appendingPathComponent(Self.contentFileName)
    }

    /// Only an unnamed note pays for this, and only for the head of its file.
    private func firstLine(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: NoteTitle.headByteCount), !head.isEmpty
        else { return nil }
        // A fixed-size read can land mid-character, so back off to the last complete one.
        for dropped in 0...3 where head.count > dropped {
            if let text = String(bytes: head.dropLast(dropped), encoding: .utf8) {
                return NoteTitle.firstLine(of: text)
            }
        }
        return nil
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: notesDirectory, withIntermediateDirectories: true)
    }

    /// Claims the first free `<base>`, `<base> 2`, … folder; a lost race only advances the suffix.
    private func claimUniqueFolder(
        base: String,
        renaming id: NoteID? = nil,
        _ claim: (URL) throws -> Void
    ) throws -> URL {
        let occupied = Set(try list().lazy.filter { $0.id != id }.map { folded($0.id.rawValue) })
        var suffix = 1
        while true {
            let candidate = uniqueCandidate(base: base, suffix: suffix)
            let name = folded(candidate.lastPathComponent)
            // A case-only rename collides with its own folder, which the move then replaces in place.
            let isSelf = id.map { name == folded($0.rawValue) } ?? false
            guard !occupied.contains(name),
                isSelf || !FileManager.default.fileExists(atPath: candidate.path)
            else {
                suffix += 1
                continue
            }
            do {
                try claim(candidate)
                return candidate
            } catch {
                guard !isSelf, FileManager.default.fileExists(atPath: candidate.path) else {
                    throw error
                }
                suffix += 1
            }
        }
    }

    /// The note folder itself: an immediate, unlinked child of the notes directory.
    private func validatedFolderURL(_ candidate: URL) throws -> URL {
        let standardized = candidate.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()
        let expectedParent = notesDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.deletingLastPathComponent().path == expectedParent.path,
            resolved.lastPathComponent == standardized.lastPathComponent,
            standardized.lastPathComponent == candidate.lastPathComponent
        else { throw Failure.invalidLocation(candidate) }
        return standardized
    }

    /// The content file: `text.md` directly inside a validated note folder.
    private func validatedFileURL(_ candidate: URL) throws -> URL {
        let standardized = candidate.standardizedFileURL
        let folder = try validatedFolderURL(standardized.deletingLastPathComponent())
        let resolved = standardized.resolvingSymlinksInPath()
        guard standardized.lastPathComponent == Self.contentFileName,
            resolved.deletingLastPathComponent().path == folder.resolvingSymlinksInPath().path
        else { throw Failure.invalidLocation(candidate) }
        return standardized
    }

    private func validatedTitle(_ raw: String) throws -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != ".", title != "..", !title.hasPrefix("."),
            !title.contains("/"), !title.contains("\0")
        else { throw Failure.invalidTitle(raw) }
        return title
    }

    private func uniqueCandidate(base: String, suffix: Int) -> URL {
        let suffixText = suffix == 1 ? "" : " \(suffix)"
        return notesDirectory.appendingPathComponent("\(base)\(suffixText)", isDirectory: true)
    }

    private func summaryPrecedes(_ lhs: NoteSummary, _ rhs: NoteSummary) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
    }

    private func folded(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The folder claim fails if it exists, which is what makes a lost race visible to the caller.
    private func createNoteFolder(at folder: URL, source: Data) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            try source.write(to: folder.appendingPathComponent(Self.contentFileName), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func coordinatedWrite<Value>(
        at fileURL: URL,
        options: NSFileCoordinator.WritingOptions,
        _ mutation: (URL) throws -> Value
    ) throws -> Value {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Value, Swift.Error>?
        coordinator.coordinate(
            writingItemAt: fileURL,
            options: options,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try mutation(coordinatedURL) }
        }
        if let result { return try result.get() }
        if let coordinationError { throw coordinationError }
        throw CocoaError(.fileWriteUnknown)
    }

    private func mappedError<Value>(
        at fileURL: URL,
        _ operation: () throws -> Value
    ) throws(Failure) -> Value {
        do {
            return try operation()
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .io(fileURL: fileURL, message: error.localizedDescription)
        }
    }
}
