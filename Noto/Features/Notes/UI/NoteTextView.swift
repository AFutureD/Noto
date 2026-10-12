import AppKit
import MDTextKit
import MDTextKitUI

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
