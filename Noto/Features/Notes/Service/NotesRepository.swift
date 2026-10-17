import Foundation
import os

struct NotesRepository: Sendable {
    typealias TrashOperation = @Sendable (URL) throws -> Void

    enum Failure: Error, LocalizedError, Sendable, Equatable {
        case invalidTitle(String)
        case unreadable(URL)
        case invalidLocation(URL)
        case io(fileURL: URL, message: String)
        /// Plain note folders that could not become packages. They stay where they are.
        case notMigrated([String])

        var errorDescription: String? {
            switch self {
            case .invalidTitle(let title):
                return "“\(title)” can't be used as a note title."
            case .unreadable(let fileURL):
                let title = fileURL.deletingLastPathComponent().deletingPathExtension().lastPathComponent
                return "The note isn't valid UTF-8. (\(title))"
            case .invalidLocation(let fileURL):
                return "The note is outside the notes folder. (\(fileURL.path))"
            case .io(let fileURL, let message):
                return "Could not access \(fileURL.path): \(message)"
            case .notMigrated(let names):
                let list = names.map { "“\($0)”" }.joined(separator: ", ")
                return "Noto could not change these notes to the new format: \(list). "
                    + "They stay in the notes folder, and Noto tries again the next time it lists the folder."
            }
        }
    }

    /// What one migration did: the folders that became packages, the folders that wait for iCloud,
    /// and the folders that failed.
    struct MigrationReport: Sendable, Equatable {
        var migrated: [NoteID] = []
        var deferred: [String] = []
        var failed: [String] = []
    }

    /// A note is a `<title>.noto` package; this file inside it holds the Markdown.
    static let contentFileName = "text.md"
    /// The package extension. `Info.plist` declares it as `app.huanan.noto.note`, a `com.apple.package`,
    /// so Finder shows one item and iCloud keeps versions of the whole note.
    static let packageExtension = "noto"

    /// The note a package URL names, or nil when the URL is not a `.noto` package.
    static func noteID(forPackage url: URL) -> NoteID? {
        guard url.pathExtension == packageExtension else { return nil }
        let title = url.deletingPathExtension().lastPathComponent
        return title.isEmpty ? nil : NoteID(rawValue: title)
    }

    let notesDirectory: URL
    private let trashOperation: TrashOperation
    private let now: @Sendable () -> Date

    init(
        notesDirectory: URL,
        trashOperation: @escaping TrashOperation = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.notesDirectory = notesDirectory
        self.trashOperation = trashOperation
        self.now = now
    }

    func packageURL(for id: NoteID) -> URL {
        notesDirectory.appendingPathComponent("\(id.rawValue).\(Self.packageExtension)", isDirectory: true)
    }

    func fileURL(for id: NoteID) -> URL {
        packageURL(for: id).appendingPathComponent(Self.contentFileName)
    }

    // MARK: - The collection

    func list() throws(Failure) -> [NoteSummary] {
        try mappedError(at: notesDirectory) {
            try ensureDirectory()
            let packageKeys: Set<URLResourceKey> = [
                .isDirectoryKey, .isHiddenKey, .isSymbolicLinkKey, .contentModificationDateKey,
                .ubiquitousItemDownloadingStatusKey,
            ]
            let fileKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
            return try FileManager.default.contentsOfDirectory(
                at: notesDirectory,
                includingPropertiesForKeys: Array(packageKeys),
                options: [.skipsHiddenFiles]
            )
            // An unreadable entry is skipped: one bad package must not hide the rest.
            .compactMap { package -> NoteSummary? in
                guard let id = Self.noteID(forPackage: package),
                    let values = try? package.resourceValues(forKeys: packageKeys),
                    values.isDirectory == true, values.isSymbolicLink != true, values.isHidden != true
                else { return nil }
                // A package iCloud has not downloaded yet: a read inside it would wait for the
                // download, so it lists by the package alone until it arrives.
                guard Self.isLocal(values) else {
                    return NoteSummary(
                        id: id, title: id.rawValue, firstLine: nil,
                        modifiedAt: values.contentModificationDate ?? .distantPast)
                }
                guard let url = try? validatedFileURL(package.appendingPathComponent(Self.contentFileName)),
                    let file = try? url.resourceValues(forKeys: fileKeys),
                    file.isRegularFile == true, file.isSymbolicLink != true
                else { return nil }
                return NoteSummary(
                    id: id,
                    title: id.rawValue,
                    firstLine: NoteTitle.isUnnamed(id.rawValue) ? firstLine(of: url) : nil,
                    modifiedAt: file.contentModificationDate ?? .distantPast)
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
            let source = try coordinatedRead(at: url) { try Self.source(at: try validatedFileURL($0)) }
            return NoteDocument(id: id, source: source)
        }
    }

    func create(title: String = "Untitled") throws(Failure) -> NoteDocument {
        try mappedError(at: notesDirectory) {
            let id = try claimUniqueNote(base: try validatedTitle(title)) {
                try createPackage(at: $0, source: Data())
            }
            return try load(id)
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
                _ = try claimUniqueNote(base: base) {
                    try createPackage(at: $0, source: Data(note.source.utf8))
                }
                imported += 1
            }
            return imported
        }
    }

