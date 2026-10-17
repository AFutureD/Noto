import CoreGraphics
import Foundation

@main
@MainActor
struct NotesTests {
    private static var failures = 0

    static func main() async throws {
        try testRepositoryAndSearch()
        testDerivedTitles()
        testHighlightColor()
        testAccentColor()
        try testUnnamedNotesTitleThemselves()
        testSwitcherInteraction()
        testWindowPlacement()
        try await testStoreCollectionAndAutosave()
        try await testStoreRefreshesExternalEdits()
        try await testStoreRefreshPreservesDrafts()
        try await testStoreRefreshRecoversFromFailures()
        try await testCollectionMutationsFlushTheDraft()
        try await testStoreRecoversFromFailures()
        try await testStoreRelocates()
        try await testStoreKeepsRemoteEditsBesideTheDraft()
        try await testStoreSavesOverAMergedNote()
        try await testStoreCopiesNotesIn()
        testNoteAssetPaths()
        try await testStoreImportsAssets()
        testEmojiCatalog()
        try testLegacyFoldersMigrate()
        try await testVersionsKeepTheWholeNote()
        testAssetReferences()
        try testDroppedAssetsGo()
        try await testStoreDeletesDroppedImagesWhenTheSessionEnds()
        try await testStoreAddsVersions()

        print(failures == 0 ? "Notes tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testRepositoryAndSearch() throws {
        let root = temporaryRoot("repository")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("app.huanan.noto")
        let stable = try repository(in: root, support: support)
        let development = try repository(
            in: root, support: root.appendingPathComponent("app.huanan.noto.dev"))

        try FileManager.default.createDirectory(
            at: stable.notesDirectory, withIntermediateDirectories: true)
        let floatingID = NoteID(rawValue: "Floating Note")
        try seed(stable, floatingID, "existing")
        try "stray".write(
            to: stable.notesDirectory.appendingPathComponent("Loose.md"), atomically: true, encoding: .utf8)
        let firstLoad = try stable.load(preferredID: nil)
        check("an existing note folder is discovered", firstLoad.1?.id == floatingID)
        check("a loose Markdown file is not a note", (try stable.list()).count == 1)
        check("existing Markdown source is preserved", firstLoad.1?.source == "existing")
        check(
            "channels receive different Notes directories",
            stable.notesDirectory.standardizedFileURL != development.notesDirectory.standardizedFileURL)

        let untitled = try stable.create()
        let secondUntitled = try stable.create()
        check("first creation uses the plain default title", untitled.id.rawValue == "Untitled")
        check("duplicate titles receive a numeric suffix", secondUntitled.id.rawValue == "Untitled 2")

        let source = "# Heading\n\nLiteral **Markdown** and café snow\n"
        try stable.save(id: untitled.id, source: source, base: "")
        check("UTF-8 Markdown round-trips unchanged", try stable.load(untitled.id).source == source)
        check(
            "the content lives in text.md inside the note package",
            stable.fileURL(for: untitled.id).path.hasSuffix("/Untitled.noto/text.md"))

        check(
            "a save over the content it read keeps no copy",
            try stable.save(id: untitled.id, source: source + "more", base: source) == nil)
        try Data("external".utf8).write(to: stable.fileURL(for: untitled.id), options: .atomic)
        let copy = try stable.save(id: untitled.id, source: source, base: source + "more")
        check("a save replaces what another writer left", try stable.load(untitled.id).source == source)
        check(
            "what another writer left is kept as a conflict copy",
            try copy.map { try stable.load($0).source } == "external"
                && copy?.rawValue.hasPrefix("Untitled (Conflict ") == true)
        if let copy { try FileManager.default.removeItem(at: stable.packageURL(for: copy)) }
        try FileManager.default.removeItem(at: stable.packageURL(for: untitled.id))
        try stable.save(id: untitled.id, source: source, base: source)
        check(
            "a save recreates a note folder deleted elsewhere",
            try stable.load(untitled.id).source == source && stable.list().count == 3)

        let plan = try stable.create(title: "Plan")
        let foldedCollision = try stable.create(title: "plán")
        check(
            "title collisions are case- and diacritic-insensitive",
            foldedCollision.id.rawValue == "plán 2")
        let renamed = try stable.rename(id: secondUntitled.id, title: "Plan")
        check("rename uses the same unique-title rule", renamed.rawValue == "Plan 3")

        let recased = try stable.rename(id: renamed, title: "PLAN 3")
        check("a rename that changes only case renames the folder", recased.rawValue == "PLAN 3")
        let accented = try stable.rename(id: recased, title: "Plán 3")
        check("a rename that adds only accents renames the folder", accented.rawValue == "Plán 3")
        check(
            "a rename to the identical title is a no-op",
            try stable.rename(id: accented, title: "Plán 3") == accented)
        check(
            "a renamed note leaves no copy under its old name",
            !(try stable.list()).contains { $0.id.rawValue == "Plan 3" })

        do {
            _ = try stable.create(title: "../escape")
            check("path-forming titles are rejected", false)
        } catch let failure {
            if case .invalidTitle = failure {
                check("path-forming titles are rejected", true)
            } else {
                check("an invalid title reports the title error", false)
            }
        }

        let bodyMatches = stable.search(
            NoteSearch.Query("cafe snow"), summaries: try stable.list(), limit: 10)
        check(
            "search matches Markdown bodies without transforming source",
            bodyMatches.contains { $0.id == untitled.id })
        let titleMatches = stable.search(
            NoteSearch.Query("Plan"), summaries: try stable.list(), limit: 1)
        check("search obeys its presentation limit", titleMatches.count == 1)
        check(
            "title matches outrank body-only matches",
            titleMatches.first?.summary.title.hasPrefix("Plan") == true)

        try stable.trash(id: plan.id)
        check(
            "deletion moves the package through the injected Trash operation",
            FileManager.default.fileExists(
                atPath: trashDirectory(in: root).appendingPathComponent("\(plan.id.rawValue).noto").path))

        let outside = root.appendingPathComponent("outside.md")
        try Data("outside".utf8).write(to: outside)
        let symlinkID = NoteID(rawValue: "Linked")
        try FileManager.default.createDirectory(
            at: stable.packageURL(for: symlinkID), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: stable.fileURL(for: symlinkID), withDestinationURL: outside)
        do {
            _ = try stable.load(symlinkID)
            check("a note cannot escape its channel through a symlink", false)
        } catch let failure {
            if case .invalidLocation = failure {
                check("a note cannot escape its channel through a symlink", true)
            } else {
                check("an escaping symlink reports its invalid location", false)
            }
        }
        check(
            "a symlinked text.md is absent from enumeration",
            !(try stable.list()).contains { $0.id == symlinkID })

        let empty = try repository(
            in: root, support: root.appendingPathComponent("app.huanan.noto.empty"))
        let emptyLoad = try empty.load(preferredID: nil)
        check("an empty collection loads no document", emptyLoad.0.isEmpty && emptyLoad.1 == nil)
        check(
            "loading an empty collection creates no file",
            (try FileManager.default.contentsOfDirectory(atPath: empty.notesDirectory.path)).isEmpty)
    }

    private static func testDerivedTitles() {
        check(
            "the names Create claims are unnamed",
            NoteTitle.isUnnamed("Untitled") && NoteTitle.isUnnamed("Untitled 12"))
        check(
            "a typed title is never unnamed",
            !NoteTitle.isUnnamed("Plan") && !NoteTitle.isUnnamed("untitled")
                && !NoteTitle.isUnnamed("Untitled notes") && !NoteTitle.isUnnamed("Untitled 2b"))

        check(
            "a heading marker is not part of the derived title",
            NoteTitle.firstLine(of: "#  Groceries \n\nmilk") == "Groceries")
        check(
            "task titles omit checkbox syntax",
            NoteTitle.firstLine(of: "- [ ] Groceries\n- [x] milk") == "Groceries")
        check(
            "leading blank lines are skipped",
            NoteTitle.firstLine(of: "\n \t \n  café snow\nmore") == "café snow")
        check(
            "a hashtag is literal text, not a heading",
            NoteTitle.firstLine(of: "####### seven\n") == "####### seven"
                && NoteTitle.firstLine(of: "#tag") == "#tag")
        check(
            "a blank note derives no title",
            NoteTitle.firstLine(of: "") == nil && NoteTitle.firstLine(of: "\n  \n\t\n") == nil)
        check(
            "a wall of text is capped to one row",
            NoteTitle.firstLine(of: String(repeating: "a", count: 400))?.count == 120)
        check("a task title drops its box", NoteTitle.firstLine(of: "- [ ] Buy milk") == "Buy milk")
        check("a bullet title drops its marker", NoteTitle.firstLine(of: "  * errands\n") == "errands")
        check("a quote title drops its marker", NoteTitle.firstLine(of: "> quoted words") == "quoted words")
        check(
            "a bold title drops its delimiters", NoteTitle.firstLine(of: "Buy **milk** now") == "Buy milk now"
        )
        check(
            "a highlighted title drops its delimiters",
            NoteTitle.firstLine(of: "==Urgent== call") == "Urgent call")
        check(
            "a link title keeps only its label",
            NoteTitle.firstLine(of: "[Plan](https://a.com) v2") == "Plan v2")
        check(
            "rules and fences carry no title",
            NoteTitle.firstLine(of: "---\n```swift\nlet x = 1\n```") == "let x = 1")
    }

    private static func testUnnamedNotesTitleThemselves() throws {
        let root = temporaryRoot("derived")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)

        let unnamed = try repository.create()
        try repository.save(id: unnamed.id, source: "# Groceries\n\nmilk\n", base: "")
        let named = try repository.create(title: "Plan")
        try repository.save(id: named.id, source: "# Ignored heading\n", base: "")

        let summaries = try repository.list()
        let unnamedSummary = try require(summaries.first { $0.id == unnamed.id })
        check("an unnamed note shows its first line", unnamedSummary.displayTitle == "Groceries")
        check("an unnamed note keeps its filename as its title", unnamedSummary.title == "Untitled")
        let namedSummary = try require(summaries.first { $0.id == named.id })
        check(
            "a named note ignores its first line",
            namedSummary.firstLine == nil && namedSummary.displayTitle == "Plan")

        let fuzzy = repository.search(NoteSearch.Query("Grcrs"), summaries: summaries, limit: 10)
        check(
            "search matches a derived title the body never spells out",
            fuzzy.count == 1 && fuzzy.first?.id == unnamed.id)

        let renamed = try repository.rename(id: unnamed.id, title: "Shopping")
        let afterRename = try require((try repository.list()).first { $0.id == renamed })
        check("naming a note retires its derived title", afterRename.firstLine == nil)
    }

