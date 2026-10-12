import AppKit

extension NSAppearance {
    /// `bestMatch`, not a name comparison, so vibrant and accessibility variants resolve.
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension NSColor {
    /// Built in sRGB, where `Color.white` resolves, so a dark branch is the same pixel.
    static func srgbInk(_ white: CGFloat, alpha: Double) -> NSColor {
        NSColor(srgbRed: white, green: white, blue: white, alpha: alpha)
    }

    /// An opaque sRGB colour from `0xRRGGBB`.
    static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
