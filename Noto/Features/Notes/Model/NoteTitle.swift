import Foundation
import PolarMark

/// A note's title is its filename; one the user has not named yet borrows its first line to show.
enum NoteTitle {
    static let untitled = "Untitled"

    /// Wide enough that the scanned prefix is covered even where every character is four bytes.
    static let headByteCount = 4096

    private static let scanLimit = 1024
    private static let displayLimit = 120

    /// Syntax never titles a note: markers, indentation, rules, fences and link targets are dropped.
    private static let syntax: [NSAttributedString.Key] =
        PMKAttributes.markerAttributes + [
            .pmkIndentSpace, .pmkThematicBreak, .pmkFencedCodeLanguage, .pmkLinkURL, .pmkLinkTitle,
            .pmkImageURL, .pmkImageTitle
        ]

    /// True only for the names `create` claims — `Untitled`, `Untitled 2`, … — never a typed one.
    static func isUnnamed(_ title: String) -> Bool {
        guard title.hasPrefix(untitled) else { return false }
        let suffix = title.dropFirst(untitled.count)
        guard !suffix.isEmpty else { return true }
        let digits = suffix.dropFirst()
        return suffix.hasPrefix(" ") && !digits.isEmpty
            && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// The first line carrying visible text, without its Markdown markers and capped to one row.
    static func firstLine(of source: String) -> String? {
        let head = String(source.prefix(scanLimit))
        let annotated = PMKAST(markdown: head).annotatedString()
        let text = annotated.string as NSString
        var location = 0
        while location < text.length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            let title = visibleText(of: line, in: annotated)
            if !title.isEmpty { return String(title.prefix(displayLimit)) }
            location = NSMaxRange(line)
        }
        return nil
    }

    private static func visibleText(of line: NSRange, in annotated: NSAttributedString) -> String {
        let text = annotated.string as NSString
        var visible = ""
        annotated.enumerateAttributes(in: line, options: []) { attributes, range, _ in
            guard syntax.allSatisfy({ attributes[$0] == nil }) else { return }
            visible += text.substring(with: range)
        }
        return visible.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
