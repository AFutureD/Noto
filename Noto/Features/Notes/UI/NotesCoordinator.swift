import AppKit
import SwiftUI
import os

@MainActor
@Observable
final class NotesCoordinator {
    private enum Presentation {
        case editor
        case create
        case search
    }

    private let store: NotesStore
    private let settings: NotoSettings
    private let cloudNotes: CloudNotesLocation
    private let dialogs: NotesDialogs
    @ObservationIgnored private lazy var windowController = NotesWindowController(coordinator: self)
    @ObservationIgnored private lazy var switcherController = NoteSwitcherWindowController(
        coordinator: self)
    @ObservationIgnored private lazy var barMenuController = NoteBarMenuWindowController(coordinator: self)
    @ObservationIgnored private lazy var emojiPickerController = NoteEmojiPickerWindowController(coordinator: self)
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var issueTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var operationID = 0
    @ObservationIgnored private var pendingIssue: NotesStore.Issue?
    private var pendingPresentation: Presentation?
    private(set) var isSwitcherPresented = false
    private(set) var switcherSelection: NoteID?
    private(set) var switcherFocusRevision = 0
    private(set) var characterCount = 0
    private(set) var formatting = NoteFormatting.plain
    private(set) var isFormattingBarExpanded: Bool
    private(set) var presentedBarMenu: NoteBarMenu?
    /// The editor's open `:` emoji list; the editor owns it and reports each change.
    private(set) var emojiPicker: NoteEmojiPicker?
    /// A press closes the menu before its button fires, so that button must not reopen it.
    @ObservationIgnored private var barMenuOpenAtPress: NoteBarMenu?
    /// Each menu button in the panel's flipped content space, reported by the bar as it lays out.
    @ObservationIgnored var barMenuButtonFrames: [NoteBarMenu: CGRect] = [:]
    private var switcherRename = NoteSwitcherRenameState()
    private var presentationGeneration = 0

    @ObservationIgnored private let saveFormattingBarExpanded: @Sendable (Bool) -> Void