    private static func testSwitcherInteraction() {
        let id = NoteID(rawValue: "Project")
        var rename = NoteSwitcherRenameState()
        check("switcher rename starts inactive", !rename.isActive)
        rename.begin(id: id, title: "Project")
        check("switcher rename captures identity and title", rename.id == id && rename.draft == "Project")
        rename.updateDraft("Project plan")
        let committed = rename.commit()
        check(
            "switcher rename commits once and clears its state",
            committed?.id == id && committed?.title == "Project plan" && !rename.isActive)
        check("an inactive rename cannot commit", rename.commit() == nil)

        let first = NoteID(rawValue: "First")
        let second = NoteID(rawValue: "Second")
        let third = NoteID(rawValue: "Third")
        let fallback = NoteID(rawValue: "Untitled")
        check(
            "Trash selects the next switcher row",
            NoteSwitcherSelection.replacement(
                afterRemoving: second,
                from: [first, second, third],
                fallback: fallback) == third)
        check(
            "Trash selects the previous row when removing the last one",
            NoteSwitcherSelection.replacement(
                afterRemoving: third,
                from: [first, second, third],
                fallback: fallback) == second)
        check(
            "Trash uses the post-operation fallback when no row remains",
            NoteSwitcherSelection.replacement(
                afterRemoving: first,
                from: [first],
                fallback: fallback) == fallback)
    }

