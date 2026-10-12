/// One formatting gesture of the bar, the heading menu or a chord. `NoteTextView.format` applies it.
enum NoteEditAction: Sendable, Equatable {
    enum InlineStyle: Sendable, CaseIterable {
        case bold, italic, strikethrough, highlight, code
    }

    enum ListStyle: Sendable {
        case bullet, ordered, task
    }

    case toggleInline(InlineStyle)
    case toggleLink
    /// Level 0 makes the paragraph plain.
    case setHeading(level: Int)
    case toggleList(ListStyle)
    case toggleCodeBlock
    case toggleQuote
}
