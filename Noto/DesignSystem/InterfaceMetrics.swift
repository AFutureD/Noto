import SwiftUI

/// `Theme`'s geometry at a scale; `.standard` is `Theme` verbatim, and the only one Noto sets.
struct InterfaceMetrics: Equatable, Sendable {
    static let standard = InterfaceMetrics(scale: 1)

    let scale: CGFloat

    var spacing: Spacing { Spacing(scale: scale) }
    var radius: Radius { Radius(scale: scale) }
    var size: Size { Size(scale: scale) }
    var typography: Typography { Typography(scale: scale) }

    /// For a tuned length a surface owns itself, where `Theme` states no token for it.
    func scaled(_ value: CGFloat) -> CGFloat { scaledPoints(value, scale) }

    struct Spacing: Equatable, Sendable {
        let scale: CGFloat

        var xxs: CGFloat { scaledPoints(Theme.Spacing.xxs, scale) }
        var xs: CGFloat { scaledPoints(Theme.Spacing.xs, scale) }
        var sm: CGFloat { scaledPoints(Theme.Spacing.sm, scale) }
        var md: CGFloat { scaledPoints(Theme.Spacing.md, scale) }
    }

    struct Radius: Equatable, Sendable {
        let scale: CGFloat

        var barControl: CGFloat { scaledPoints(Theme.Radius.barControl, scale) }
        var keyCap: CGFloat { scaledPoints(Theme.Radius.keyCap, scale) }
        var tooltip: CGFloat { scaledPoints(Theme.Radius.tooltip, scale) }
    }

    struct Size: Equatable, Sendable {
        let scale: CGFloat

        var barButtonHeight: CGFloat { scaledPoints(Theme.Size.barButtonHeight, scale) }
        var keyCap: CGFloat { scaledPoints(Theme.Size.keyCap, scale) }
        var compactKeyCap: CGFloat { scaledPoints(Theme.Size.compactKeyCap, scale) }
        var heroKeyCap: CGFloat { scaledPoints(Theme.Size.heroKeyCap, scale) }
    }

    /// `NSFont` is the only public source of a text style's size and face.
    struct Typography: Sendable {
        let scale: CGFloat

        var keyCap: Font { font(Theme.Typography.keyCap, .caption1) }
        var compactKeyCap: Font { font(Theme.Typography.compactKeyCap, .caption2) }
        var heroKeyCap: Font { font(Theme.Typography.heroKeyCap, .body) }

        /// Composed like `Theme`'s own: the style carries the face, an explicit weight overrides it.
        private func font(_ base: Font, _ style: NSFont.TextStyle) -> Font {
            guard scale != 1 else { return base }
            let descriptor = NSFont.preferredFont(forTextStyle: style)
            return Font(
                NSFont(descriptor: descriptor.fontDescriptor, size: scaledPoints(descriptor.pointSize, scale))
                    ?? descriptor)
        }
    }
}

/// Whole points: a fractional row pitch lands keycap edges and the dissolve mask off-pixel.
private func scaledPoints(_ value: CGFloat, _ scale: CGFloat) -> CGFloat {
    scale == 1 ? value : (value * scale).rounded()
}

extension EnvironmentValues {
    /// `.standard` by default, so a shared `DesignSystem` view never scales unless told to.
    @Entry var metrics = InterfaceMetrics.standard
}