    private static func testWindowPlacement() {
        let visible = CGRect(x: 0, y: 50, width: 1440, height: 850)
        let window = CGRect(x: 100, y: 100, width: 440, height: 312)
        check(
            "corner placement respects menu bar and Dock insets",
            NoteWindowPlacement.topRight(window, in: visible, inset: 40)
                == CGRect(x: 960, y: 548, width: 440, height: 312))

        let external = CGRect(x: -1920, y: 30, width: 1880, height: 1020)
        check(
            "corner placement respects another display's origin",
            NoteWindowPlacement.topRight(window, in: external, inset: 40)
                == CGRect(x: -520, y: 698, width: 440, height: 312))

        let nearlyFull = CGRect(x: 0, y: 0, width: 1420, height: 830)
        check(
            "corner placement reduces the inset rather than pushing a fitting window offscreen",
            NoteWindowPlacement.topRight(nearlyFull, in: visible, inset: 40)
                == CGRect(x: 0, y: 50, width: 1420, height: 830))

        let oversized = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        check(
            "oversized notes retain their size and align the top-right corner",
            NoteWindowPlacement.topRight(oversized, in: visible, inset: 40)
                == CGRect(x: -160, y: -100, width: 1600, height: 1000))

        let highWindow = CGRect(x: 100, y: 500, width: 440, height: 180)
        let heights: ClosedRange<CGFloat> = 180...860
        check(
            "fitting grows downward and preserves width and the top edge",
            NoteWindowPlacement.fitting(highWindow, toHeight: 300, within: heights, in: visible)
                == CGRect(x: 100, y: 380, width: 440, height: 300))
        check(
            "fitting moves the window up when it reaches the Dock",
            NoteWindowPlacement.fitting(window, toHeight: 500, within: heights, in: visible)
                == CGRect(x: 100, y: 50, width: 440, height: 500))
        check(
            "fitting stops at the screen's usable height",
            NoteWindowPlacement.fitting(highWindow, toHeight: 2000, within: heights, in: visible)
                == CGRect(x: 100, y: 50, width: 440, height: 850))
        let tall = CGRect(x: 0, y: 0, width: 2560, height: 1400)
        let tallWindow = CGRect(x: 100, y: 1000, width: 440, height: 312)
        check(
            "fitting stops at the height limit on a tall display",
            NoteWindowPlacement.fitting(tallWindow, toHeight: 2000, within: heights, in: tall)
                == CGRect(x: 100, y: 452, width: 440, height: 860))
        check(
            "fitting shrinks shorter content and preserves the top edge",
            NoteWindowPlacement.fitting(window, toHeight: 200, within: heights, in: visible)
                == CGRect(x: 100, y: 212, width: 440, height: 200))
        check(
            "fitting never shrinks below the minimum height",
            NoteWindowPlacement.fitting(window, toHeight: 40, within: heights, in: visible)
                == CGRect(x: 100, y: 232, width: 440, height: 180))
        let externalWindow = CGRect(x: -900, y: 700, width: 500, height: 180)
        check(
            "fitting uses the current display's origin and rounds up fractional heights",
            NoteWindowPlacement.fitting(externalWindow, toHeight: 300.2, within: heights, in: external)
                == CGRect(x: -900, y: 579, width: 500, height: 301))
    }

    private static func testStoreCollectionAndAutosave() async throws {
        let root = temporaryRoot("store")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let selection = SelectionBox()
        let store = NotesStore(
            repository: repository,
            loadSelection: { selection.id },
            saveSelection: { selection.id = $0 })
        let started = await store.create()
        check(
            "Create Note is one file when it is the first action",
            started && store.activeTitle == "Untitled" && store.summaries.count == 1)
        check("active selection is persisted separately from note files", selection.id == store.activeID)

        store.updateSource("# Draft heading\nbody")
        check(
            "an unnamed note titles itself from the live draft",
            store.activeTitle == "Draft heading")

        store.updateSource("first")
        store.updateSource("latest searchable body")
        await waitUntil { !store.isDirty }
        let firstID = try require(store.activeID)
        check(
            "debounced autosave writes only the latest source",
            try String(contentsOf: repository.fileURL(for: firstID), encoding: .utf8)
                == "latest searchable body")

        let created = await store.create()
        check("store creates another note", created)
        let secondID = try require(store.activeID)
        check("the new note becomes active", secondID != firstID)
        let renamedID = await store.rename(secondID, to: "Project")
        check(
            "rename updates active identity and title",
            renamedID == store.activeID && store.activeTitle == "Project")

        store.updateSearchQuery("searchable")
        await waitUntil { !store.isSearching }
        check(
            "on-demand search finds body text in another note",
            store.searchResults.contains { $0.id == firstID })
        store.cancelSearch()
        let selectionBeforeRejection = selection.id
        let activeBeforeRejection = store.activeID
        let rejectedSelection = await store.select(firstID, permitsApply: { false })
        check(
            "a superseded selection cannot change or persist the active note",
            !rejectedSelection && store.activeID == activeBeforeRejection
                && selection.id == selectionBeforeRejection)
        let selected = await store.select(firstID)
        check(
            "select flushes and changes the active document",
            selected && store.source == "latest searchable body")

        let activeURL = repository.fileURL(for: firstID)
        store.updateSource("draft that outlives a switch")
        let switched = await store.select(try require(renamedID))
        let flushedOnSwitch = try String(contentsOf: activeURL, encoding: .utf8)
        check(
            "switching flushes the draft before it loads another note",
            switched && flushedOnSwitch == "draft that outlives a switch")
        _ = await store.select(firstID)

        let projectID = try require(renamedID)
        let trashed = await store.trash(projectID)
        check("a non-active note moves to Trash", trashed)
        check(
            "trashing another note moves it through the injected Trash operation",
            FileManager.default.fileExists(
                atPath: trashDirectory(in: root).appendingPathComponent("\(projectID.rawValue).noto").path))
        check("trashing another note keeps the active note", store.activeID == firstID)

        for summary in store.summaries {
            _ = await store.trash(summary.id)
        }
        check(
            "deleting the last note leaves the collection empty",
            store.summaries.isEmpty && store.activeID == nil && store.source.isEmpty)
        check("an empty collection is still loaded", store.isLoaded)
        store.updateSource("ignored with no active note")
        check("editing does nothing while no note is active", store.source.isEmpty)
        let recreated = await store.create()
        check("creating restores an active note", recreated && store.activeID != nil)
        store.stop()
    }

