import Foundation

/// One emoji the `:` shortcut can insert, with the lowercased Unicode name it is found by.
struct Emoji: Sendable, Equatable {
    let character: String
    let name: String
}

/// The single-scalar emoji of the Unicode data that ships with the OS, found by name. There is no
/// bundled table: the names come from `Unicode.Scalar.Properties`, so a new OS brings new emoji.
/// Sequences (flags, skin tones, families) have no single name and are not in the catalog.
enum EmojiCatalog {
    /// A query shorter than this lists too much to be useful, and `:` plus one letter is common text.
    static let minimumQueryLength = 2

    static let all: [Emoji] = {
        var result: [Emoji] = []
        for value in UInt32(0x00A9)...UInt32(0x1FAFF) {
            guard let scalar = Unicode.Scalar(value), isCandidate(scalar), let name = scalar.properties.name
            else { continue }
            // A text-default emoji needs the variation selector to draw as an emoji.
            let character = scalar.properties.isEmojiPresentation
                ? String(scalar) : String(scalar) + "\u{FE0F}"
            result.append(Emoji(character: character, name: name.lowercased()))
        }
        return result
    }()

    /// The common shortcodes whose word is not in the Unicode name.
    static let aliases: [String: String] = [
        "+1": "👍", "thumbsup": "👍", "-1": "👎", "thumbsdown": "👎", "tada": "🎉", "sob": "😭",
        "lol": "😂", "heart": "❤️", "check": "✅", "100": "💯", "pray": "🙏", "smile": "😄",
    ]

    /// Best match first: an alias, a whole name, a whole word, then a word that starts with the query.
    static func search(_ query: String, limit: Int = 12) -> [Emoji] {
        let needle = query.lowercased().replacingOccurrences(of: "_", with: " ")
        guard needle.count >= minimumQueryLength else { return [] }
        var ranked: [(score: Int, emoji: Emoji)] = []
        // `:tad` finds `tada` as it is typed, not only once the whole shortcode is there.
        for (alias, character) in aliases where alias.hasPrefix(needle) {
            ranked.append((alias == needle ? 0 : 3, Emoji(character: character, name: alias)))
        }
        for emoji in all {
            guard let score = score(emoji.name, needle) else { continue }
            ranked.append((score, emoji))
        }
        var seen = Set<String>()
        return ranked
            .sorted { ($0.score, $0.emoji.name.count) < ($1.score, $1.emoji.name.count) }
            .map(\.emoji)
            .filter { seen.insert($0.character).inserted }
            .prefix(limit)
            .map { $0 }
    }

    private static func score(_ name: String, _ needle: String) -> Int? {
        if name == needle { return 1 }
        let words = name.split(separator: " ")
        if words.contains(where: { $0 == needle }) { return 2 }
        if name.hasPrefix(needle) { return 3 }
        if words.contains(where: { $0.hasPrefix(needle) }) { return 4 }
        // `smile` finds `smiling`: a final e drops before -ing.
        if needle.count >= 4, needle.hasSuffix("e") {
            let stem = needle.dropLast()
            if words.contains(where: { $0.hasPrefix(stem) }) { return 5 }
        }
        return nil
    }

    /// An emoji that stands alone: not a digit or `#` (which are emoji only in a keycap sequence),
    /// not a skin-tone modifier, not a regional indicator, which only pairs into a flag.
    private static func isCandidate(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        guard properties.isEmoji, !properties.isEmojiModifier else { return false }
        if (0x1F1E6...0x1F1FF).contains(scalar.value) { return false }
        return scalar.value > 0x7F
    }
}
