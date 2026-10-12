import AppKit
import SwiftUI

/// Turns a parsed line into attributes; bullets keep their dot even when the caret reveals syntax.
@MainActor
enum NoteMarkdownStyler {
    typealias Attributes = [NSAttributedString.Key: Any]
    private typealias Unit = NoteMarkdownParser.Unit

    struct LineStyle {
        /// Set over the whole line, replacing whatever it carried.
        let base: Attributes
        /// Added on top of `base`, in order, so inner spans override outer ones.
        let runs: [(range: NSRange, attributes: Attributes)]
    }

    /// The literal editor's attributes, and the base every rendered line starts from.
    private(set) static var literal = makeLiteral()

    private static let hidden: Attributes = [
        .font: NoteMarkdownTypography.hidden,
        .foregroundColor: NSColor.clear
    ]
    private static var hiddenEmptyListMarker = makeHiddenEmptyListMarker()
    private static var listSlot = makeListSlot()
    private static let quoteStep = Theme.Size.markdownQuoteBar + Theme.Spacing.lg
    private static let codeInset = Theme.Spacing.lg
    /// Space after each list item, kept when revealed so moving the caret never shifts the rows.
    private static let listItemSpacing = Theme.Spacing.md
    /// Space before nested content, so an item and what it holds read as one group.
    private static let nestedItemSpacing = Theme.Spacing.xs
    /// A hidden tab still runs to the next tab stop, so each one gets a stop this far past where it starts.
    private static let hiddenTabStep: CGFloat = 0.1
    private static let defaultTabInterval: CGFloat = 28
    /// Only these get a `.link` attribute, and only these are opened when one is clicked.
    static let openableSchemes: Set<String> = ["http", "https", "mailto"]

    /// The chosen highlight background; nil draws the theme's own, resolved per appearance.
    private(set) static var highlight: NoteHighlightColor?

    /// The one way to change the editor's fonts: the attributes built from them are rebuilt here.
    static func apply(_ fonts: NoteFontSettings) -> Bool {
        guard NoteMarkdownTypography.apply(fonts) else { return false }
        literal = makeLiteral()
        hiddenEmptyListMarker = makeHiddenEmptyListMarker()
        listSlot = makeListSlot()
        return true
    }

    /// Returns false when `next` is what the highlight already draws with.
    static func apply(highlight next: NoteHighlightColor?) -> Bool {
        guard next != highlight else { return false }
        highlight = next
        return true
    }

    private static func makeLiteral() -> Attributes {
        [.font: NoteMarkdownTypography.body, .foregroundColor: NSColor(Theme.Colors.noteText)]
    }

    private static func makeHiddenEmptyListMarker() -> Attributes {
        [.font: NoteMarkdownTypography.body, .foregroundColor: NSColor.clear]
    }

    private static func makeListSlot() -> CGFloat {
        NoteListGeometry.slot(bodyFont: NoteMarkdownTypography.body)
    }

