import AppKit
import MDTextKit
import MDTextKitUI
import os

/// The note editor: `MDTextView` plus Noto's chords, the window fit's height, the placeholder and focus.
@MainActor
final class NoteTextView: MDTextView {
    /// Tracked here because the window still names this view first responder while it resigns.
    private var isFirstResponder = false

    var isFocused: Bool { isFirstResponder && window?.isKeyWindow == true }

    /// The formatting bar's way in: the same toggle, gate and undo step as the matching chord.
    func format(_ action: NoteEditAction) {
        guard !hasMarkedText() else { return }
        switch action {
        case .toggleInline(.bold): editorController.toggleStrong(in: self)
        case .toggleInline(.italic): editorController.toggleEmphasis(in: self)
        case .toggleInline(.strikethrough): editorController.toggleStrikethrough(in: self)
        case .toggleInline(.underline): editorController.toggleUnderline(in: self)
        case .toggleInline(.highlight): editorController.toggleHighlighter(in: self)
        case .toggleInline(.code): editorController.toggleCode(in: self)
        case .toggleLink: toggleLink()
        case .setHeading(let level): setHeading(level)
        case .toggleList(.bullet): editorController.toggleUnorderedList(in: self)
        case .toggleList(.ordered): editorController.toggleOrderedList(in: self)
        case .toggleList(.task): editorController.toggleTaskList(in: self)
        case .toggleCodeBlock: editorController.toggleCodeBlock(in: self)
        case .toggleQuote: editorController.toggleBlockQuote(in: self)
        }
    }

    var formatting: NoteFormatting { NoteFormatting(editorController.formatting(in: self)) }

    func find(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
    }

    /// The frame never gets shorter than the clip view, so only the layout knows the text's height.
    func textHeight(upTo limit: CGFloat) -> CGFloat {
        guard let layoutManager, let textContainer else { return frame.height }
        let insets = textContainerInset.height * 2
        // Lays out the top `limit` points only, so a long note costs no more than the window shows.
        let probe = CGRect(x: 0, y: 0, width: textContainer.size.width, height: limit)
        let glyphs = layoutManager.glyphRange(forBoundingRect: probe, in: textContainer)
        if glyphs.length > 0, NSMaxRange(glyphs) < layoutManager.numberOfGlyphs {
            let last = layoutManager.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
            return last.maxY + insets
        }
        return layoutManager.usedRect(for: textContainer).height + insets
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard mdTextStorage.length == 0 else { return }
        var attributes = editorController.attributedStringRenderer.defaultTextAttributes
        attributes[.foregroundColor] = NSColor(Theme.Colors.textTertiary)
        NSAttributedString(string: "Start writing…", attributes: attributes).draw(at: textContainerOrigin)
    }

    // MARK: - Formatting

    /// Set, not toggle: the heading menu names a level, and choosing the current one changes nothing.
    private func setHeading(_ level: Int) {
        let current = editorController.formatting(in: self).headingLevel ?? 0
        if level == 0 {
            guard current > 0 else { return }
            editorController.toggleHeading(in: self, headingLevel: current)
        } else if current != level {
            editorController.toggleHeading(in: self, headingLevel: level)
        }
    }

    /// Wraps the selection as `[selection]()` with the caret in the parentheses, or unwraps a link.
    private func toggleLink() {
        let storage = mdTextStorage
        let selection = selectedRange()
        if storage.isRangeInsideLink(selection) {
            let link = storage.linkRange(at: selection.location)
            guard link.location != NSNotFound,
                let match = storage.stringByExpandingTextAttachments(in: link).firstMatch(of: /\[(.*?)\]\(.*\)/)
            else { return }
            editorController.replaceCharacters(in: link, with: NSAttributedString(string: String(match.1)), in: self)
            return
        }
        let replacement = "[\(storage.stringByExpandingTextAttachments(in: selection))]()"
        editorController.replaceCharacters(in: selection, with: NSAttributedString(string: replacement), in: self)
        setSelectedRange(NSRange(location: selection.location + (replacement as NSString).length - 1, length: 0))
    }