    init(
        store: NotesStore,
        settings: NotoSettings,
        cloudNotes: CloudNotesLocation,
        dialogs: NotesDialogs,
        isFormattingBarExpanded: Bool = false,
        saveFormattingBarExpanded: @escaping @Sendable (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.settings = settings
        self.cloudNotes = cloudNotes
        self.dialogs = dialogs
        self.isFormattingBarExpanded = isFormattingBarExpanded
        self.saveFormattingBarExpanded = saveFormattingBarExpanded
        store.onIssue = { [weak self] issue in self?.present(issue) }
    }

    var editorInput: NoteEditorInput {
        NoteEditorInput(
            id: store.activeID ?? NoteID(rawValue: ""),
            source: store.source,
            epoch: store.editorEpoch)
    }

    var hasActiveNote: Bool { store.activeID != nil }
    /// The active note's folder: the base of its relative image paths.
    var activeFolderURL: URL? { store.activeFolderURL }
    /// UTF-16 units of the Markdown source.
    var characterCountLabel: String {
        characterCount == 1 ? "1 character" : "\(characterCount) characters"
    }

    var searchQueryBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.store.searchQuery ?? "" },
            set: { [weak self] in self?.store.updateSearchQuery($0) })
    }

    var activeTitle: String { store.activeTitle }
    var fonts: NoteFontSettings { settings.fonts }
    var highlightColor: NoteHighlightColor? { settings.highlightColor }
    var accentColor: NoteAccentColor? { settings.accentColor }
    var keepsOnTop: Bool { settings.keepsOnTop }
    var showsFormattingBar: Bool { settings.showsFormattingBar }
    var isSearching: Bool { store.isSearching }
    var visibleNotes: [NoteSummary] {
        store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? store.summaries : store.searchResults.map(\.summary)
    }
    var switcherEditingID: NoteID? { switcherRename.id }
    var isRenamingSwitcherNote: Bool { switcherRename.isActive }
    var switcherTitleDraftBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.switcherRename.draft ?? "" },
            set: { [weak self] in self?.switcherRename.updateDraft($0) })
    }

    /// Quit waits on this so the 300 ms autosave debounce cannot swallow the last edit.
    func prepareForTermination() async {
        await store.flush()
    }

    /// The command is a toggle, like every other surface: a second press puts the panel away.
    func toggle() {
        if windowController.isVisible {
            hide()
        } else {
            request(.editor)
        }
    }

    /// The Dock icon and the main menu only ever bring the panel forward.
    func show() {
        request(.editor)
    }

    func toggleKeepOnTop() {
        settings.keepsOnTop.toggle()
    }

    func createNote() {
        request(.create)
    }

    func searchNotes() {
        request(.search)
    }

    func openSwitcher() {
        guard store.isLoaded else { return }
        closeBarMenu()
        if isSwitcherPresented {
            switcherFocusRevision &+= 1
            return
        }
        isSwitcherPresented = true
        switcherSelection = store.activeID ?? store.summaries.first?.id
        switcherFocusRevision &+= 1
        windowController.presentSwitcher(switcherController)
    }

    func closeSwitcher(focusEditor: Bool = true) {
        guard isSwitcherPresented || !store.searchQuery.isEmpty else { return }
        switcherRename.cancel()
        isSwitcherPresented = false
        switcherSelection = nil
        store.cancelSearch()
        switcherController.hide()
        if focusEditor { windowController.focusEditor() }
    }

    func hide() {
        closeBarMenu()
        presentationGeneration &+= 1
        pendingPresentation = nil
        closeSwitcher(focusEditor: false)
        windowController.hide(restoreFocus: true)
        Task { await store.flush() }
    }

    func handleEscape() {
        if presentedBarMenu != nil {
            closeBarMenu()
        } else if isSwitcherPresented {
            closeSwitcher()
        } else {
            hide()
        }
    }

    func reconcileSwitcherSelection() {
        let notes = visibleNotes
        guard !notes.isEmpty else {
            switcherSelection = nil
            return
        }
        if let switcherSelection, notes.contains(where: { $0.id == switcherSelection }) { return }
        switcherSelection = notes.first?.id
    }

    func moveSwitcherSelection(by offset: Int) {
        let notes = visibleNotes
        guard !notes.isEmpty else {
            switcherSelection = nil
            return
        }
        guard let current = switcherSelection,
            let index = notes.firstIndex(where: { $0.id == current })
        else {
            switcherSelection = notes[offset < 0 ? notes.count - 1 : 0].id
            return
        }
        switcherSelection = notes[(index + offset + notes.count) % notes.count].id
    }

    func selectSwitcherNote() {
        guard let switcherSelection else { return }
        select(switcherSelection)
    }

    func activateSwitcherNote(_ id: NoteID) {
        switcherRename.cancel()
        select(id)
    }

    /// Renaming edits the filename, so the field starts from that and never from a derived line.
    func beginSwitcherRename(_ summary: NoteSummary) {
        switcherRename.begin(id: summary.id, title: summary.title)
    }

    func commitSwitcherRename() {
        guard let committed = switcherRename.commit() else { return }
        rename(committed.id, to: committed.title)
        switcherFocusRevision &+= 1
    }

    func cancelSwitcherRename() {
        guard switcherRename.isActive else { return }
        switcherRename.cancel()
        switcherFocusRevision &+= 1
    }

    func select(_ id: NoteID) {
        runOperation { [weak self] generation in
            guard let self else { return }
            let selected = await store.select(id) { [weak self] in
                self?.permitsCompletion(generation) ?? false
            }
            guard selected, !Task.isCancelled else { return }
            guard permitsCompletion(generation) else { return }
            closeSwitcher()
            windowController.show(focusEditor: true)
        }
    }

    func rename(_ id: NoteID, to title: String) {
        runOperation { [weak self] generation in
            guard let self else { return }
            let renamedID = await store.rename(id, to: title)
            guard let renamedID, !Task.isCancelled else { return }
            switcherSelection = renamedID
            if renamedID == store.activeID, permitsCompletion(generation) {
                windowController.show(focusEditor: false)
            }
        }
    }

    func trashSwitcherSelection() {
        guard let id = switcherSelection ?? store.activeID else { return }
        trash(id)
    }

    func handleDeleteShortcut() -> Bool {
        guard isSwitcherPresented, !switcherRename.isActive else { return false }
        trashSwitcherSelection()
        return true
    }

    func trash(_ id: NoteID) {
        guard let title = store.summaries.first(where: { $0.id == id })?.displayTitle else { return }
        runOperation { [weak self] generation in
            guard let self else { return }
            let confirmed = await dialogs.confirm(
                "Move “\(title)” to Trash?",
                "You can recover it from the Trash in Finder.",
                "Move to Trash")
            guard confirmed, !Task.isCancelled else { return }
            let switcherOrder = visibleNotes.map(\.id)
            let removed = await store.trash(id)
            guard removed, !Task.isCancelled else { return }
            switcherSelection = NoteSwitcherSelection.replacement(
                afterRemoving: id,
                from: switcherOrder,
                fallback: store.activeID ?? store.summaries.first?.id)
            // Nothing left to browse, so the empty state owns the window rather than a bare list.
            if store.summaries.isEmpty { closeSwitcher(focusEditor: false) }
            guard permitsCompletion(generation) else { return }
            windowController.show(focusEditor: !isSwitcherPresented)
        }
    }

    /// Points Notes at a folder as it is; nothing is moved out of the old one.
    func chooseNotesFolder() {
        guard
            let url = FolderPicker.choose(
                message: "Choose the folder your notes are kept in.",
                startingAt: store.notesDirectory)
        else { return }
        settings.notesFolder = AppPaths.contentFolderSetting(for: url, named: "Notes")
    }

    func resetNotesFolder() {
        settings.notesFolder = nil
    }

    /// The Settings switch. Off only moves back to this Mac's folder; nothing is copied or deleted.
    /// On asks whether this Mac's notes join iCloud. A switch flipped on another Mac does neither.
    func setSyncsWithICloud(_ on: Bool) {
        syncTask?.cancel()
        syncTask = nil
        guard on else {
            settings.syncsWithICloud = false
            return
        }
        guard !settings.syncsWithICloud else { return }
        syncTask = Task { [weak self] in
            await self?.turnOnICloudSync()
            self?.syncTask = nil
        }
    }

    func openNotesFolder() {
        guard let folderURL = store.activeFolderURL else {
            NSWorkspace.shared.open(store.notesDirectory)
            return
        }
        FileViewer.reveal(folderURL)
    }

    func moveToTopRight() {
        windowController.moveToTopRight()
    }

    func updateSource(_ source: String) {
        closeBarMenu()
        store.updateSource(source)
    }

    func importAssets(_ files: [URL], into id: NoteID) async -> [String]? {
        await store.importAssets(files, into: id)
    }

    func updateCharacterCount(_ input: NoteEditorInput, _ count: Int) {
        guard input == editorInput else { return }
        characterCount = count
    }

    /// Id and epoch, not the whole input: comparing a long source on every caret move is not free.
    func updateFormatting(_ input: NoteEditorInput, _ formatting: NoteFormatting) {
        let current = editorInput
        guard input.id == current.id, input.epoch == current.epoch, formatting != self.formatting else {
            return
        }
        self.formatting = formatting
    }

    func format(_ action: NoteEditAction) {
        windowController.format(action)
    }

    /// Collapsing takes the menu buttons with it, so no menu can outlive them.
    func toggleFormattingBar() {
        guard showsFormattingBar else { return }
        closeBarMenu()
        // Explicit, because the chord changes this from outside any view's transaction.
        withAnimation(Self.barMotion) { isFormattingBarExpanded.toggle() }
        saveFormattingBarExpanded(isFormattingBarExpanded)
    }

    private static var barMotion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? nil : Theme.MenuMotion.chevronAnimation
    }

    func toggleBarMenu(_ menu: NoteBarMenu) {
        let reopening = barMenuOpenAtPress == menu
        barMenuOpenAtPress = nil
        guard !reopening else { return }
        guard presentedBarMenu != menu else { return closeBarMenu() }
        closeBarMenu()
        presentedBarMenu = menu
        windowController.presentBarMenu(menu, with: barMenuController)
    }

    /// A menu row: the menu closes first, so the edit lands in a bar that is already settled.
    func choose(_ action: NoteEditAction) {
        closeBarMenu()
        format(action)
    }

    func closeBarMenu() {
        guard presentedBarMenu != nil else { return }
        presentedBarMenu = nil
        barMenuController.hide()
    }

    func noteWindowMouseDown() {
        barMenuOpenAtPress = presentedBarMenu
        closeBarMenu()
    }

    func editorReady(_ textView: NoteTextView) {
        textView.onEmojiPickerChange = { [weak self] picker, anchor in
            self?.presentEmojiPicker(picker, anchor: anchor)
        }
        windowController.editorReady(textView)
    }

    private func presentEmojiPicker(_ picker: NoteEmojiPicker?, anchor: NSRect) {
        emojiPicker = picker
        guard let picker else { return emojiPickerController.hide() }
        windowController.presentEmojiPicker(rows: picker.candidates.count, anchor: anchor, with: emojiPickerController)
    }

    /// A click on a row; the keys go to the editor directly.
    func chooseEmoji(at index: Int) {
        windowController.chooseEmoji(at: index)
    }

    private func request(_ presentation: Presentation) {
        closeBarMenu()
        pendingPresentation = presentation
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            // Create is its own load: the collection it would wait for is the one it adds to.
            let loaded = presentation == .create ? await store.create() : await store.start()
            loadTask = nil
            guard loaded, !Task.isCancelled else { return }
            // The note this task just made satisfies a create still pending; never make a second.
            if presentation == .create, pendingPresentation == .create {
                pendingPresentation = .editor
            }
            guard let next = pendingPresentation else { return }
            pendingPresentation = nil
            await present(next)
        }
    }

    private func present(_ presentation: Presentation) async {
        switch presentation {
        case .editor:
            closeSwitcher()
            windowController.show(focusEditor: true)
        case .create:
            let generation = presentationGeneration
            guard await store.create(), !Task.isCancelled,
                generation == presentationGeneration
            else { return }
            closeSwitcher()
            windowController.show(focusEditor: true)
        case .search:
            // The switcher hangs off the note window, so that window has to exist first.
            windowController.show(focusEditor: false)
            openSwitcher()
        }
    }

    private func turnOnICloudSync() async {
        guard let documents = await cloudNotes.refresh() else {
            _ = await dialogs.reportFailure(
                "iCloud Drive Is Off",
                "Sign in to iCloud and turn on iCloud Drive in System Settings, then turn on sync again.",
                nil)
            return
        }
        guard !Task.isCancelled else { return }
        let local = NotesRepository(notesDirectory: store.notesDirectory)
        let count = await Task.detached(priority: .userInitiated) { (try? local.list().count) ?? 0 }.value
        var copies = false
        if count > 0 {
            copies = await dialogs.choose(
                count == 1 ? "Copy 1 Note to iCloud?" : "Copy \(count) Notes to iCloud?",
                "The notes also stay in the folder on this Mac. "
                    + "A note iCloud already has with the same text is not copied again.",
                "Copy", "Don't Copy")
        }
        guard !Task.isCancelled else { return }
        settings.syncsWithICloud = true
        // Moved first, so nothing writes into the folder the copy reads from.
        await store.relocate(to: NotesRepository(notesDirectory: documents))
        guard copies else { return }
        let copied = await store.copyNotes(from: local)
        Logger.sync.info("copied \(copied, privacy: .public) of \(count, privacy: .public) notes to iCloud")
    }

    /// A newer show or hide retires an older operation's right to put what it loaded on screen.
    private func permitsCompletion(_ generation: Int) -> Bool {
        windowController.isVisible && generation == presentationGeneration
    }

    /// One collection operation at a time: a newer request cancels and supersedes an in-flight one.
    private func runOperation(_ body: @escaping @MainActor (Int) async -> Void) {
        operationTask?.cancel()
        operationID &+= 1
        let id = operationID
        let generation = presentationGeneration
        operationTask = Task { [weak self] in
            guard let self else { return }
            await body(generation)
            if self.operationID == id { self.operationTask = nil }
        }
    }

    private func present(_ issue: NotesStore.Issue) {
        guard issueTask == nil else {
            pendingIssue = issue
            return
        }
        issueTask = Task { [weak self] in
            guard let self else { return }
            switch issue {
            case .load(let failure):
                let retry = await dialogs.reportFailure(
                    "Couldn't Open Note", failure.localizedDescription, "Retry")
                if retry { _ = await store.reload() }
            case .save(let failure):
                let retry = await dialogs.reportFailure(
                    "Couldn't Save Note", failure.localizedDescription, "Retry")
                if retry { await store.retrySave() }
            case .operation(let failure):
                _ = await dialogs.reportFailure(
                    "Couldn't Update Note", failure.localizedDescription, nil)
            }
            issueTask = nil
            if let pendingIssue {
                self.pendingIssue = nil
                present(pendingIssue)
            }
        }
    }
}