    /// Colours the fragment draws with are resolved now, under the caller's drawing appearance.
    static func style(
        at index: Int, in markdown: NoteMarkdown, text: NSString, isRevealed: Bool
    ) -> LineStyle {
        let line = markdown.lines[index]
        var base = literal
        var runs: [(range: NSRange, attributes: Attributes)] = []
        let markerLook = isRevealed ? revealedMarker : hidden

        switch line.kind {
        case .paragraph where line.isListContinuation:
            let indentation = Self.indentation(of: line.contentRange, in: text)
            runs.append((indentation, hidden))
            base[.paragraphStyle] = listParagraph(
                contentIndent: CGFloat(line.level) * listSlot, hiding: indentation, in: text,
                spacingAfter: listSpacing(after: index, in: markdown))
        case .blank, .paragraph:
            break
        case .heading(let level):
            base.merge(NoteMarkdownTypography.headingLook(level)) { $1 }
            base[.paragraphStyle] = paragraph {
                $0.paragraphSpacingBefore =
                    index == 0 ? 0 : level <= 2 ? Theme.Spacing.xl : Theme.Spacing.md
                $0.paragraphSpacing = Theme.Spacing.xs
            }
            if let marker = line.markerRange { runs.append((marker, markerLook)) }
        case .bullet, .ordered, .task:
            guard let marker = line.markerRange else { break }
            let indentation = Self.indentation(of: marker, in: text)
            let label = NSRange(NSMaxRange(indentation)..<NSMaxRange(marker))
            let labelWidth = bodyWidth(of: label, in: text)
            let contentIndent = CGFloat(line.level + 1) * listSlot
            let reveals = isRevealed && line.kind.isOrdered && labelWidth <= contentIndent
            let isEmpty = line.contentRange.length == 0
            runs.append((indentation, hidden))
            let labelLook: Attributes =
                reveals
                ? [.foregroundColor: color(Theme.Colors.textSecondary)]
                : isEmpty ? hiddenEmptyListMarker : hidden
            runs.append((label, labelLook))
            if case .task(checked: true) = line.kind {
                runs.append((line.contentRange, checkedTask))
            }
            let hangs = reveals || isEmpty
            base[.paragraphStyle] = listParagraph(
                contentIndent: contentIndent, hangingWidth: hangs ? labelWidth : 0,
                hiding: hangs ? indentation : marker, in: text,
                spacingAfter: listSpacing(after: index, in: markdown))
            if !reveals { base[.noteBlockDecoration] = listDecoration(line, label: label, text: text) }
        case .quote(let depth):
            if let marker = line.markerRange { runs.append((marker, markerLook)) }
            runs.append((line.contentRange, [.foregroundColor: color(Theme.Colors.textSecondary)]))
            guard !isRevealed else {
                base[.paragraphStyle] = hanging(
                    line.markerRange, in: text, contentIndent: CGFloat(depth) * quoteStep)
                break
            }
            base[.paragraphStyle] = indented(by: CGFloat(depth) * quoteStep)
            base[.noteBlockDecoration] = decoration(
                .quote(depth: depth), fill: Theme.Colors.border, ink: Theme.Colors.border)
        case .rule:
            guard !isRevealed else {
                base[.foregroundColor] = color(Theme.Colors.textTertiary)
                break
            }
            base[.foregroundColor] = NSColor.clear
            base[.noteBlockDecoration] = decoration(
                .rule, fill: Theme.Colors.separator, ink: Theme.Colors.separator)
        case .table:
            base[.font] = NoteMarkdownTypography.codeBlock
            base[.paragraphStyle] = tableRow
        case .fenceOpen, .fenceClose, .code:
            base[.font] = NoteMarkdownTypography.codeBlock
            base[.paragraphStyle] = codeParagraph
            if line.kind != .code {
                base[.foregroundColor] = isRevealed ? color(Theme.Colors.textTertiary) : NSColor.clear
            }
            base[.noteBlockDecoration] = decoration(
                .code(codeRow(index, markdown), language: language(line.kind)),
                fill: Theme.Colors.cardFill, ink: Theme.Colors.textTertiary)
        }

        let lineFont = base[.font] as? NSFont ?? NoteMarkdownTypography.body
        runs += inlineRuns(markdown.inlines(of: line), lineFont: lineFont, text: text, isRevealed: isRevealed)
        return LineStyle(base: base, runs: runs)
    }

    // MARK: - Inlines

    private static func inlineRuns(
        _ inlines: [NoteMarkdown.Inline], lineFont: NSFont, text: NSString, isRevealed: Bool
    ) -> [(range: NSRange, attributes: Attributes)] {
        var runs: [(range: NSRange, attributes: Attributes)] = []
        for (position, inline) in inlines.enumerated() {
            let look = spanLook(inlines[...position], lineFont: lineFont)
            let font = look[.font] as? NSFont ?? lineFont
            var markerLook = isRevealed ? revealedMarker.merging(look) { $1 } : hidden
            switch inline.kind {
            case .strong, .emphasis, .strongEmphasis:
                runs.append((inline.contentRange, look))
            case .strikethrough:
                runs.append((inline.contentRange, [.strikethroughStyle: NSUnderlineStyle.single.rawValue]))
            case .highlight:
                runs.append((inline.contentRange, [.backgroundColor: highlightColor]))
            case .code:
                let codeFont = NoteMarkdownTypography.inlineCode(matching: font)
                if isRevealed { markerLook[.font] = codeFont }
                let background = color(Theme.Colors.controlSurface)
                runs.append((inline.contentRange, [.font: codeFont, .backgroundColor: background]))
            case .link(let destination):
                runs.append((inline.contentRange, linkLook(URL(string: destination), isRevealed: isRevealed)))
            case .autolink:
                let url = URL(string: text.substring(with: inline.range))
                runs.append((inline.range, linkLook(url, isRevealed: isRevealed)))
            }
            runs += inline.markerRanges.map { ($0, markerLook) }
        }
        return runs
    }