    private static func testStoreRefreshesExternalEdits() async throws {
        let root = temporaryRoot("external-edits")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let selection = SelectionBox()
        let store = NotesStore(
            repository: repository, saveSelection: { selection.id = $0 })
        defer { store.stop() }

        _ = await store.create()
        let activeID = try require(store.activeID)
        let activeURL = repository.fileURL(for: activeID)
        let unchecked = "- [ ] First task\n- [ ] Second task\n"
        store.updateSource("- [x] First task\n- [x] Second task\n")
        _ = await store.flush()
        let epoch = store.editorEpoch
        let modifiedAt = try activeURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        try unchecked.write(to: activeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: try require(modifiedAt)], ofItemAtPath: activeURL.path)

        let refreshed = await store.start()
        check(
            "reopening reloads externally reset checkboxes even with an unchanged modification date",
            refreshed && store.activeID == activeID && store.source == unchecked && !store.isDirty)
        check("an external edit resets the editor history", store.editorEpoch == epoch + 1)

        let refreshedEpoch = store.editorEpoch
        let unchanged = await store.start()
        check(
            "reopening unchanged contents preserves editor history",
            unchanged && store.source == unchecked && store.editorEpoch == refreshedEpoch)

        let other = try repository.create(title: "Other")
        try repository.save(id: other.id, source: "Another note", base: "")
        _ = await store.start()
        check(
            "externally added notes appear without replacing the active note or its history",
            store.summaries.contains { $0.id == other.id }
                && store.activeID == activeID && store.editorEpoch == refreshedEpoch)

        let externalText = "# Updated elsewhere\n🧑🏽‍💻 Plain text\n"
        try externalText.write(to: activeURL, atomically: true, encoding: .utf8)
        _ = await store.start()
        check(
            "external text edits refresh both the source and the derived title",
            store.source == externalText && store.activeTitle == "Updated elsewhere")

        try FileManager.default.removeItem(at: activeURL)
        _ = await store.start()
        check(
            "an externally deleted active note selects a remaining note",
            store.activeID == other.id && store.source == "Another note" && selection.id == other.id)

