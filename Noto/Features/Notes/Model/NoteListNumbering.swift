import Foundation

/// How an ordered list writes its numbers: `1.`, `a.`, `A.`, `i.` or `I.`.
enum NoteListNumbering: Sendable, Equatable {
    case decimal, lowerLetter, upperLetter, lowerRoman, upperRoman

    private static let romanDigits: [(value: Int, glyphs: String)] = [
        (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"), (50, "l"), (40, "xl"),
        (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")
    ]

    /// The label for `number`, or its decimal digits when the style has no label for it.
    func label(_ number: Int) -> String {
        switch self {
        case .decimal:
            return String(number)
        case .lowerLetter, .upperLetter:
            guard (1...26).contains(number) else { return String(number) }
            let scalar = Unicode.Scalar(UInt8((self == .lowerLetter ? 97 : 65) + number - 1))
            return String(Character(scalar))
        case .lowerRoman, .upperRoman:
            guard let roman = Self.roman(number) else { return String(number) }
            return self == .lowerRoman ? roman : roman.uppercased()
        }
    }

    /// The number a label stands for; a lone `i`, `v`, `x`, `l`, `c`, `d` or `m` reads as a letter.
    static func parse(_ label: String) -> (number: Int, numbering: NoteListNumbering)? {
        guard !label.isEmpty, label.utf8.count <= 9 else { return nil }
        if label.utf8.allSatisfy({ (48...57).contains($0) }) {
            return (label.utf8.reduce(0) { $0 * 10 + Int($1 - 48) }, .decimal)
        }
        let isLower = label.utf8.allSatisfy { (97...122).contains($0) }
        let isUpper = label.utf8.allSatisfy { (65...90).contains($0) }
        guard isLower || isUpper else { return nil }
        if label.utf8.count == 1 {
            return (Int(label.utf8.first! - (isLower ? 96 : 64)), isLower ? .lowerLetter : .upperLetter)
        }
        guard let number = romanValue(label) else { return nil }
        return (number, isLower ? .lowerRoman : .upperRoman)
    }

    /// A lone `i`, `v`, `x`, `l`, `c`, `d` or `m` follows the run it is in; starting one, only `i` is roman.
    static func disambiguated(
        _ label: (number: Int, numbering: NoteListNumbering), after run: NoteListNumbering?
    ) -> (number: Int, numbering: NoteListNumbering) {
        guard label.numbering == .lowerLetter || label.numbering == .upperLetter,
            let roman = romanValue(NoteListNumbering.lowerLetter.label(label.number))
        else { return label }
        let asRoman = (roman, label.numbering == .lowerLetter ? lowerRoman : upperRoman)
        switch run {
        case .lowerRoman, .upperRoman: return asRoman
        case .some: return label
        case nil: return roman == 1 ? asRoman : label
        }
    }

    /// The number a well-formed roman numeral stands for, in either case, or nil.
    static func romanValue(_ label: String) -> Int? {
        let lowered = label.lowercased()
        var rest = Substring(lowered)
        var number = 0
        for (value, glyphs) in romanDigits {
            while rest.hasPrefix(glyphs) {
                number += value
                rest = rest.dropFirst(glyphs.count)
            }
        }
        guard rest.isEmpty, roman(number) == lowered else { return nil }
        return number
    }

    private static func roman(_ number: Int) -> String? {
        guard (1...3999).contains(number) else { return nil }
        var rest = number
        var result = ""
        for (value, glyphs) in romanDigits {
            while rest >= value {
                result += glyphs
                rest -= value
            }
        }
        return result
    }
}
