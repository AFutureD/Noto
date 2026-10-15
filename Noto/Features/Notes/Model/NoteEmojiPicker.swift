import Foundation

/// The open `:` emoji list: the emoji it offers for the query and the row Return takes.
struct NoteEmojiPicker: Sendable, Equatable {
    /// Enough to scan at a glance; a longer query narrows the list instead of a scroll.
    static let rowLimit = 8

    let query: String
    let candidates: [Emoji]
    private(set) var selection = 0

    init?(query: String) {
        let candidates = EmojiCatalog.search(query, limit: Self.rowLimit)
        guard !candidates.isEmpty else { return nil }
        self.query = query
        self.candidates = candidates
    }

    /// The selection wraps, like a menu's.
    mutating func moveSelection(by offset: Int) {
        selection = (selection + offset % candidates.count + candidates.count) % candidates.count
    }

    /// The same list keeps its row while the query only refines to the same emoji.
    mutating func keepSelection(of previous: NoteEmojiPicker?) {
        guard let previous, previous.candidates == candidates else { return }
        selection = previous.selection
    }
}
