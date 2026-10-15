import AppKit
import Carbon.HIToolbox
import Foundation
import MDTextKit
import MDTextKitUI
import SwiftUI

@main
@MainActor
struct NotesEditorTests {
    private static var failures = 0

    static func main() async {
        _ = NSApplication.shared
        testSourceRoundTripAndNativeCommands()
        testUndoAndRedoShortcuts()
        testUndoIsolation(afterUndo: false)
        testUndoIsolation(afterUndo: true)
        testCharacterCountReports()
        testStylingKeepsSourceAndUndo()
        testHighlightBackground()
        testAccentColour()
        testListKeysAndChords()
        testHeadingsAndLinks()
        testFormattingReports()
        testCheckboxesAndLinkClicks()
        testTablesRenderAsGrids()
        testDeleteBeforeATableKeepsItsRows()
        testCustomFonts()
        testTextHeight()
        testHeightBeforeDraw()
        testEmojiQuery()
        print(failures == 0 ? "Notes editor tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testEmojiQuery() {
        func query(_ text: String) -> String? {
            let ns = text as NSString
            return NoteTextView.emojiQueryRange(in: ns, caret: NSRange(location: ns.length, length: 0))
                .map { ns.substring(with: $0.range) }
        }
        check("a query at a line start opens the list", query(":smi") == ":smi")
        check("a query after a space opens the list", query("好耶 :fire") == ":fire")
        check("a query inside a word does not", query("note:smi") == nil)
        check("one letter does not", query("a :s") == nil)
        check("a clock time does not", query("at 10:30") == nil)
        check("only the line under the caret counts", query(":smi\nplain") == nil)
        check("a query after a block marker opens the list", query("\u{FFFC}:tada") == ":tada")
        check(
            "a long line scans only its end",
            query(String(repeating: "word ", count: 400) + ":fire") == ":fire"
                && query(String(repeating: "x", count: 400) + ":fire") == nil)
    }

    private static func testSourceRoundTripAndNativeCommands() {
        let source = "# Heading\n\nThis is **bold** and [linked](https://example.com)."
        let input = NoteEditorInput(id: NoteID(rawValue: "Literal.md"), source: source, epoch: 1)
        var changes: [String] = []
        let editor = makeEditor(input: input, onSourceChange: { changes.append($0) })
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        check("the editor's Markdown is the installed source", editor.textView.markdown == source)
        check("the heading marker is an attachment", editor.textView.string.hasPrefix("\u{FFFC}Heading"))
        check("inline markers stay in the text", editor.textView.string.contains("**bold**"))
        check("the editor enables native Find", editor.textView.usesFindBar)
        editor.textView.find(.showFindInterface)
        check("Find opens in the editor", editor.textView.enclosingScrollView?.isFindBarVisible == true)
        editor.textView.find(.hideFindInterface)
        check("Find closes in the editor", editor.textView.enclosingScrollView?.isFindBarVisible == false)
        check("Find closes without changing the source", editor.textView.markdown == source)

        let boldRange = (editor.textView.string as NSString).range(of: "**bold**")
        editor.textView.setSelectedRange(boldRange)
        copySelection(of: editor.textView, to: pasteboard)
        check("native Copy writes Markdown", pasteboard.string(forType: .string) == "**bold**")

        cutSelection(of: editor.textView, to: pasteboard)
        check("native Cut publishes one source update", changes.count == 1)
        check("native Cut removes the selected source", !editor.textView.markdown.contains("**bold**"))
        editor.coordinator.editorUndoManager.undo()
        check("native Undo restores the source", editor.textView.markdown == source)
        editor.coordinator.editorUndoManager.redo()
        check("native Redo restores the cut", editor.textView.markdown == changes.last)

        let end = (editor.textView.string as NSString).length
        editor.textView.setSelectedRange(NSRange(location: end, length: 0))
        paste(" plain words", into: editor.textView, from: pasteboard)
        check("native Paste inserts exact text", editor.textView.markdown.hasSuffix(" plain words"))

        let unicode = " 🧑🏽‍💻e\u{301}"
        editor.textView.insertText(unicode, replacementRange: editor.textView.selectedRange())
        check("emoji and combining marks remain exact", editor.textView.markdown.hasSuffix(unicode))

        let markedLocation = (editor.textView.string as NSString).length
        editor.textView.setSelectedRange(NSRange(location: markedLocation, length: 0))
        editor.textView.setMarkedText(
            "語", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.textView.unmarkText()
        check("marked text commits through native AppKit editing", editor.textView.markdown.hasSuffix("語"))
        check("every published value is the editor's Markdown", changes.last == editor.textView.markdown)
    }

    private static func testUndoAndRedoShortcuts() {
        let source = "# Heading\n🧑🏽‍💻e\u{301}"
        let input = NoteEditorInput(id: NoteID(rawValue: "Undo.md"), source: source, epoch: 1)
        var changes: [String] = []
        var counts: [Int] = []
        let editor = makeEditor(
            input: input, onSourceChange: { changes.append($0) }, onCountChange: { _, count in counts.append(count) })
        let undo = keyDown("z", keyCode: kVK_ANSI_Z, in: editor.window)
        let redo = keyDown("Z", keyCode: kVK_ANSI_Z, modifiers: [.command, .shift], in: editor.window)
        editor.textView.setSelectedRange(NSRange(location: (editor.textView.string as NSString).length, length: 0))
        editor.textView.insertText(" edit", replacementRange: editor.textView.selectedRange())
        check("⌘Z reaches the editor through its window", editor.window.performKeyEquivalent(with: undo))
        check("⌘Z restores exact source", editor.textView.markdown == source)
        check("Undo publishes the restored source for autosave", changes == [source + " edit", source])
        check("Undo updates the character count", counts.last == (source as NSString).length)
        check("⌘⇧Z reaches the editor through its window", editor.window.performKeyEquivalent(with: redo))
        check("⌘⇧Z restores the edit", editor.textView.markdown == source + " edit")
        check("Redo publishes the restored edit for autosave", changes.last == source + " edit")
        check("Redo updates the character count", counts.last == ((source + " edit") as NSString).length)

        _ = editor.window.performKeyEquivalent(with: undo)
        editor.textView.insertText(" new", replacementRange: editor.textView.selectedRange())
        check("an edit after Undo discards Redo", !editor.coordinator.editorUndoManager.canRedo)
        let updated = editor.textView.markdown
        let changeCount = changes.count
        let repeatedUndo = keyDown("z", keyCode: kVK_ANSI_Z, isARepeat: true, in: editor.window)
        check("a held Undo shortcut is consumed", editor.window.performKeyEquivalent(with: repeatedUndo))
        check("a held Undo shortcut does not repeat", editor.textView.markdown == updated)
        for modifiers: NSEvent.ModifierFlags in [[.command, .option], [.command, .control]] {
            let event = keyDown("z", keyCode: kVK_ANSI_Z, modifiers: modifiers, in: editor.window)
            check("other Z chords leave history alone", !editor.textView.performKeyEquivalent(with: event))
        }
        editor.window.makeFirstResponder(nil)
        check("an unfocused editor does not claim Undo", !editor.textView.performKeyEquivalent(with: undo))
        check("unrelated shortcuts change nothing", editor.textView.markdown == updated && changes.count == changeCount)
        editor.window.makeFirstResponder(editor.textView)
        check("empty Redo is handled locally", editor.window.performKeyEquivalent(with: redo))
        check("empty Redo changes nothing", editor.textView.markdown == updated && changes.count == changeCount)

        editor.coordinator.update(NoteEditorInput(id: input.id, source: updated, epoch: input.epoch))
        check("a source echo preserves Undo", editor.coordinator.editorUndoManager.canUndo)
        _ = editor.window.performKeyEquivalent(with: undo)
        check("Undo after a source echo still restores the note", editor.textView.markdown == source)
        check("Undo after a source echo still publishes the note", changes.last == source)
    }

    private static func testUndoIsolation(afterUndo: Bool) {
        let first = NoteEditorInput(id: NoteID(rawValue: "First.md"), source: "First", epoch: 1)
        var changes: [String] = []
        let editor = makeEditor(input: first, onSourceChange: { changes.append($0) })
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        editor.textView.insertText(" edit", replacementRange: editor.textView.selectedRange())
        check("native editing registers Undo", editor.coordinator.editorUndoManager.canUndo)
        if afterUndo {
            editor.coordinator.editorUndoManager.undo()
            check("native Undo registers Redo", editor.coordinator.editorUndoManager.canRedo)
        }

        let second = NoteEditorInput(id: NoteID(rawValue: "Second.md"), source: "Second", epoch: 2)
        editor.coordinator.parent = view(for: second, onSourceChange: { changes.append($0) })
        editor.coordinator.update(second)
        check("switching notes installs the replacement source", editor.textView.markdown == "Second")
        check("switching notes clears stale Undo", !editor.coordinator.editorUndoManager.canUndo)
        check("switching notes clears stale Redo", !editor.coordinator.editorUndoManager.canRedo)
        editor.coordinator.editorUndoManager.undo()
        editor.coordinator.editorUndoManager.redo()
        check("Undo after a switch leaves the new note intact", editor.textView.markdown == "Second")

        editor.textView.setSelectedRange(NSRange(location: 6, length: 0))
        editor.textView.insertText(" draft", replacementRange: editor.textView.selectedRange())
        let external = NoteEditorInput(id: second.id, source: "External", epoch: 3)
        editor.coordinator.parent = view(for: external, onSourceChange: { changes.append($0) })
        editor.coordinator.update(external)
        check("a clean external reload replaces the displayed source", editor.textView.markdown == "External")
        check("a clean external reload clears stale Undo", !editor.coordinator.editorUndoManager.canUndo)
        check("a clean external reload clears stale Redo", !editor.coordinator.editorUndoManager.canRedo)
    }

    private static func testCharacterCountReports() {
        let first = NoteEditorInput(id: NoteID(rawValue: "First.md"), source: "# First", epoch: 1)
        var reports: [(NoteEditorInput, Int)] = []
        let editor = makeEditor(input: first, onCountChange: { reports.append(($0, $1)) })
        check("installing a note reports the length of its Markdown", reports.last?.1 == 7)

        editor.textView.selectAll(nil)
        editor.textView.insertText("Twelve chars", replacementRange: editor.textView.selectedRange())
        check("typing reports the new length", reports.last?.1 == 12)

        editor.textView.selectAll(nil)
        editor.textView.insertText("🇬🇧", replacementRange: editor.textView.selectedRange())
        check("the count is the Markdown's UTF-16 length", reports.last?.1 == 4)

        let second = NoteEditorInput(id: NoteID(rawValue: "Second.md"), source: "Second", epoch: 2)
        editor.coordinator.parent = view(for: second, onCountChange: { reports.append(($0, $1)) })
        editor.coordinator.update(second)
        check(
            "a stale count cannot be attributed to the replacement note",
            reports.last?.0.id == second.id && reports.last?.1 == 6)
    }

    private static let everyConstruct = """
        # Heading
        Some **bold**, _italic_, ~~gone~~, ==marked==, `code` and [a link](https://example.com) or https://a.com.
        - bullet
        \t- nested
        1. first
        - [ ] open task
        - [x] done task
        > quoted
        ---
        ```swift
        let x = 1
        ```
        | a | b |
        | --- | --- |
        | 1 | 2 |
        """

    private static func testStylingKeepsSourceAndUndo() {
        let input = NoteEditorInput(id: NoteID(rawValue: "Styled.md"), source: everyConstruct, epoch: 1)
        var changes: [String] = []
        let editor = makeEditor(input: input, onSourceChange: { changes.append($0) })
        check("styling never changes the Markdown", editor.textView.markdown == everyConstruct)
        check("styling publishes nothing", changes.isEmpty)
        check("styling registers no Undo", !editor.coordinator.editorUndoManager.canUndo)
        let text = editor.textView.string as NSString
        check(
            "a hidden marker keeps a tiny font",
            font(in: editor.textView, at: text.range(of: "**bold**").location)?.pointSize == 0.01)
        check(
            "bold text is drawn bold",
            font(in: editor.textView, at: text.range(of: "bold").location)?.isBold == true)
        editor.coordinator.setFonts(NoteFontSettings(size: 24))
        check("a font change does not touch the Markdown", editor.textView.markdown == everyConstruct && changes.isEmpty)
        check("a font change registers no Undo", !editor.coordinator.editorUndoManager.canUndo)
        check(
            "a font change restyles the text already on screen",
            font(in: editor.textView, at: text.range(of: "Some").location)?.pointSize == 24)
    }

    private static func testHighlightBackground() {
        let source = "Some ==marked== words"
        let input = NoteEditorInput(id: NoteID(rawValue: "Highlight.md"), source: source, epoch: 1)
        let editor = makeEditor(input: input)
        let marked = (editor.textView.string as NSString).range(of: "marked").location
        let themed = NSColor(Theme.Colors.highlight)
        check(
            "a highlight draws the theme's colour until one is chosen",
            background(in: editor.textView, at: marked)?.isSameColor(as: themed) == true)
        editor.coordinator.setHighlight(NoteHighlightColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8))
        check(
            "a chosen colour replaces the theme's",
            background(in: editor.textView, at: marked)?.isSameColor(
                as: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)) == true)
        editor.coordinator.setHighlight(nil)
        check(
            "Use Default returns to the theme's colour",
            background(in: editor.textView, at: marked)?.isSameColor(as: themed) == true)
        check("the highlight setting never changes the Markdown", editor.textView.markdown == source)
    }