    // MARK: - Keys

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.charactersIgnoringModifiers?.lowercased() == "z",
            modifiers == .command || modifiers == [.command, .shift]
        {
            guard !event.isARepeat else { return true }
            breakUndoCoalescing()
            if modifiers == .command {
                editorUndoManager.undo()
            } else {
                editorUndoManager.redo()
            }
            return true
        }
        guard let action = Self.chord(for: event) else {
            return super.performKeyEquivalent(with: event)
        }
        if !event.isARepeat { format(action) }
        return true
    }

    /// The digit key codes, stated here so a local chord needs no Carbon.
    private enum DigitKey {
        static let zero: UInt16 = 0x1D
        static let one: UInt16 = 0x12
        static let two: UInt16 = 0x13
        static let three: UInt16 = 0x14
        static let seven: UInt16 = 0x1A
        static let eight: UInt16 = 0x1C
        static let nine: UInt16 = 0x19
    }

    /// Digits match by key code, since shifted and optioned digits vary by keyboard layout.
    private static func chord(for event: NSEvent) -> NoteEditAction? {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch modifiers {
        case [.command]:
            switch key {
            case "b": return .toggleInline(.bold)
            case "i": return .toggleInline(.italic)
            case "e": return .toggleInline(.code)
            case "u": return .toggleInline(.underline)
            case "k": return .toggleLink
            default: return nil
            }
        case [.command, .shift]:
            if key == "x" { return .toggleInline(.strikethrough) }
            if key == "h" { return .toggleInline(.highlight) }
            if key == "b" { return .toggleQuote }
            switch event.keyCode {
            case DigitKey.seven: return .toggleList(.ordered)
            case DigitKey.eight: return .toggleList(.bullet)
            case DigitKey.nine: return .toggleList(.task)
            default: return nil
            }
        case [.command, .option]:
            if key == "c" { return .toggleCodeBlock }
            switch event.keyCode {
            case DigitKey.one: return .setHeading(level: 1)
            case DigitKey.two: return .setHeading(level: 2)
            case DigitKey.three: return .setHeading(level: 3)
            case DigitKey.zero: return .setHeading(level: 0)
            default: return nil
            }
        default:
            return nil
        }
    }

    // MARK: - Files

    /// Dropped or pasted files: the images import, everything else is ignored. MDTextKit's reader
    /// looks only at the first file and inserts a folder's path as text, so Noto decides here.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let files = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL], !files.isEmpty
        else { return super.readSelection(from: pboard, type: type) }
        let images = files.filter(NoteAssets.isImage)
        if images.count < files.count {
            Logger.notes.notice("ignored \(files.count - images.count) dropped files that are not images")
        }
        if !images.isEmpty { addFilesBlock?(images, rangeForUserTextChange) }
        return true
    }

    // MARK: - Emoji

    /// Reports the open emoji list with the screen rect of its `:`, or nil when the list closes.
    var onEmojiPickerChange: ((NoteEmojiPicker?, NSRect) -> Void)?
    /// The `:query` under the caret and its list, while the list is open.
    private var emojiQuery: EmojiQuery?
    /// The query Escape closed; the list stays shut until the query changes.
    private var dismissedEmojiRange: NSRange?

    private struct EmojiQuery: Equatable {
        let range: NSRange
        var picker: NoteEmojiPicker
    }

    /// Return and Tab take the selected emoji, the arrows move through the list. Escape never gets
    /// here: the panel claims it and asks `dismissEmojiPicker` first.
    override func doCommand(by selector: Selector) {
        guard var query = emojiQuery else { return super.doCommand(by: selector) }
        switch selector {
        case #selector(moveUp(_:)):
            query.picker.moveSelection(by: -1)
            setEmojiQuery(query)
        case #selector(moveDown(_:)):
            query.picker.moveSelection(by: 1)
            setEmojiQuery(query)
        case #selector(insertNewline(_:)), #selector(insertTab(_:)):
            chooseEmoji(at: query.picker.selection)
        default:
            super.doCommand(by: selector)
        }
    }

    /// Replaces `:query` with the emoji as one undo step.
    func chooseEmoji(at index: Int) {
        guard let query = emojiQuery, query.picker.candidates.indices.contains(index) else { return }
        let emoji = query.picker.candidates[index].character
        setEmojiQuery(nil)
        editorController.replaceCharacters(in: query.range, with: NSAttributedString(string: emoji), in: self)
        setSelectedRange(NSRange(location: query.range.location + (emoji as NSString).length, length: 0))
        // A replacement writes the storage directly; this reports it, so autosave sees it.
        didChangeText()
    }

    /// True when a list was open: Escape closes it before it may hide the window.
    @discardableResult
    func dismissEmojiPicker() -> Bool {
        guard let query = emojiQuery else { return false }
        dismissedEmojiRange = query.range
        setEmojiQuery(nil)
        return true
    }

    /// The host calls this after each text and selection change, once MDTextKit has styled the edit.
    /// An undo or redo closes the list: Return after ⌘Z must not insert the emoji again.
    func updateEmojiPicker() {
        guard isFocused, !hasMarkedText(), !editorUndoManager.isUndoing, !editorUndoManager.isRedoing,
            let match = Self.emojiQueryRange(in: mdTextStorage.string as NSString, caret: selectedRange()),
            !mdTextStorage.isRangeInsideCode(match.range)
        else {
            dismissedEmojiRange = nil
            return setEmojiQuery(nil)
        }
        if let dismissed = dismissedEmojiRange {
            guard dismissed != match.range else { return setEmojiQuery(nil) }
            dismissedEmojiRange = nil
        }
        // The same query keeps its list and selection; only the range can move.
        if let current = emojiQuery, current.picker.query == match.text {
            return setEmojiQuery(EmojiQuery(range: match.range, picker: current.picker))
        }
        guard var picker = NoteEmojiPicker(query: match.text) else { return setEmojiQuery(nil) }
        picker.keepSelection(of: emojiQuery?.picker)
        setEmojiQuery(EmojiQuery(range: match.range, picker: picker))
    }

    private func setEmojiQuery(_ next: EmojiQuery?) {
        guard next != emojiQuery else { return }
        emojiQuery = next
        let anchor = next.map { firstRect(forCharacterRange: NSRange(location: $0.range.location, length: 0), actualRange: nil) }
        onEmojiPickerChange?(next?.picker, anchor ?? .zero)
    }

    /// The `:query` that ends at an empty selection, after a line start, a space, an opening bracket
    /// or a block marker. A block marker (`- `, `# `, a checkbox) is one attachment character.
    static func emojiQueryRange(in text: NSString, caret: NSRange) -> (range: NSRange, text: String)? {
        guard caret.length == 0, caret.location <= text.length else { return nil }
        let line = text.lineRange(for: NSRange(location: caret.location, length: 0))
        // `:` plus at most 32 characters, plus the boundary before it: a long line costs no more.
        let start = max(line.location, caret.location - 34)
        let head = text.substring(with: NSRange(location: start, length: caret.location - start))
        let anchored = start == line.location
        guard let match = head.firstMatch(of: /(?:^|[\s(\[\x{FFFC}])(:([A-Za-z0-9_+\-]{2,32}))$/),
            anchored || match.range.lowerBound != head.startIndex || head.first != ":"
        else { return nil }
        let length = (String(match.1) as NSString).length
        return (NSRange(location: caret.location - length, length: length), String(match.2))
    }

    // MARK: - Focus and appearance

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        isFirstResponder = true
        focusChanged()
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        isFirstResponder = false
        focusChanged()
        return true
    }

    /// Every line under the selection shows its Markdown; an unfocused editor reveals nothing.
    private func focusChanged() {
        // The list closes with focus and opens only on an edit or a caret move, not when the window
        // comes back.
        if !isFocused { setEmojiQuery(nil) }
        let selection = selectedRange()
        if isFocused {
            editorController.autoHideMarkdown(in: self, forOldSelectionRange: selection, newSelectionRange: selection)
        } else {
            editorController.hideMarkdown(in: self, range: NSRange(location: 0, length: mdTextStorage.length))
        }
    }

    /// The panel keeps its first responder while another app is active, so key state is focus too.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        center.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            center.addObserver(self, selector: #selector(windowKeyStateChanged), name: name, object: window)
        }
    }

    @objc private func windowKeyStateChanged(_ notification: Notification) {
        focusChanged()
    }

    /// The colours are dynamic, but the attachments cache their drawing, so a restyle rebuilds them.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        editorController.restyleAll(in: self)
    }
}

extension NoteFormatting {
    init(_ formatting: MDFormatting) {
        var styles: Set<NoteEditAction.InlineStyle> = []
        if formatting.inline.contains(.strong) { styles.insert(.bold) }
        if formatting.inline.contains(.emphasis) { styles.insert(.italic) }
        if formatting.inline.contains(.strikethrough) { styles.insert(.strikethrough) }
        if formatting.inline.contains(.underline) { styles.insert(.underline) }
        if formatting.inline.contains(.highlighter) { styles.insert(.highlight) }
        if formatting.inline.contains(.code) { styles.insert(.code) }
        let list: NoteEditAction.ListStyle? =
            switch formatting.list {
            case .bullet: .bullet
            case .ordered: .ordered
            case .task: .task
            case nil: nil
            }
        self.init(
            headingLevel: formatting.headingLevel, inlineStyles: styles, isLink: formatting.isLink,
            isCodeBlock: formatting.isCodeBlock, isQuote: formatting.isBlockquote, list: list)
    }
}