    /// The span's font: the line font plus the traits of every emphasis span enclosing it.
    private static func spanLook(_ spans: ArraySlice<NoteMarkdown.Inline>, lineFont: NSFont) -> Attributes {
        guard let span = spans.last else { return [.font: lineFont] }
        var traits: NSFontDescriptor.SymbolicTraits = []
        for outer in spans where NSIntersectionRange(outer.range, span.range) == span.range {
            switch outer.kind {
            case .strong: traits.insert(.bold)
            case .emphasis: traits.insert(.italic)
            case .strongEmphasis: traits.formUnion([.bold, .italic])
            default: break
            }
        }
        return traits.isEmpty
            ? [.font: lineFont] : NoteMarkdownTypography.emphasized(lineFont, with: traits)
    }

    private static var highlightColor: NSColor {
        guard let highlight else { return color(Theme.Colors.highlight) }
        return NSColor(
            srgbRed: highlight.red, green: highlight.green, blue: highlight.blue, alpha: highlight.alpha)
    }

    /// A revealed link is plain coloured text, so a click places the caret to edit its URL.
    private static func linkLook(_ url: URL?, isRevealed: Bool) -> Attributes {
        guard !isRevealed else { return [.foregroundColor: NSColor.linkColor] }
        guard let url, let scheme = url.scheme?.lowercased(), openableSchemes.contains(scheme) else {
            return [:]
        }
        return [.link: url]
    }

    // MARK: - Blocks

    private static var revealedMarker: Attributes {
        [.foregroundColor: color(Theme.Colors.textTertiary)]
    }