    private static func testAccentColour() {
        let source = "Some ~marked~ words and a [link](https://example.com)"
        let input = NoteEditorInput(id: NoteID(rawValue: "Accent.md"), source: source, epoch: 1)
        let editor = makeEditor(input: input)
        let textView = editor.textView
        let marked = (textView.string as NSString).range(of: "marked").location
        func underline() -> NSColor? {
            textView.textStorage?.attribute(.underlineColor, at: marked, effectiveRange: nil) as? NSColor
        }
        func link() -> NSColor? { textView.linkTextAttributes?[.foregroundColor] as? NSColor }
        func selection() -> NSColor? { textView.selectedTextAttributes[.backgroundColor] as? NSColor }
        let system = NSColor.controlAccentColor
        check("an underline draws the macOS accent until one is chosen", underline()?.isSameColor(as: system) == true)
        check("a link draws the macOS accent until one is chosen", link()?.isSameColor(as: system) == true)
        check(
            "the selection is the macOS accent at the fixed alpha",
            selection()?.isSameColor(as: system.withAlphaComponent(NoteEditorTheme.selectionAlpha)) == true)
        editor.coordinator.setAccent(NoteAccentColor(red: 0.8, green: 0.1, blue: 0.2))
        let chosen = NSColor(srgbRed: 0.8, green: 0.1, blue: 0.2, alpha: 1)
        check("a chosen accent colours the underline", underline()?.isSameColor(as: chosen) == true)
        check("a chosen accent colours links", link()?.isSameColor(as: chosen) == true)
        check(
            "a chosen accent colours the selection at the fixed alpha",
            selection()?.isSameColor(as: chosen.withAlphaComponent(NoteEditorTheme.selectionAlpha)) == true)
        editor.coordinator.setAccent(nil)
        check("Use Default returns to the macOS accent", underline()?.isSameColor(as: system) == true)
        check("the accent setting never changes the Markdown", textView.markdown == source)
    }

