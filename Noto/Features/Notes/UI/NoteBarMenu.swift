import Foundation

/// The formatting bar's three drop-down menus and the rows each one lists.
enum NoteBarMenu: Hashable, CaseIterable, Sendable {
    case heading, list, more

    struct Row: Sendable {
        let title: String
        let shortcut: String
        let action: NoteEditAction
        let isCurrent: @Sendable (NoteFormatting) -> Bool
    }

    var title: String {
        switch self {
        case .heading: "Heading"
        case .list: "List"
        case .more: "More"
        }
    }

    var symbol: String {
        switch self {
        case .heading: "textformat.size"
        case .list: "list.bullet"
        case .more: "ellipsis"
        }
    }

    /// The button lights while any of its rows applies.
    func isLit(_ formatting: NoteFormatting) -> Bool {
        switch self {
        case .heading: (1...6).contains(formatting.headingLevel ?? 0)
        case .list, .more: rows.contains { $0.isCurrent(formatting) }
        }
    }

    var rows: [Row] {
        switch self {
        case .heading:
            [
                Row(title: "Heading 1", shortcut: "⌥⌘1", action: .setHeading(level: 1)) { $0.headingLevel == 1 },
                Row(title: "Heading 2", shortcut: "⌥⌘2", action: .setHeading(level: 2)) { $0.headingLevel == 2 },
                Row(title: "Heading 3", shortcut: "⌥⌘3", action: .setHeading(level: 3)) { $0.headingLevel == 3 },
                Row(title: "Text", shortcut: "⌥⌘0", action: .setHeading(level: 0)) { $0.headingLevel == 0 }
            ]
        case .list:
            [
                Row(title: "Bullet List", shortcut: "⇧⌘8", action: .toggleList(.bullet)) { $0.list == .bullet },
                Row(title: "Numbered List", shortcut: "⇧⌘7", action: .toggleList(.ordered)) { $0.list == .ordered },
                Row(title: "Task List", shortcut: "⇧⌘9", action: .toggleList(.task)) { $0.list == .task }
            ]
        case .more:
            [
                Row(title: "Underline", shortcut: "⌘U", action: .toggleInline(.underline)) {
                    $0.inlineStyles.contains(.underline)
                },
                Row(title: "Strikethrough", shortcut: "⇧⌘X", action: .toggleInline(.strikethrough)) {
                    $0.inlineStyles.contains(.strikethrough)
                },
                Row(title: "Inline Code", shortcut: "⌘E", action: .toggleInline(.code)) {
                    $0.inlineStyles.contains(.code)
                },
                Row(title: "Code Block", shortcut: "⌥⌘C", action: .toggleCodeBlock) { $0.isCodeBlock }
            ]
        }
    }
}