    /// Writes `source` over the file `base` was read from. A file that no longer holds `base` was
    /// changed elsewhere, so its content is kept as a conflict copy before the write; the returned id
    /// names it. A package that was renamed or deleted elsewhere is created again, so the draft lands.
    @discardableResult
    func save(id: NoteID, source: String, base: String) throws(Failure) -> NoteID? {
        let candidate = fileURL(for: id)
        return try mappedError(at: candidate) {
            let url = try validatedFileURL(candidate)
            let data = Data(source.utf8)
            return try coordinatedReplace(at: url) { coordinatedURL in
                let fileURL = try validatedFileURL(coordinatedURL)
                let disk = FileManager.default.fileExists(atPath: fileURL.path)
                    ? try Self.source(at: fileURL) : nil
                // The copy lands first: if it fails, the write does not happen and nothing is lost.
                var copy: NoteID?
                if let disk, disk != base, disk != source {
                    copy = try keepConflictCopy(of: id, source: disk, imagesFrom: packageURL(for: id))
                }
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: fileURL, options: .atomic)
                return copy
            }
        }
    }

    /// Keeps every version iCloud could not merge as a conflict copy, with that version's own
    /// images, then marks it resolved. The versions stay in the version store: they are the history.
    func resolveConflicts(id: NoteID) throws(Failure) -> [NoteID] {
        let candidate = packageURL(for: id)
        return try mappedError(at: candidate) {
            let url = try validatedPackageURL(candidate)
            return try coordinatedWrite(at: url, options: []) { coordinatedURL in
                let package = try validatedPackageURL(coordinatedURL)
                var copies: [NoteID] = []
                for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: package) ?? [] {
                    let source = try Self.source(at: version.url.appendingPathComponent(Self.contentFileName))
                    // A copy that fails leaves the version unresolved, so the next report tries again.
                    copies.append(try keepConflictCopy(of: id, source: source, imagesFrom: version.url))
                    version.isResolved = true
                }
                return copies
            }
        }
    }

    /// Copies every note of `other` in beside the existing ones. A note with the same title and the
    /// same text is already here and is skipped; any other collision takes the next free name.
    func copyNotes(from other: NotesRepository) throws(Failure) -> Int {
        try mappedError(at: other.notesDirectory) {
            let existing = Dictionary(
                try list().map { (folded($0.id.rawValue), $0.id) }, uniquingKeysWith: { first, _ in first })
            var copied = 0
            for summary in try other.list() {
                let source = try other.load(summary.id).source
                if let twin = existing[folded(summary.id.rawValue)], (try? load(twin).source) == source {
                    continue
                }
                // The images copy inside the claim: if they fail, the package goes, so a retry copies
                // this note again instead of skipping it as already there.
                let id = try claimUniqueNote(base: summary.id.rawValue) { package in
                    try createPackage(at: package, source: Data(source.utf8))
                    do {
                        try copyAssets(from: other.packageURL(for: summary.id), to: package)
                    } catch {
                        try? FileManager.default.removeItem(at: package)
                        throw error
                    }
                }
                // The copy keeps its place in the modification-date order.
                try? FileManager.default.setAttributes(
                    [.modificationDate: summary.modifiedAt], ofItemAtPath: fileURL(for: id).path)
                copied += 1
            }
            return copied
        }
    }

    func rename(id: NoteID, title: String) throws(Failure) -> NoteID {
        let candidate = packageURL(for: id)
        return try mappedError(at: candidate) {
            let sourceURL = try validatedPackageURL(candidate)
            let base = try validatedTitle(title)
            // Exact, not folded: a change of case or accents alone is a rename the user asked for.
            guard base != id.rawValue else { return id }
            return try claimUniqueNote(base: base, renaming: id) { destination in
                try coordinatedWrite(at: sourceURL, options: .forMoving) { coordinatedURL in
                    try FileManager.default.moveItem(
                        at: try validatedPackageURL(coordinatedURL), to: destination)
                }
            }
        }
    }

    func trash(id: NoteID) throws(Failure) {
        let candidate = packageURL(for: id)
        try mappedError(at: candidate) {
            let url = try validatedPackageURL(candidate)
            try coordinatedWrite(at: url, options: .forDeleting) { coordinatedURL in
                try trashOperation(try validatedPackageURL(coordinatedURL))
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
            // A note iCloud has not downloaded yet matches by title until it arrives.
            let source = Self.isLocal(at: packageURL(for: summary.id)) ? try? load(summary.id).source : nil
            if let result = NoteSearch.match(query: query, summary: summary, source: source) {
                results.append(result)
            }
        }
        return Array(results.sorted(by: NoteSearch.precedes).prefix(limit))
    }

    // MARK: - Images

    /// Copies each file into the note's `assets` folder under a free name and returns the paths
    /// relative to the package, in order. The originals stay where they are.
    func importAssets(_ files: [URL], into id: NoteID) throws(Failure) -> [String] {
        let candidate = packageURL(for: id)
        return try mappedError(at: candidate) {
            let package = try validatedPackageURL(candidate)
            let assets = package.appendingPathComponent(NoteAssets.folderName, isDirectory: true)
            // A link would write the copies somewhere outside the note.
            if (try? assets.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                throw Failure.invalidLocation(assets)
            }
            return try coordinatedWrite(at: assets, options: []) { coordinatedURL in
                try FileManager.default.createDirectory(at: coordinatedURL, withIntermediateDirectories: true)
                var taken = Set(try FileManager.default.contentsOfDirectory(atPath: coordinatedURL.path))
                return try files.map { file in
                    let base = NoteAssets.isPasted(file)
                        ? NoteAssets.pastedName(for: file.lastPathComponent, at: now()) : file.lastPathComponent
                    let name = NoteAssets.uniqueName(for: base, taken: taken)
                    try FileManager.default.copyItem(at: file, to: coordinatedURL.appendingPathComponent(name))
                    taken.insert(name)
                    Logger.notes.info("imported an asset into \(id.rawValue, privacy: .private)")
                    return "\(NoteAssets.folderName)/\(name)"
                }
            }
        }
    }

    /// Deletes the images that one editing session dropped: a file in `assets` that one of
    /// `earlier` (the texts the session started from) names, or that the session imported, and that
    /// the text on disk no longer names. Any other file stays, also one that iCloud brought before
    /// its text, or one the user put there. A version of the whole note comes first; without it
    /// nothing is deleted. Returns the deleted names.
    func removeDroppedAssets(of id: NoteID, earlier: [String], imported: Set<String>) throws(Failure) -> [String] {
        let candidate = packageURL(for: id)
        return try mappedError(at: candidate) {
            let url = try validatedPackageURL(candidate)
            guard FileManager.default.fileExists(atPath: url.path), Self.isLocal(at: url) else { return [] }
            return try coordinatedWrite(at: url, options: []) { coordinatedURL in
                let package = try validatedPackageURL(coordinatedURL)
                let text = package.appendingPathComponent(Self.contentFileName)
                let assets = package.appendingPathComponent(NoteAssets.folderName, isDirectory: true)
                let folder = try? assets.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard FileManager.default.fileExists(atPath: text.path),
                    folder?.isDirectory == true, folder?.isSymbolicLink != true
                else { return [] }
                let disk = try Self.source(at: text)
                let dropped = try FileManager.default.contentsOfDirectory(
                    at: assets, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
                )
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
                .map(\.lastPathComponent)
                .filter { name in
                    let named = imported.contains(name) || earlier.contains { NoteAssets.isReferenced(name, in: $0) }
                    return named && !NoteAssets.isReferenced(name, in: disk)
                }
                .sorted()
                guard !dropped.isEmpty else { return [] }
                try addVersionIfChanged(of: package)
                for name in dropped {
                    try FileManager.default.removeItem(at: assets.appendingPathComponent(name))
                }
                Logger.notes.notice(
                    "deleted \(dropped.count, privacy: .public) images that \(id.rawValue, privacy: .private) no longer shows")
                return dropped
            }
        }
    }

    // MARK: - Versions

    /// Adds the note as it is now to the version store, which the system version browser shows, unless
    /// the newest version already holds it. With `onlyOutsideICloud`, a note in iCloud is skipped: the
    /// server keeps a version of each upload.
    func snapshot(id: NoteID, onlyOutsideICloud: Bool = false) throws(Failure) {
        let candidate = packageURL(for: id)
        try mappedError(at: candidate) {
            let url = try validatedPackageURL(candidate)
            if onlyOutsideICloud, Self.isInICloud(url) { return }
            let added = try coordinatedRead(at: url) { coordinatedURL in
                try addVersionIfChanged(of: try validatedPackageURL(coordinatedURL))
            }
            if added { Logger.notes.info("added a version of \(id.rawValue, privacy: .private)") }
        }
    }

    /// Downloads the iCloud server versions of a note saved since `since`, newest first, until
    /// `deadline`. The version browser shows a downloaded version at once; one still on the server
    /// shows Load Version. A failure is logged and skipped: the browser opens anyway. Returns how
    /// many versions downloaded.
    func downloadServerVersions(of id: NoteID, since: Date, until deadline: Date) async -> Int {
        let candidate = packageURL(for: id)
        guard let url = try? validatedPackageURL(candidate), Self.isInICloud(url) else { return 0 }
        let server: [NSFileVersion]
        do {
            server = try await NSFileVersion.nonlocalVersionsOfItem(at: url)
        } catch {
            Logger.sync.error("could not list the iCloud versions: \(error.localizedDescription, privacy: .public)")
            return 0
        }
        let recent = server
            .filter { ($0.modificationDate ?? .distantPast) >= since }
            .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        var downloaded = 0
        for version in recent {
            guard now() < deadline else { break }
            do {
                // A coordinated read of a server version's URL downloads it.
                try coordinatedRead(at: version.url) { _ in }
                downloaded += 1
            } catch {
                Logger.sync.error("could not download an iCloud version: \(error.localizedDescription, privacy: .public)")
            }
        }
        Logger.sync.info(
            "downloaded \(downloaded, privacy: .public) of \(recent.count, privacy: .public) recent iCloud versions")
        return downloaded
    }

    /// Adds a version of the package, unless the newest local version holds the same note: the same
    /// `text.md` and the same image files. Returns whether it added one.
    @discardableResult
    private func addVersionIfChanged(of package: URL) throws -> Bool {
        let newest = (NSFileVersion.otherVersionsOfItem(at: package) ?? [])
            .max { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
        if let newest, Self.holdSameNote(newest.url, package) { return false }
        _ = try NSFileVersion.addOfItem(at: package, withContentsOf: package)
        return true
    }

    /// The same text and the same files in `assets`, byte for byte. A doubt counts as a difference,
    /// so a version is never skipped by mistake.
    static func holdSameNote(_ lhs: URL, _ rhs: URL) -> Bool {
        let fm = FileManager.default
        guard fm.contentsEqual(
            atPath: lhs.appendingPathComponent(contentFileName).path,
            andPath: rhs.appendingPathComponent(contentFileName).path)
        else { return false }
        func files(_ package: URL) -> [String] {
            let assets = package.appendingPathComponent(NoteAssets.folderName, isDirectory: true)
            return ((try? fm.subpathsOfDirectory(atPath: assets.path)) ?? []).sorted()
        }
        let names = files(lhs)
        guard names == files(rhs) else { return false }
        return names.allSatisfy { name in
            fm.contentsEqual(
                atPath: lhs.appendingPathComponent(NoteAssets.folderName).appendingPathComponent(name).path,
                andPath: rhs.appendingPathComponent(NoteAssets.folderName).appendingPathComponent(name).path)
        }
    }

    // MARK: - Migration

    /// Turns each plain note folder (`<title>/text.md`, the format of Noto 0.4 and earlier) into a
    /// `<title>.noto` package. Outside iCloud, a rename does it. In iCloud a rename leaves the server
    /// with a folder, which keeps no versions, so the package is built in a temporary folder and
    /// moved in, and the old folder goes to the Trash. A folder that iCloud has not downloaded waits.
    func migrateLegacyNotes() -> MigrationReport {
        var report = MigrationReport()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: notesDirectory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        else { return report }
        for folder in entries where Self.noteID(forPackage: folder) == nil {
            guard let values = try? folder.resourceValues(forKeys: keys),
                values.isDirectory == true, values.isSymbolicLink != true, values.isHidden != true,
                let file = try? folder.appendingPathComponent(Self.contentFileName)
                    .resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                file.isRegularFile == true, file.isSymbolicLink != true,
                (try? validatedTitle(folder.lastPathComponent)) != nil
            else { continue }
            let name = folder.lastPathComponent
            do {
                if Self.isDownloaded(folder), let id = try migrate(folder) {
                    report.migrated.append(id)
                } else {
                    report.deferred.append(name)
                }
            } catch {
                report.failed.append(name)
                Logger.notes.error(
                    "could not change \(name, privacy: .private) to a package: \(error.localizedDescription, privacy: .public)")
            }
        }
        if !report.migrated.isEmpty || !report.failed.isEmpty {
            let (migrated, failed, deferred) = (report.migrated.count, report.failed.count, report.deferred.count)
            Logger.notes.notice(
                "migrated \(migrated, privacy: .public), failed \(failed, privacy: .public), wait \(deferred, privacy: .public)")
        }
        return report
    }

    /// Nil when the note must wait: a package of the same name is not downloaded yet.
    private func migrate(_ folder: URL) throws -> NoteID? {
        let title = folder.lastPathComponent
        let source = try coordinatedRead(at: folder) { try Self.source(at: $0.appendingPathComponent(Self.contentFileName)) }
        // Another Mac can have done this already. Its package has the same text.
        let existing = packageURL(for: NoteID(rawValue: title))
        if FileManager.default.fileExists(atPath: existing.path) {
            guard Self.isLocal(at: existing) else { return nil }
            if (try? load(NoteID(rawValue: title)).source) == source {
                try coordinatedWrite(at: folder, options: .forDeleting) { try trashOperation($0) }
                return NoteID(rawValue: title)
            }
        }
        guard Self.isInICloud(folder) else {
            return try claimUniqueNote(base: title) { destination in
                try coordinatedWrite(at: folder, options: .forMoving) { coordinatedURL in
                    try FileManager.default.moveItem(at: coordinatedURL, to: destination)
                }
            }
        }
        let staging = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: notesDirectory, create: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let built = staging.appendingPathComponent("\(UUID().uuidString).\(Self.packageExtension)", isDirectory: true)
        let modified = try coordinatedRead(at: folder) { coordinatedURL in
            try FileManager.default.copyItem(at: coordinatedURL, to: built)
            return try coordinatedURL.appendingPathComponent(Self.contentFileName)
                .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        if let modified {
            try? FileManager.default.setAttributes(
                [.modificationDate: modified], ofItemAtPath: built.appendingPathComponent(Self.contentFileName).path)
        }
        let id = try claimUniqueNote(base: title) { destination in
            try coordinatedWrite(at: destination, options: .forReplacing) { coordinatedURL in
                try FileManager.default.moveItem(at: built, to: coordinatedURL)
            }
        }
        try coordinatedWrite(at: folder, options: .forDeleting) { try trashOperation($0) }
        return id
    }

    /// Every file in the folder has its content on this Mac. A copy of a file without content would
    /// wait for the download, so such a file starts to download and the folder waits.
    private static func isDownloaded(_ folder: URL) -> Bool {
        guard isInICloud(folder) else { return true }
        let keys: [URLResourceKey] = [.ubiquitousItemDownloadingStatusKey, .isRegularFileKey]
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return false }
        var complete = true
        for case let item as URL in walk {
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { return false }
            if values.isRegularFile == true, !isLocal(values) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: item)
                complete = false
            }
        }
        return complete
    }

    // MARK: - Private

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

    /// Claims the first free `<base>`, `<base> 2`, … note; a lost race only advances the suffix.
    /// The claim gets the package URL; the note's id is the title without the extension.
    private func claimUniqueNote(
        base: String,
        renaming id: NoteID? = nil,
        _ claim: (URL) throws -> Void
    ) throws -> NoteID {
        let occupied = Set(try list().lazy.filter { $0.id != id }.map { folded($0.id.rawValue) })
        var suffix = 1
        while true {
            let title = suffix == 1 ? base : "\(base) \(suffix)"
            let candidate = packageURL(for: NoteID(rawValue: title))
            let name = folded(title)
            // A case-only rename collides with its own package, which the move then replaces in place.
            let isSelf = id.map { name == folded($0.rawValue) } ?? false
            guard !occupied.contains(name),
                isSelf || !FileManager.default.fileExists(atPath: candidate.path)
            else {
                suffix += 1
                continue
            }
            do {
                try claim(candidate)
                return NoteID(rawValue: title)
            } catch {
                guard !isSelf, FileManager.default.fileExists(atPath: candidate.path) else {
                    throw error
                }
                suffix += 1
            }
        }
    }

    /// The package itself: a `.noto` that is an immediate, unlinked child of the notes directory.
    private func validatedPackageURL(_ candidate: URL) throws -> URL {
        let standardized = candidate.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()
        let expectedParent = notesDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.noteID(forPackage: standardized) != nil,
            resolved.deletingLastPathComponent().path == expectedParent.path,
            resolved.lastPathComponent == standardized.lastPathComponent,
            standardized.lastPathComponent == candidate.lastPathComponent
        else { throw Failure.invalidLocation(candidate) }
        return standardized
    }

    /// The content file: `text.md` directly inside a validated package.
    private func validatedFileURL(_ candidate: URL) throws -> URL {
        let standardized = candidate.standardizedFileURL
        let package = try validatedPackageURL(standardized.deletingLastPathComponent())
        let resolved = standardized.resolvingSymlinksInPath()
        guard standardized.lastPathComponent == Self.contentFileName,
            resolved.deletingLastPathComponent().path == package.resolvingSymlinksInPath().path
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

    private func summaryPrecedes(_ lhs: NoteSummary, _ rhs: NoteSummary) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
    }

    private func folded(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The copy is named for the note and the time it was set aside, so the two sort together. It
    /// gets the images of `imagesFrom`, the package the text came from.
    private func keepConflictCopy(of id: NoteID, source: String, imagesFrom package: URL) throws -> NoteID {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let base = "\(id.rawValue) (Conflict \(formatter.string(from: now())))"
        let copy = try claimUniqueNote(base: base) {
            try createPackage(at: $0, source: Data(source.utf8))
        }
        // The text is what the copy saves; a missing image must not fail the save that needs it.
        do {
            try copyAssets(from: package, to: packageURL(for: copy))
        } catch {
            let reason = error.localizedDescription
            Logger.sync.error(
                "the conflict copy \(copy.rawValue, privacy: .private) has no images: \(reason, privacy: .public)")
        }
        Logger.sync.notice("kept a conflict copy of \(id.rawValue, privacy: .private) as \(copy.rawValue, privacy: .private)")
        return copy
    }

    /// The images travel with the text, or the copy shows placeholders. A note without images has no
    /// `assets` folder, and that is not an error.
    private func copyAssets(from package: URL, to copy: URL) throws {
        let assets = package.appendingPathComponent(NoteAssets.folderName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: assets.path) else { return }
        try FileManager.default.copyItem(
            at: assets, to: copy.appendingPathComponent(NoteAssets.folderName, isDirectory: true))
    }

    /// True for an item in iCloud. `isUbiquitousItem` alone is not enough: a process that the
    /// container's entitlement does not cover sees an iCloud item as local, and a rename there would
    /// leave the server with a plain folder. So any path under `~/Library/Mobile Documents` counts too.
    static func isInICloud(_ url: URL) -> Bool {
        if FileManager.default.isUbiquitousItem(at: url) { return true }
        let mobileDocuments = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath().path
        return url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(mobileDocuments + "/")
    }

    /// True unless iCloud holds the item without its content: a local item has no download status.
    private static func isLocal(_ values: URLResourceValues) -> Bool {
        guard let status = values.ubiquitousItemDownloadingStatus else { return true }
        return status == .current
    }

    private static func isLocal(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) else { return true }
        return isLocal(values)
    }

    private static func source(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let source = String(data: data, encoding: .utf8) else { throw Failure.unreadable(url) }
        return source
    }

    /// The claim fails if the package exists, which is what makes a lost race visible to the caller.
    private func createPackage(at package: URL, source: Data) throws {
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        do {
            try source.write(to: package.appendingPathComponent(Self.contentFileName), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: package)
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

    private func coordinatedRead<Value>(
        at fileURL: URL,
        _ read: (URL) throws -> Value
    ) throws -> Value {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Value, Swift.Error>?
        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try read(coordinatedURL) }
        }
        if let result { return try result.get() }
        if let coordinationError { throw coordinationError }
        throw CocoaError(.fileReadUnknown)
    }

    /// One read and one write under a single coordination, so no other writer lands between them.
    private func coordinatedReplace<Value>(
        at fileURL: URL,
        _ mutation: (URL) throws -> Value
    ) throws -> Value {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Value, Swift.Error>?
        coordinator.coordinate(
            readingItemAt: fileURL, options: [],
            writingItemAt: fileURL, options: .forReplacing,
            error: &coordinationError
        ) { _, writingURL in
            result = Result { try mutation(writingURL) }
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