    private static func testListKeysAndChords() {
        var changes: [String] = []
        let input = NoteEditorInput(id: NoteID(rawValue: "Keys.md"), source: "- item", epoch: 1)
        let editor = makeEditor(input: input, onSourceChange: { changes.append($0) })
        let undo = editor.coordinator.editorUndoManager
        editor.textView.setSelectedRange(NSRange(location: (editor.textView.string as NSString).length, length: 0))
        editor.textView.insertNewline(nil)
        check(
            "Return continues a list in one published edit",
            editor.textView.markdown == "- item\n- " && changes.last == "- item\n- ")
        undo.undo()
        check("one Undo step removes the continuation", editor.textView.markdown == "- item")
        undo.redo()
        check("Redo brings the continuation back", editor.textView.markdown == "- item\n- ")
        editor.textView.insertNewline(nil)
        check("Return on an empty item drops its marker", editor.textView.markdown == "- item\n")

        let chord = NoteEditorInput(id: NoteID(rawValue: "Chord.md"), source: "make bold", epoch: 3)
        editor.coordinator.update(chord)
        editor.textView.setSelectedRange(NSRange(location: 5, length: 4))
        check(
            "⌘B wraps the selection and claims the chord",
            editor.textView.performKeyEquivalent(with: keyDown("b", keyCode: kVK_ANSI_B, in: editor.window))
                && editor.textView.markdown == "make **bold**")
        undo.undo()
        check("⌘B undoes in one step", editor.textView.markdown == "make bold")
        check(
            "⌘U underlines the selection",
            editor.textView.performKeyEquivalent(with: keyDown("u", keyCode: kVK_ANSI_U, in: editor.window))
                && editor.textView.markdown == "make ~bold~"
                && editor.textView.formatting.inlineStyles.contains(.underline))
        undo.undo()
        check("⌘U undoes in one step", editor.textView.markdown == "make bold")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 4))
        _ = editor.textView.performKeyEquivalent(
            with: keyDown("8", keyCode: kVK_ANSI_8, modifiers: [.command, .shift], in: editor.window))
        check("⇧⌘8 matches its digit by key code", editor.textView.markdown == "- make bold")
        undo.undo()

        editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        check(
            "⌥⌘C fences the line and claims the chord",
            editor.textView.performKeyEquivalent(
                with: keyDown("c", keyCode: kVK_ANSI_C, modifiers: [.command, .option], in: editor.window))
                && editor.textView.markdown.hasPrefix("```\nmake bold\n```"))
        undo.undo()
        check("⌥⌘C undoes in one step", editor.textView.markdown == "make bold")
        check(
            "⇧⌘B quotes the line and claims the chord",
            editor.textView.performKeyEquivalent(
                with: keyDown("B", keyCode: kVK_ANSI_B, modifiers: [.command, .shift], in: editor.window))
                && editor.textView.markdown == "> make bold")
        undo.undo()
        check("⇧⌘B undoes in one step", editor.textView.markdown == "make bold")
    }

    private static func testHeadingsAndLinks() {
        let input = NoteEditorInput(id: NoteID(rawValue: "Headings.md"), source: "title", epoch: 1)
        let editor = makeEditor(input: input)
        editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        editor.textView.format(.setHeading(level: 2))
        check("the heading menu sets a level", editor.textView.markdown == "## title")
        editor.textView.format(.setHeading(level: 2))
        check("choosing the current level changes nothing", editor.textView.markdown == "## title")
        editor.textView.format(.setHeading(level: 1))
        check("choosing another level replaces it", editor.textView.markdown == "# title")
        editor.textView.format(.setHeading(level: 0))
        check("Text makes the paragraph plain", editor.textView.markdown == "title")
        _ = editor.textView.performKeyEquivalent(
            with: keyDown("3", keyCode: kVK_ANSI_3, modifiers: [.command, .option], in: editor.window))
        check("⌥⌘3 matches its digit by key code", editor.textView.markdown == "### title")

        let link = NoteEditorInput(id: NoteID(rawValue: "Link.md"), source: "see docs", epoch: 2)
        editor.coordinator.update(link)
        editor.textView.setSelectedRange(NSRange(location: 4, length: 4))
        editor.textView.format(.toggleLink)
        check("⌘K wraps the selection as a link", editor.textView.markdown == "see [docs]()")
        editor.textView.insertText("https://a.com", replacementRange: editor.textView.selectedRange())
        check("the caret waits inside the parentheses", editor.textView.markdown == "see [docs](https://a.com)")
        let label = (editor.textView.string as NSString).range(of: "docs")
        editor.textView.setSelectedRange(NSRange(location: label.location + 1, length: 0))
        check("a caret in a link reports one", editor.textView.formatting.isLink)
        editor.textView.format(.toggleLink)
        check("⌘K in a link unwraps it to its label", editor.textView.markdown == "see docs")
    }

    private static func testFormattingReports() {
        var reports: [(NoteEditorInput, NoteFormatting)] = []
        let input = NoteEditorInput(id: NoteID(rawValue: "Formatting.md"), source: "plain **bold**", epoch: 1)
        let editor = makeEditor(input: input, onFormattingChange: { reports.append(($0, $1)) })
        check("install reports formatting", reports.last?.0.id == input.id)

        editor.textView.setSelectedRange(NSRange(location: 10, length: 0))
        check("a caret inside bold reports bold", reports.last?.1.inlineStyles == [.bold])
        editor.textView.setSelectedRange(NSRange(location: 1, length: 0))
        check(
            "a caret in plain text reports a paragraph",
            reports.last?.1.inlineStyles == [] && reports.last?.1.headingLevel == 0)

        editor.textView.format(.toggleQuote)
        check(
            "format(_:) applies the toggle and reports the result",
            editor.textView.markdown == "> plain **bold**" && reports.last?.1.isQuote == true)
        editor.coordinator.editorUndoManager.undo()
        check("format(_:) undoes in one step", editor.textView.markdown == "plain **bold**")
        editor.textView.format(.toggleList(.task))
        check(
            "a task toggle reports a task list",
            editor.textView.markdown == "- [ ] plain **bold**" && reports.last?.1.list == .task)
    }

    private static func testCheckboxesAndLinkClicks() {
        var changes: [String] = []
        let source = "- [ ] first\n- [ ] second\nend"
        let input = NoteEditorInput(id: NoteID(rawValue: "Boxes.md"), source: source, epoch: 1)
        let editor = makeEditor(input: input, onSourceChange: { changes.append($0) })
        let caret = NSRange(location: (editor.textView.string as NSString).length, length: 0)
        editor.textView.setSelectedRange(caret)
        guard let box = taskAttachment(in: editor.textView, ordinal: 1) else {
            return check("the second task lays out a checkbox", false)
        }
        editor.textView.textView(editor.textView, clickedOn: box.cell, in: .zero, at: box.index)
        check(
            "clicking a checkbox toggles it in one published edit",
            editor.textView.markdown == "- [ ] first\n- [x] second\nend" && changes.last == editor.textView.markdown)
        editor.coordinator.editorUndoManager.undo()
        check("Undo restores the checkbox", editor.textView.markdown == source)

        var opened: [URL] = []
        editor.coordinator.open = { opened.append($0) }
        editor.textView.openURL(URL(fileURLWithPath: "/etc/hosts"))
        check("a file link never opens", opened.isEmpty)
        let web = URL(string: "https://example.com")!
        _ = editor.textView.textView(editor.textView, clickedOnLink: web, at: 0)
        check("a web link opens", opened == [web])
        _ = editor.textView.textView(editor.textView, clickedOnLink: "mailto:a@b.c", at: 0)
        check("a mail link opens", opened.last?.absoluteString == "mailto:a@b.c")
    }

    private static func testTablesRenderAsGrids() {
        let source = "| a | b |\n| --- | --- |\n| 1 | 2 |\n"
        let input = NoteEditorInput(id: NoteID(rawValue: "Table.md"), source: source, epoch: 1)
        let editor = makeEditor(input: input)
        check("a pipe table becomes one grid attachment", grids(in: editor.textView) == 1)
        check("the grid stands for the table's Markdown", editor.textView.markdown == source)
    }

    private static func testDeleteBeforeATableKeepsItsRows() {
        let table = "| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n"
        let source = "## Heading\n\n\(table)\nAfter\n"
        let joined = "## Heading\n\(table)\nAfter\n"
        let input = NoteEditorInput(id: NoteID(rawValue: "Table.md"), source: source, epoch: 1)
        let editor = makeEditor(input: input)
        let blankLine = (editor.textView.string as NSString).range(of: "\n\n").location + 1

        editor.textView.setSelectedRange(NSRange(location: blankLine, length: 0))
        editor.textView.deleteBackward(nil)
        check("Delete on the blank line before a table keeps its rows", editor.textView.markdown == joined)
        check("the table stays one grid after the Delete", grids(in: editor.textView) == 1)
        editor.coordinator.editorUndoManager.undo()
        check("undo restores the blank line before the table", editor.textView.markdown == source)

        editor.textView.setSelectedRange(NSRange(location: blankLine, length: 0))
        editor.textView.deleteForward(nil)
        check("forward Delete on the blank line keeps the rows too", editor.textView.markdown == joined)
    }

    private static func testCustomFonts() {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        guard installed.isSuperset(of: ["Menlo", "Monaco", "Songti SC"]) else {
            print("SKIP: custom font checks need Menlo, Monaco and Songti SC")
            return
        }
        let source = "Plain 你好 **粗体 bold**\n\n`code 字`\n\n# Head 题"
        let input = NoteEditorInput(id: NoteID(rawValue: "Fonts.md"), source: source, epoch: 1)
        let editor = makeEditor(input: input)
        let text = editor.textView.string as NSString
        editor.textView.setSelectedRange(NSRange(location: text.length, length: 0))
        editor.coordinator.setFonts(
            NoteFontSettings(textFamily: "Menlo", cjkFamily: "Songti SC", codeFamily: "Monaco", size: 20))
        let plain = text.range(of: "Plain").location
        check("a font change restyles the text already on screen", font(in: editor.textView, at: plain)?.familyName == "Menlo")
        check("the size setting is the body size", font(in: editor.textView, at: plain)?.pointSize == 20)
        check(
            "typing continues in the chosen font",
            (editor.textView.typingAttributes[.font] as? NSFont)?.familyName == "Menlo")
        check("Latin text is drawn by the text family", drawnFamily(in: editor.textView, at: plain) == "Menlo")
        check(
            "CJK text is drawn by the CJK family",
            drawnFamily(in: editor.textView, at: text.range(of: "你好").location) == "Songti SC")
        let boldCJK = text.range(of: "粗体").location
        check(
            "bold reaches the cascaded CJK face",
            drawnFont(in: editor.textView, at: boldCJK)?.isBold == true
                && drawnFamily(in: editor.textView, at: boldCJK) == "Songti SC")
        let code = text.range(of: "code").location
        check("inline code is drawn by the code family", drawnFamily(in: editor.textView, at: code) == "Monaco")
        check(
            "CJK inside code is drawn by the CJK family",
            drawnFamily(in: editor.textView, at: text.range(of: "字").location) == "Songti SC")
        let head = text.range(of: "Head").location
        check("a heading follows the text family when it has none", font(in: editor.textView, at: head)?.familyName == "Menlo")
        check("a heading keeps its weight", font(in: editor.textView, at: head)?.isBold == true)
        editor.coordinator.setFonts(NoteFontSettings(textFamily: "No Such Family"))
        check(
            "an uninstalled family falls back to the system font",
            font(in: editor.textView, at: plain)?.familyName == NSFont.systemFont(ofSize: 12).familyName)
        check("the font settings never change the Markdown", editor.textView.markdown == source)
    }

    private static func testTextHeight() {
        let input = NoteEditorInput(id: NoteID(rawValue: "Sizing.md"), source: "", epoch: 0)
        let editor = makeEditor(input: input)
        let emptyHeight = editor.textView.textHeight(upTo: .infinity)
        check("an empty note measures shorter than the visible area", emptyHeight < editor.textView.frame.height)

        let lines = String(repeating: "A line of text\n", count: 20)
        editor.textView.insertText(lines, replacementRange: editor.textView.selectedRange())
        let multilineHeight = editor.textView.textHeight(upTo: .infinity)
        check("new lines grow the measured height at once", multilineHeight > emptyHeight)

        let wrappedText = String(repeating: "wrapped words ", count: 80)
        editor.textView.insertText(wrappedText, replacementRange: editor.textView.selectedRange())
        let wrappedHeight = editor.textView.textHeight(upTo: .infinity)
        check("wrapped text grows the measured height without a newline", wrappedHeight > multilineHeight)

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        paste("\n" + lines, into: editor.textView, from: pasteboard)
        check("paste grows the measured height", editor.textView.textHeight(upTo: .infinity) > wrappedHeight)

        editor.textView.selectAll(nil)
        editor.textView.deleteBackward(nil)
        check(
            "deleting the text shrinks the measured height back",
            editor.textView.textHeight(upTo: .infinity) == emptyHeight)
    }

    /// The fit reads before any draw, so each height here is read right after its edit returns.
    private static func testHeightBeforeDraw() {
        let notes = [
            ("list", "Ideas:\n- First\n- Second\n- Third"), ("mixed", everyConstruct), ("trailing newline", "a\n- b\n")
        ]
        for (name, source) in notes {
            checkHeightBeforeDraw(of: "\(name) note", source: source)
        }

        let long = makeEditor(
            input: NoteEditorInput(
                id: NoteID(rawValue: "Long.md"), source: String(repeating: "- Item\n", count: 60), epoch: 0))
        let limit = Theme.Size.noteWindowMaxHeight
        let measured = long.textView.textHeight(upTo: limit)
        check("a note taller than the window still measures past its limit", measured >= limit)
        check(
            "measuring stops near the limit instead of laying out the rest",
            measured < laidOutHeight(of: long.textView))
    }

    private static func checkHeightBeforeDraw(of note: String, source: String) {
        let editor = makeEditor(
            input: NoteEditorInput(id: NoteID(rawValue: "Heights.md"), source: source, epoch: 0))
        let textView = editor.textView
        let length = { (textView.string as NSString).length }
        func edit(_ name: String, at location: Int? = nil, _ change: () -> Void) {
            if let location { textView.setSelectedRange(NSRange(location: location, length: 0)) }
            change()
            let measured = textView.textHeight(upTo: Theme.Size.noteWindowMaxHeight)
            check(
                "\(name) in a \(note) measures its height before a draw",
                measured == laidOutHeight(of: textView))
        }
        edit("typing at the end", at: length()) {
            textView.insertText("x", replacementRange: textView.selectedRange())
        }
        edit("Return at the end") { textView.insertNewline(nil) }
        edit("Return in the middle", at: length() / 2) { textView.insertNewline(nil) }
        edit("typing in the middle") { textView.insertText("y", replacementRange: textView.selectedRange()) }
        edit("Delete in the middle") { textView.deleteBackward(nil) }
        edit("Return at the start", at: 0) { textView.insertNewline(nil) }
        edit("undo") { editor.coordinator.editorUndoManager.undo() }
        edit("switching notes") {
            editor.coordinator.update(NoteEditorInput(id: NoteID(rawValue: "Other.md"), source: source, epoch: 0))
        }
        edit("deleting everything") {
            textView.selectAll(nil)
            textView.deleteBackward(nil)
        }
        withExtendedLifetime(editor) {}
    }

    /// Where the last line sits once the whole note is laid out, as a draw would leave it.
    private static func laidOutHeight(of textView: NSTextView) -> CGFloat {
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return -1 }
        manager.ensureLayout(for: container)
        return manager.usedRect(for: container).height + textView.textContainerInset.height * 2
    }

    // MARK: - Helpers

    private static func keyDown(
        _ characters: String, keyCode: Int, modifiers: NSEvent.ModifierFlags = .command, isARepeat: Bool = false,
        in window: NSWindow
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters.lowercased(), isARepeat: isARepeat, keyCode: UInt16(keyCode))!
    }

    /// The `ordinal`th task checkbox in the storage: its index and the cell AppKit clicks.
    private static func taskAttachment(
        in textView: NoteTextView, ordinal: Int
    ) -> (index: Int, cell: any NSTextAttachmentCellProtocol)? {
        let storage = textView.mdTextStorage
        var found: [(Int, any NSTextAttachmentCellProtocol)] = []
        let whole = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.attachment, in: whole, options: []) { value, range, _ in
            if let task = value as? MDTaskTextAttachment, let cell = task.attachmentCell {
                found.append((range.location, cell))
            }
        }
        return ordinal < found.count ? found[ordinal] : nil
    }

    /// The font Core Text picks for the glyph, which is the cascade's choice, not the attribute.
    private static func drawnFont(in textView: NSTextView, at location: Int) -> NSFont? {
        guard let storage = textView.textStorage else { return nil }
        let piece = storage.attributedSubstring(from: NSRange(location: location, length: 1))
        let runs = CTLineGetGlyphRuns(CTLineCreateWithAttributedString(piece)) as? [CTRun]
        guard let run = runs?.first else { return nil }
        return (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as? NSFont
    }

    private static func drawnFamily(in textView: NSTextView, at location: Int) -> String? {
        drawnFont(in: textView, at: location)?.familyName
    }

    private static func font(in textView: NSTextView, at location: Int) -> NSFont? {
        textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    private static func grids(in textView: NoteTextView) -> Int {
        var grids = 0
        textView.mdTextStorage.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: textView.mdTextStorage.length), options: []
        ) { value, _, _ in
            if value is MDTableTextAttachment { grids += 1 }
        }
        return grids
    }

    /// The layout manager draws a highlight from its own attribute, not `.backgroundColor`.
    private static func background(in textView: NSTextView, at location: Int) -> NSColor? {
        textView.textStorage?.attribute(.mdHighlighterBackgroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    /// The primitives `copy:`/`cut:`/`paste:` delegate to; the actions clobber the real clipboard.
    private static func copySelection(of textView: NSTextView, to pasteboard: NSPasteboard) {
        let types = textView.writablePasteboardTypes
        pasteboard.declareTypes(types, owner: nil)
        _ = textView.writeSelection(to: pasteboard, types: types)
    }

    private static func cutSelection(of textView: NSTextView, to pasteboard: NSPasteboard) {
        copySelection(of: textView, to: pasteboard)
        textView.delete(nil)
    }

    private static func paste(_ text: String, into textView: NSTextView, from pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        _ = textView.readSelection(from: pasteboard)
    }

    private static func makeEditor(
        input: NoteEditorInput,
        onSourceChange: @escaping (String) -> Void = { _ in },
        onCountChange: @escaping (NoteEditorInput, Int) -> Void = { _, _ in },
        onFormattingChange: @escaping (NoteEditorInput, NoteFormatting) -> Void = { _, _ in }
    ) -> (coordinator: NoteEditorView.Coordinator, textView: NoteTextView, window: NSWindow) {
        let view = view(
            for: input, onSourceChange: onSourceChange, onCountChange: onCountChange,
            onFormattingChange: onFormattingChange)
        let coordinator = NoteEditorView.Coordinator(parent: view)
        let textView = coordinator.textView
        textView.setFrameSize(NSSize(width: 320, height: 1))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        scrollView.documentView = textView
        let window = KeyWindow(contentRect: scrollView.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = scrollView
        coordinator.install(input)
        window.makeFirstResponder(textView)
        return (coordinator, textView, window)
    }

    private static func view(
        for input: NoteEditorInput,
        onSourceChange: @escaping (String) -> Void = { _ in },
        onCountChange: @escaping (NoteEditorInput, Int) -> Void = { _, _ in },
        onFormattingChange: @escaping (NoteEditorInput, NoteFormatting) -> Void = { _, _ in }
    ) -> NoteEditorView {
        NoteEditorView(
            input: input, onSourceChange: onSourceChange, onCharacterCountChange: onCountChange,
            onFormattingChange: onFormattingChange, onImportFiles: { _, _ in nil }, onReady: { _ in })
    }

    private static func check(_ message: String, _ condition: @autoclosure () -> Bool) {
        guard condition() else {
            failures += 1
            print("FAIL: \(message)")
            return
        }
    }
}

extension NSColor {
    /// Compared in sRGB under the current appearance, so a dynamic colour meets its static twin.
    func isSameColor(as other: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01 && abs(a.alphaComponent - b.alphaComponent) < 0.01
    }
}

/// A harness window cannot become key without an active app, and the editor reveals only when key.
private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
