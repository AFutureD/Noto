import Foundation

/// The background of a `==highlight==` span, as sRGB components the user chose.
struct NoteHighlightColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    /// `#RRGGBBAA`, the one form the setting is stored in.
    var hex: String {
        [red, green, blue, alpha].reduce(into: "#") {
            $0 += String(format: "%02X", Int((min(max($1, 0), 1) * 255).rounded()))
        }
    }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 9 else { return nil }
        var channels: [Double] = []
        var index = hex.index(after: hex.startIndex)
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let value = UInt8(hex[index..<next], radix: 16) else { return nil }
            channels.append(Double(value) / 255)
            index = next
        }
        self.init(red: channels[0], green: channels[1], blue: channels[2], alpha: channels[3])
    }
}