    private static var checkedTask: Attributes {
        [
            .foregroundColor: color(Theme.Colors.textSecondary),
            .strikethroughStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    /// A wrapped table row hangs under its first line, so each row still reads as one.
    private static let tableRow: NSParagraphStyle = paragraph { $0.headIndent = Theme.Spacing.lg }

    private static let codeParagraph: NSParagraphStyle = paragraph {
        $0.firstLineHeadIndent = codeInset
        $0.headIndent = codeInset
        $0.tailIndent = -codeInset
    }

    /// Tighter before nested content; the gap after a group's last line stays the list's own.
    private static func listSpacing(after index: Int, in markdown: NoteMarkdown) -> CGFloat {
        let next = markdown.lines[(index + 1)...].first { $0.kind != .blank }
        return next.map { $0.level > 0 } == true ? nestedItemSpacing : listItemSpacing
    }

    private static func indented(by indent: CGFloat, spacingAfter: CGFloat = 0) -> NSParagraphStyle {
        paragraph {
            $0.firstLineHeadIndent = indent
            $0.headIndent = indent
            $0.paragraphSpacing = spacingAfter
        }
    }

    /// A revealed marker hangs left of the content, so text stays where the rendered line had it.
    private static func hanging(
        _ marker: NSRange?, in text: NSString, contentIndent: CGFloat, spacingAfter: CGFloat = 0
    ) -> NSParagraphStyle {
        let width = marker.map { bodyWidth(of: $0, in: text) } ?? 0
        return paragraph {
            $0.firstLineHeadIndent = max(0, contentIndent - width)
            $0.headIndent = contentIndent
            $0.paragraphSpacing = spacingAfter
        }
    }

    /// Content sits at `contentIndent`, a visible label hangs left of it, and hidden tabs get stops.
    private static func listParagraph(
        contentIndent: CGFloat, hangingWidth: CGFloat = 0, hiding hidden: NSRange, in text: NSString,
        spacingAfter: CGFloat
    ) -> NSParagraphStyle {
        let firstLineIndent = max(0, contentIndent - hangingWidth)
        let tabs = (hidden.location..<NSMaxRange(hidden)).count { text.character(at: $0) == Unit.tab }
        return paragraph {
            $0.firstLineHeadIndent = firstLineIndent
            $0.headIndent = contentIndent
            $0.paragraphSpacing = spacingAfter
            guard tabs > 0 else { return }
            $0.tabStops = (1...tabs).map { tab in
                let location = firstLineIndent + CGFloat(tab) * hiddenTabStep
                return NSTextTab(textAlignment: .left, location: location, options: [:])
            }
            $0.defaultTabInterval = defaultTabInterval
        }
    }

    private static func bodyWidth(of range: NSRange, in text: NSString) -> CGFloat {
        text.substring(with: range).size(withAttributes: [.font: NoteMarkdownTypography.body]).width
    }

    /// The leading spaces and tabs of `range`, which a list-shaped line always hides.
    private static func indentation(of range: NSRange, in text: NSString) -> NSRange {
        var end = range.location
        while end < NSMaxRange(range), Unit.isSpaceOrTab(text.character(at: end)) { end += 1 }
        return NSRange(range.location..<end)
    }

    private static func paragraph(_ configure: (NSMutableParagraphStyle) -> Void) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        configure(style)
        return style
    }

    private static func listDecoration(
        _ line: NoteMarkdown.Line, label: NSRange, text: NSString
    ) -> NoteBlockDecoration {
        let shape: NoteBlockDecoration.Shape
        switch line.kind {
        case .task(let checked):
            return decoration(
                .task(level: line.level, checked: checked),
                fill: Theme.Colors.controlSurface, ink: Theme.Colors.noteText)
        case .ordered:
            let label = text.substring(with: label).trimmingCharacters(in: .whitespaces)
            shape = .ordered(level: line.level, label: label)
        default:
            shape = .bullet(level: line.level, dash: text.character(at: label.location) == Unit.dash)
        }
        return decoration(shape, fill: Theme.Colors.textSecondary, ink: Theme.Colors.textSecondary)
    }

    private static func codeRow(_ index: Int, _ markdown: NoteMarkdown) -> NoteBlockDecoration.Shape.CodeRow {
        let blocks = markdown.fenceBlocks
        var low = 0
        var high = blocks.count
        while low < high {
            let middle = (low + high) / 2
            if blocks[middle].upperBound < index { low = middle + 1 } else { high = middle }
        }
        guard low < blocks.count, blocks[low].contains(index) else { return .middle }
        let block = blocks[low]
        switch index {
        case block.lowerBound where block.lowerBound == block.upperBound: return .single
        case block.lowerBound: return .top
        case block.upperBound: return .bottom
        default: return .middle
        }
    }

    private static func language(_ kind: NoteMarkdown.Line.Kind) -> String? {
        guard case .fenceOpen(let language) = kind else { return nil }
        return language
    }

    private static func decoration(
        _ shape: NoteBlockDecoration.Shape, fill: Color, ink: Color
    ) -> NoteBlockDecoration {
        NoteBlockDecoration(
            shape: shape, fill: color(fill), ink: color(ink),
            bodyPointSize: NoteMarkdownTypography.body.pointSize,
            labelFontName: NoteMarkdownTypography.labelFontName)
    }

    /// Pins a dynamic token to the current drawing appearance; the fragment cannot resolve one.
    private static func color(_ token: Color) -> NSColor {
        if let resolved = resolved[token] { return resolved }
        let pinned = NSColor(cgColor: NSColor(token).cgColor) ?? NSColor(token)
        resolved[token] = pinned
        return pinned
    }

    /// Pinned colours belong to one appearance, so a change to it has to drop them.
    static func invalidateColors() {
        resolved.removeAll(keepingCapacity: true)
    }

    private static var resolved: [Color: NSColor] = [:]
}
