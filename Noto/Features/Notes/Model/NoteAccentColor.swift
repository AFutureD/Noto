import Foundation

/// The accent of underlines, links and the selection, as opaque sRGB components the user chose.
struct NoteAccentColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    /// `#RRGGBB`, the one form the setting is stored in.
    var hex: String {
        [red, green, blue].reduce(into: "#") {
            $0 += String(format: "%02X", Int((min(max($1, 0), 1) * 255).rounded()))
        }
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 7 else { return nil }
        var channels: [Double] = []
        var index = hex.index(after: hex.startIndex)
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let value = UInt8(hex[index..<next], radix: 16) else { return nil }
            channels.append(Double(value) / 255)
            index = next
        }
        self.init(red: channels[0], green: channels[1], blue: channels[2])
    }
}