        try FileManager.default.removeItem(at: repository.packageURL(for: other.id))
        _ = await store.start()
        check(
            "deleting the last note externally clears the editor and persisted selection",
            store.summaries.isEmpty && store.activeID == nil && store.source.isEmpty && selection.id == nil)
        let emptyEpoch = store.editorEpoch
        _ = await store.start()
        check("reopening an empty collection leaves the editor alone", store.editorEpoch == emptyEpoch)
    }

    private static func testStoreKeepsRemoteEditsBesideTheDraft() async throws {
        let root = temporaryRoot("remote-edit")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let store = NotesStore(repository: repository)
        defer { store.stop() }
        _ = await store.create()
        let activeID = try require(store.activeID)
        store.updateSource("Shared start")
        _ = await store.flush()

        // Another device saves while this one types.
        try Data("Edited on the iPhone".utf8).write(to: repository.fileURL(for: activeID), options: .atomic)
        store.updateSource("Shared start, typed on this Mac")
        _ = await store.flush()
        let notes = try repository.list()
        let copy = notes.first { $0.id.rawValue.hasPrefix("\(activeID.rawValue) (Conflict ") }
        check(
            "the draft lands over a remote edit",
            try repository.load(activeID).source == "Shared start, typed on this Mac")
        check(
            "the remote edit is kept as a conflict copy",
            try copy.map { try repository.load($0.id).source } == "Edited on the iPhone")
        check("the conflict copy is listed", store.summaries.contains { $0.id == copy?.id })

        store.updateSource("Shared start, typed on this Mac, and more")
        _ = await store.flush()
        check(
            "the next save over its own write keeps no further copy",
            try repository.list().count == notes.count)
    }

    /// Two Macs offline both create `Untitled`; iCloud keeps one folder with the other Mac's text.
    private static func testStoreSavesOverAMergedNote() async throws {
        let root = temporaryRoot("merged")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let store = NotesStore(repository: repository)
        defer { store.stop() }
        _ = await store.create()
        let activeID = try require(store.activeID)
        try Data("Written on the other Mac".utf8).write(to: repository.fileURL(for: activeID), options: .atomic)
        store.updateSource("Written on this Mac")
        _ = await store.flush()
        let sources = try repository.list().map { try repository.load($0.id).source }
        check(
            "neither Mac's text is lost when both notes share one folder",
            Set(sources) == ["Written on this Mac", "Written on the other Mac"])
    }

    private static func testNoteAssetPaths() {
        let folder = URL(fileURLWithPath: "/notes/Plan", isDirectory: true)
        check(
            "a relative image path resolves inside the note folder",
            NoteAssets.resolve("assets/a b.png", in: folder)?.path == "/notes/Plan/assets/a b.png")
        check("a path out of the note folder is refused", NoteAssets.resolve("../Other/assets/a.png", in: folder) == nil)
        check("an absolute path is refused", NoteAssets.resolve("/etc/hosts", in: folder) == nil)
        check("a remote image is refused", NoteAssets.resolve("https://example.com/a.png", in: folder) == nil)
        check("the note folder itself is not an image", NoteAssets.resolve(".", in: folder) == nil)
        check(
            "a taken name takes the next free one, case-insensitively",
            NoteAssets.uniqueName(for: "image.png", taken: ["Image.png", "image 2.png"]) == "image 3.png")
        check("an image mid-line becomes its own paragraph", NoteAssets.paragraph("I", after: "a", before: "b") == "\nI\n")
        check("an image at a line start adds nothing", NoteAssets.paragraph("I", after: "\n", before: nil) == "I")
        check("an image at the very start adds nothing", NoteAssets.paragraph("I", after: nil, before: "\n") == "I")
        check(
            "the Markdown encodes the space and the parentheses",
            NoteAssets.markdown(for: "assets/a (1).png") == "![](assets/a%20%281%29.png)")
    }

    private static func testStoreImportsAssets() async throws {
        let root = temporaryRoot("assets")
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try repository(in: root, support: root.appendingPathComponent("local"))
        let id = NoteID(rawValue: "Pictures")
        try seed(local, id, "text")
        let image = root.appendingPathComponent("shot.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)

        let store = NotesStore(repository: local)
        defer { store.stop() }
        _ = await store.start()
        _ = await store.select(id)
        let first = await store.importAssets([image, image], into: id)
        check("each file gets its own free name", first == ["assets/shot.png", "assets/shot 2.png"])
        let copied = local.packageURL(for: id).appendingPathComponent("assets/shot 2.png")
        check("the copy lands in the note's assets folder", FileManager.default.fileExists(atPath: copied.path))
        check("the original stays where it was", FileManager.default.fileExists(atPath: image.path))
        let pastedFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: pastedFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pastedFolder) }
        let pasted = pastedFolder.appendingPathComponent("image.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pasted)
        let pastedPath = await store.importAssets([pasted], into: id)
        check(
            "a pasted image gets a dated name",
            pastedPath?.first?.hasPrefix("assets/Pasted ") == true && pastedPath?.first?.hasSuffix(".png") == true)
        check("a dropped image is an image", NoteAssets.isImage(image))
        check("a folder is not an image", !NoteAssets.isImage(root))
        let other = await store.importAssets([image], into: NoteID(rawValue: "Not Active"))
        check("an import for a note that is not active inserts nothing", other == nil)

        let cloud = try repository(in: root, support: root.appendingPathComponent("cloud"))
        _ = try cloud.copyNotes(from: local)
        check(
            "a note copied to another folder brings its images",
            FileManager.default.fileExists(
                atPath: cloud.packageURL(for: id).appendingPathComponent("assets/shot.png").path))
    }

    private static func testEmojiCatalog() {
        check("the catalog holds the OS emoji", EmojiCatalog.all.count > 1000)
        check("a whole name comes first", EmojiCatalog.search("fire").first?.character == "🔥")
        check("an alias finds a shortcode", EmojiCatalog.search("+1").first?.character == "👍")
        check("a partly typed alias finds its emoji", EmojiCatalog.search("tad").first?.character == "🎉")
        check("smile finds smiling faces", EmojiCatalog.search("smile").count > 3)
        check("one letter lists nothing", EmojiCatalog.search("s").isEmpty)
        check(
            "a text-default emoji carries the emoji variation selector",
            EmojiCatalog.search("snowman").contains { $0.character.unicodeScalars.last == "\u{FE0F}" })
        var picker = NoteEmojiPicker(query: "cat")
        picker?.moveSelection(by: -1)
        check("the selection wraps upward to the last row", picker?.selection == (picker?.candidates.count ?? 0) - 1)
        check("a query with no match has no list", NoteEmojiPicker(query: "zzzzqq") == nil)
    }

    private static func testStoreCopiesNotesIn() async throws {
        let root = temporaryRoot("copy-in")
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try repository(in: root, support: root.appendingPathComponent("local"))
        let cloud = try repository(in: root, support: root.appendingPathComponent("cloud"))
        try seed(local, NoteID(rawValue: "Same"), "same text")
        try seed(local, NoteID(rawValue: "Differs"), "local text")
        try seed(local, NoteID(rawValue: "Only Here"), "only local")
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: old], ofItemAtPath: local.fileURL(for: NoteID(rawValue: "Only Here")).path)
        try seed(cloud, NoteID(rawValue: "same"), "same text")
        try seed(cloud, NoteID(rawValue: "Differs"), "cloud text")

        let store = NotesStore(repository: cloud)
        defer { store.stop() }
        _ = await store.start()
        let copied = await store.copyNotes(from: local)
        let titles = Set(try cloud.list().map(\.id.rawValue))
        check("a note iCloud already has with the same text is not copied", copied == 2)
        check(
            "a differing note of the same name takes the next name",
            try titles == ["same", "Differs", "Differs 2", "Only Here"]
                && cloud.load(NoteID(rawValue: "Differs 2")).source == "local text")
        let modified = try cloud.fileURL(for: NoteID(rawValue: "Only Here"))
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        check("a copied note keeps its modification date", modified == old)
        check("the listing shows the copies", store.summaries.count == 4)
        check("the source folder is left as it was", try local.list().count == 3)
    }

    private static func testStoreRefreshPreservesDrafts() async throws {
        let root = temporaryRoot("refresh-draft")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let store = NotesStore(repository: repository)
        defer { store.stop() }
        _ = await store.create()
        let activeID = try require(store.activeID)
        let epoch = store.editorEpoch

        store.updateSource("Unsaved draft")
        store.stop()
        let reopened = await store.start()
        check(
            "refreshing the collection preserves an unsaved draft and its history",
            reopened && store.source == "Unsaved draft" && store.isDirty && store.editorEpoch == epoch)
        let flushed = await store.flush()
        let savedSource = try repository.load(activeID).source
        check(
            "the preserved draft still saves to its original note",
            flushed && savedSource == "Unsaved draft")

        store.updateSource("Draft being saved")
        async let save = store.flush()
        async let refresh = store.start()
        let completed = await [save, refresh]
        check(
            "reopening during a save preserves the saved draft and editor history",
            completed.allSatisfy { $0 } && !store.isDirty
                && store.source == "Draft being saved" && store.editorEpoch == epoch)
        check(
            "reopening during a save leaves the file consistent with the editor",
            try repository.load(activeID).source == store.source)
    }

    private static func testStoreRefreshRecoversFromFailures() async throws {
        let root = temporaryRoot("refresh-recovery")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let store = NotesStore(repository: repository)
        defer { store.stop() }
        _ = await store.create()
        let activeID = try require(store.activeID)
        let activeURL = repository.fileURL(for: activeID)
        store.updateSource("Saved draft")
        _ = await store.flush()
        let epoch = store.editorEpoch
        var loadFailures = 0
        store.onIssue = { issue in
            if case .load = issue { loadFailures += 1 }
        }

        try Data([0xFF]).write(to: activeURL, options: .atomic)
        let unreadable = await store.start()
        check(
            "an unreadable external edit reports a load failure and retains the previous contents",
            unreadable && loadFailures == 1 && store.source == "Saved draft" && store.editorEpoch == epoch)
        try "Repaired externally".write(to: activeURL, atomically: true, encoding: .utf8)
        let repaired = await store.start()
        check("reopening retries a failed external reload", repaired && store.source == "Repaired externally")

        try "Cancelled external edit".write(to: activeURL, atomically: true, encoding: .utf8)
        let repairedEpoch = store.editorEpoch
        let cancelledRefresh = Task { await store.start() }
        cancelledRefresh.cancel()
        let cancelled = await cancelledRefresh.value
        check(
            "a cancelled refresh leaves the current note and its history intact",
            !cancelled && store.source == "Repaired externally" && store.editorEpoch == repairedEpoch)

        store.updateSource("Draft after a failed save")
        let activeFolder = repository.packageURL(for: activeID)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: activeFolder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: activeFolder.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repository.notesDirectory.path)
        }
        let failedSave = await store.flush()
        let failedEpoch = store.editorEpoch
        let reopened = await store.start()
        check(
            "reopening preserves a draft whose save failed",
            !failedSave && reopened && store.isDirty
                && store.source == "Draft after a failed save" && store.editorEpoch == failedEpoch)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: repository.notesDirectory.path)
        let unlisted = await store.start()
        check(
            "an unreadable folder still reopens on the retained draft",
            unlisted && store.isDirty && store.source == "Draft after a failed save")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repository.notesDirectory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: activeFolder.path)
        let retried = await store.retrySave()
        let retriedSource = try repository.load(activeID).source
        check(
            "the retained draft can still be saved after reopening",
            retried && retriedSource == "Draft after a failed save")
    }

    private static func testCollectionMutationsFlushTheDraft() async throws {
        let root = temporaryRoot("mutation-flush")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let store = NotesStore(repository: repository)

        _ = await store.create()
        let renameTarget = try require(store.activeID)
        _ = await store.create()
        let trashTarget = try require(store.activeID)
        _ = await store.create()
        let activeID = try require(store.activeID)
        let activeURL = repository.fileURL(for: activeID)

        store.updateSource("draft before rename")
        let renamed = await store.rename(renameTarget, to: "Renamed")
        check("renaming another note succeeds", renamed?.rawValue == "Renamed")
        check(
            "renaming another note writes the active draft first",
            try String(contentsOf: activeURL, encoding: .utf8) == "draft before rename")

        store.updateSource("draft before trash")
        let trashed = await store.trash(trashTarget)
        check("trashing another note succeeds", trashed)
        check(
            "trashing another note writes the active draft first",
            try String(contentsOf: activeURL, encoding: .utf8) == "draft before trash")
        check("the active note survives another note's deletion", store.activeID == activeID)

        store.updateSource("draft before self-rename")
        let selfRenamed = await store.rename(activeID, to: "Self")
        let selfRenamedID = try require(selfRenamed)
        check("renaming the active note re-points identity", store.activeID == selfRenamedID)
        check(
            "renaming the active note carries its draft into the new file",
            try String(contentsOf: repository.fileURL(for: selfRenamedID), encoding: .utf8)
                == "draft before self-rename")
        store.stop()
    }

    private static func testStoreRecoversFromFailures() async throws {
        let root = temporaryRoot("recovery")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        try FileManager.default.createDirectory(
            at: repository.notesDirectory, withIntermediateDirectories: true)
        let unreadable = repository.fileURL(for: NoteID(rawValue: "Unreadable"))
        try seed(repository, NoteID(rawValue: "Unreadable"), Data([0xFF]))

        let failingStore = NotesStore(repository: repository)
        let firstStart = await failingStore.start()
        check("a store whose first load fails does not report itself loaded", !firstStart)
        try Data("repaired".utf8).write(to: unreadable, options: .atomic)
        let secondStart = await failingStore.start()
        check(
            "a failed start can be retried in the same session",
            secondStart && failingStore.source == "repaired")
        failingStore.stop()

        let store = NotesStore(repository: repository)
        _ = await store.start()
        let activeID = try require(store.activeID)
        let activeURL = repository.fileURL(for: activeID)

        store.updateSource("concurrent draft")
        async let firstFlush = store.flush()
        async let secondFlush = store.flush()
        let flushed = await [firstFlush, secondFlush]
        check("overlapping flushes agree on one save", flushed.allSatisfy { $0 })
        check("overlapping flushes leave no unsaved draft", !store.isDirty)
        check(
            "overlapping flushes write the draft once",
            try String(contentsOf: activeURL, encoding: .utf8) == "concurrent draft")

        store.updateSource("first edit")
        async let slowFlush = store.flush()
        store.updateSource("edit during the write")
        _ = await slowFlush
        _ = await store.flush()
        check(
            "an edit that lands during a write is not lost",
            try String(contentsOf: activeURL, encoding: .utf8) == "edit during the write")
        store.stop()
    }

    private static func testStoreRelocates() async throws {
        let root = temporaryRoot("relocation")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try repository(in: root, support: root.appendingPathComponent("first"))
        let second = try repository(in: root, support: root.appendingPathComponent("second"))
        let fm = FileManager.default
        try fm.createDirectory(at: first.notesDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: second.notesDirectory, withIntermediateDirectories: true)
        let firstURL = first.fileURL(for: NoteID(rawValue: "Plan"))
        try seed(first, NoteID(rawValue: "Plan"), "plan")
        let unreadable = second.fileURL(for: NoteID(rawValue: "Broken"))
        try seed(second, NoteID(rawValue: "Broken"), Data([0xFF]))

        let store = NotesStore(repository: first)
        _ = await store.start()
        store.updateSource("unsaved plan")
        let planFolder = first.packageURL(for: NoteID(rawValue: "Plan"))
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: planFolder.path)
        await store.relocate(to: second)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: planFolder.path)
        check(
            "a draft the old folder can't take keeps the store there",
            store.notesDirectory == first.notesDirectory && store.source == "unsaved plan")

        _ = await store.retrySave()
        for _ in 0..<100 where store.notesDirectory != second.notesDirectory {
            try await Task.sleep(for: .milliseconds(10))
        }
        check(
            "the draft is saved where it was, then the move goes ahead",
            try String(contentsOf: firstURL, encoding: .utf8) == "unsaved plan"
                && store.notesDirectory == second.notesDirectory)
        check("a folder that fails to load leaves no old note open", store.activeID == nil)
        store.stop()
    }

    private static func testHighlightColor() {
        let colour = NoteHighlightColor(red: 1, green: 0.5, blue: 0, alpha: 0.6)
        check("a colour stores as #RRGGBBAA", colour.hex == "#FF800099")
        check(
            "a stored colour reads back within a channel step",
            NoteHighlightColor(hex: colour.hex).map {
                abs($0.red - 1) < 0.005 && abs($0.green - 0.5) < 0.005 && $0.blue == 0
                    && abs($0.alpha - 0.6) < 0.005
            } == true)
        check(
            "a malformed colour is nil",
            NoteHighlightColor(hex: "FF800099") == nil && NoteHighlightColor(hex: "#FF8000") == nil
                && NoteHighlightColor(hex: "#GG800099") == nil)
    }

    private static func testAccentColor() {
        let colour = NoteAccentColor(red: 1, green: 0.5, blue: 0)
        check("an accent stores as #RRGGBB", colour.hex == "#FF8000")
        check(
            "a stored accent reads back within a channel step",
            NoteAccentColor(hex: colour.hex).map {
                abs($0.red - 1) < 0.005 && abs($0.green - 0.5) < 0.005 && $0.blue == 0
            } == true)
        check(
            "a malformed accent is nil",
            NoteAccentColor(hex: "FF8000") == nil && NoteAccentColor(hex: "#FF800099") == nil
                && NoteAccentColor(hex: "#GG8000") == nil)
    }

    private static func testLegacyFoldersMigrate() throws {
        let root = temporaryRoot("migration")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let fm = FileManager.default
        try fm.createDirectory(at: repository.notesDirectory, withIntermediateDirectories: true)
        func legacy(_ name: String, _ text: String, image: Bool = false) throws {
            let folder = repository.notesDirectory.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: folder.appendingPathComponent("assets"), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: folder.appendingPathComponent("text.md"))
            if image { try Data([1, 2, 3]).write(to: folder.appendingPathComponent("assets/a.png")) }
        }
        try legacy("Plan", "plan text", image: true)
        try legacy("Twin", "same text")
        try seed(repository, NoteID(rawValue: "Twin"), "same text")
        try legacy("Clash", "old text")
        try seed(repository, NoteID(rawValue: "Clash"), "new text")
        try fm.createDirectory(
            at: repository.notesDirectory.appendingPathComponent("Not a note"), withIntermediateDirectories: true)
        check(
            "a plain note folder is not listed before it migrates",
            try !repository.list().contains { $0.id.rawValue == "Plan" })

        let report = repository.migrateLegacyNotes()
        check("each plain note folder migrates", Set(report.migrated.map(\.rawValue)) == ["Plan", "Twin", "Clash 2"])
        check("nothing fails or waits on a local disk", report.failed.isEmpty && report.deferred.isEmpty)
        check("a migrated note keeps its text", try repository.load(NoteID(rawValue: "Plan")).source == "plan text")
        check(
            "a migrated note keeps its images",
            fm.fileExists(
                atPath: repository.packageURL(for: NoteID(rawValue: "Plan")).appendingPathComponent("assets/a.png").path))
        check(
            "a local migration is a rename: the plain folder is gone",
            !fm.fileExists(atPath: repository.notesDirectory.appendingPathComponent("Plan").path))
        check(
            "a folder that another Mac already migrated goes to the Trash",
            try fm.fileExists(atPath: trashDirectory(in: root).appendingPathComponent("Twin").path)
                && repository.load(NoteID(rawValue: "Twin")).source == "same text")
        check(
            "a folder with other text than the package of its name takes the next free name",
            try repository.load(NoteID(rawValue: "Clash 2")).source == "old text"
                && repository.load(NoteID(rawValue: "Clash")).source == "new text")
        check(
            "a folder without text.md is not a note and stays",
            fm.fileExists(atPath: repository.notesDirectory.appendingPathComponent("Not a note").path))
        check("a second migration finds nothing", repository.migrateLegacyNotes() == .init())
        let mobileDocuments = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~app~huanan~noto/Documents/Plan")
        check(
            "a path in an iCloud container counts as iCloud, also when the process cannot see the container",
            NotesRepository.isInICloud(mobileDocuments) && !NotesRepository.isInICloud(repository.notesDirectory))
    }

    private static func testVersionsKeepTheWholeNote() async throws {
        let root = temporaryRoot("versions")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let id = NoteID(rawValue: "History")
        try seed(repository, id, "v1")
        let assets = repository.packageURL(for: id).appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data([1]).write(to: assets.appendingPathComponent("a.png"))
        try repository.snapshot(id: id)
        try repository.save(id: id, source: "v2", base: "v1")
        try FileManager.default.removeItem(at: assets.appendingPathComponent("a.png"))

        let versions = NSFileVersion.otherVersionsOfItem(at: repository.packageURL(for: id)) ?? []
        check("a snapshot is a version of the package", versions.count == 1)
        if let version = versions.first {
            check(
                "a version keeps the text",
                (try? String(contentsOf: version.url.appendingPathComponent("text.md"), encoding: .utf8)) == "v1")
            check(
                "a version keeps the images",
                FileManager.default.fileExists(atPath: version.url.appendingPathComponent("assets/a.png").path))
        }
        let renamed = try repository.rename(id: id, title: "History Renamed")
        check(
            "a rename keeps the versions",
            (NSFileVersion.otherVersionsOfItem(at: repository.packageURL(for: renamed)) ?? []).count == 1)
        func count() -> Int { (NSFileVersion.otherVersionsOfItem(at: repository.packageURL(for: renamed)) ?? []).count }
        try repository.snapshot(id: renamed)
        check("a snapshot of a changed note adds a version", count() == 2)
        try repository.snapshot(id: renamed)
        check("a snapshot of the same note adds no version", count() == 2)
        let image = repository.packageURL(for: renamed).appendingPathComponent("assets/b.png")
        try Data([3]).write(to: image)
        try repository.snapshot(id: renamed)
        check("a snapshot after an image came adds a version", count() == 3)
        try Data([4]).write(to: image)
        try repository.snapshot(id: renamed, onlyOutsideICloud: true)
        check("a note outside iCloud gets the snapshot that iCloud would skip, also for new image bytes", count() == 4)
        let none = await repository.downloadServerVersions(
            of: renamed, since: .distantPast, until: Date().addingTimeInterval(10))
        check("a note outside iCloud has no server versions to download", none == 0)
    }

    private static func testAssetReferences() {
        check("a path names its file", NoteAssets.isReferenced("a b.png", in: "![](assets/a%20b.png)"))
        check("a written path names its file", NoteAssets.isReferenced("a b.png", in: "see assets/a b.png"))
        check("case does not count", NoteAssets.isReferenced("Shot.PNG", in: "![](assets/shot.png)"))
        check(
            "Unicode normalization does not count",
            NoteAssets.isReferenced("caf\u{E9}.png", in: "![](assets/cafe\u{301}.png)"))
        check("a parenthesis is encoded", NoteAssets.isReferenced("x(1).png", in: NoteAssets.markdown(for: "assets/x(1).png")))
        check("another file is not named", !NoteAssets.isReferenced("a.png", in: "![](assets/b.png)"))
    }

    private static func testDroppedAssetsGo() throws {
        let root = temporaryRoot("dropped")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let id = NoteID(rawValue: "Images")
        let opened = "![](assets/kept.png)\n![](assets/dropped.png)"
        try seed(repository, id, "![](assets/kept.png)\n![](assets/later.png)")
        let assets = repository.packageURL(for: id).appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        for name in ["kept.png", "dropped.png", "later.png", "pasted.png", "finder.png"] {
            try Data([1]).write(to: assets.appendingPathComponent(name))
        }
        let removed = try repository.removeDroppedAssets(of: id, earlier: [opened], imported: ["pasted.png"])
        check("a dropped and an imported image that the text no longer names go", removed == ["dropped.png", "pasted.png"])
        for name in ["kept.png", "later.png", "finder.png"] {
            check(
                "an image the session did not drop stays: \(name)",
                FileManager.default.fileExists(atPath: assets.appendingPathComponent(name).path))
        }
        let versions = NSFileVersion.otherVersionsOfItem(at: repository.packageURL(for: id)) ?? []
        check(
            "a version with the images comes before the delete",
            versions.count == 1
                && FileManager.default.fileExists(atPath: versions[0].url.appendingPathComponent("assets/dropped.png").path))
        check(
            "nothing to delete adds no version",
            try repository.removeDroppedAssets(of: id, earlier: [opened], imported: []).isEmpty
                && (NSFileVersion.otherVersionsOfItem(at: repository.packageURL(for: id)) ?? []).count == 1)
    }

    private static func testStoreDeletesDroppedImagesWhenTheSessionEnds() async throws {
        let root = temporaryRoot("session")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let id = NoteID(rawValue: "Album")
        let other = NoteID(rawValue: "Other")
        try seed(repository, other, "other")
        try seed(repository, id, "![](assets/a.png)")
        let assets = repository.packageURL(for: id).appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data([1]).write(to: assets.appendingPathComponent("a.png"))
        let store = NotesStore(repository: repository, loadSelection: { id })
        defer { store.stop() }
        _ = await store.start()
        check("the store opens the note with the image", store.activeID == id)
        store.updateSource("no image now")
        _ = await store.flush()
        check(
            "a removed reference keeps the file while the session lasts",
            FileManager.default.fileExists(atPath: assets.appendingPathComponent("a.png").path))
        _ = await store.select(other)
        check(
            "the switch to another note deletes the dropped image",
            !FileManager.default.fileExists(atPath: assets.appendingPathComponent("a.png").path))
        check("the other note opens", store.activeID == other)
    }

    private static func testStoreAddsVersions() async throws {
        let root = temporaryRoot("snapshots")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try repository(in: root)
        let id = NoteID(rawValue: "Diary")
        try seed(repository, id, "opened")
        let clock = ClockBox()
        let store = NotesStore(repository: repository, loadSelection: { id }, now: { clock.now })
        defer { store.stop() }
        _ = await store.start()
        func count() -> Int { (NSFileVersion.otherVersionsOfItem(at: repository.packageURL(for: id)) ?? []).count }
        store.updateSource("first edit")
        _ = await store.flush()
        check("the first save of a session keeps the note as it was opened", count() == 1)
        store.updateSource("second edit")
        _ = await store.flush()
        check("a save inside the interval adds no version", count() == 1)
        clock.now = clock.now.addingTimeInterval(NotesStore.snapshotInterval)
        store.updateSource("third edit")
        _ = await store.flush()
        check("a save after the interval adds one", count() == 2)

        let fileURL = repository.fileURL(for: id)
        let modified = try fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        store.updateSource("third edit, then undone")
        store.updateSource("third edit")
        _ = await store.flush()
        check(
            "an edit that comes back to the text on disk writes nothing",
            try fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified
                && !store.isDirty)
        let first = (NSFileVersion.otherVersionsOfItem(at: repository.packageURL(for: id)) ?? [])
            .min { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
        check(
            "the first version is the note as it was opened",
            first.map { (try? String(contentsOf: $0.url.appendingPathComponent("text.md"), encoding: .utf8)) == "opened" }
                == true)
    }

    /// Lays a note down as another app would: its package, then `text.md` inside it.
    private static func seed(_ repository: NotesRepository, _ id: NoteID, _ text: String) throws {
        try seed(repository, id, Data(text.utf8))
    }

    private static func seed(_ repository: NotesRepository, _ id: NoteID, _ data: Data) throws {
        try FileManager.default.createDirectory(
            at: repository.packageURL(for: id), withIntermediateDirectories: true)
        try data.write(to: repository.fileURL(for: id), options: .atomic)
    }

    private static func repository(in root: URL, support: URL? = nil) throws -> NotesRepository {
        let trash = trashDirectory(in: root)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return NotesRepository(
            notesDirectory: (support ?? root).appendingPathComponent("Notes", isDirectory: true),
            trashOperation: { url in
                try FileManager.default.moveItem(
                    at: url, to: trash.appendingPathComponent(url.lastPathComponent))
            })
    }

    private static func trashDirectory(in root: URL) -> URL {
        root.appendingPathComponent("Trash", isDirectory: true)
    }

    private static func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "noto-notes-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw TestFailure.missingValue }
        return value
    }

    @discardableResult
    private static func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private static func check(_ message: String, _ condition: @autoclosure () throws -> Bool) {
        do {
            if try condition() { return }
        } catch {
            print("FAIL: \(message) (\(error))")
            failures += 1
            return
        }
        print("FAIL: \(message)")
        failures += 1
    }
}

private final class SelectionBox: @unchecked Sendable {
    var id: NoteID?
}

private final class ClockBox: @unchecked Sendable {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
}

private enum TestFailure: Error {
    case missingValue
}
