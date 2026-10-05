import SwiftUI

/// A bar control's hover chrome; footer pills and header pop-ups share `barControl` as one family.
enum BarButtonChrome {
    case capsule
    case rounded

    func shape(_ metrics: InterfaceMetrics) -> AnyShape {
        switch self {
        case .capsule:
            return AnyShape(Capsule())
        case .rounded:
            return AnyShape(
                RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous))
        }
    }
}

/// A bar control, bare until hover; hover lives here so its owner never re-renders.
struct BarButton<Label: View>: View {
    var chrome: BarButtonChrome = .capsule
    var isSelected = false
    /// `sm` padding, so a 16-point glyph frame makes a square as tall as the bar.
    var isCompact = false
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        let shape = chrome.shape(metrics)
        return Button(action: action) {
            label
                .padding(.horizontal, isCompact ? metrics.spacing.sm : metrics.spacing.md)
                .frame(height: metrics.size.barButtonHeight)
                .contentShape(shape)
                .background(shape.fill(fill))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    /// Selection beats hover, the rule every row follows.
    private var fill: Color {
        if isSelected { return Theme.Colors.selection }
        return hovered ? Theme.Colors.rowHover : Color.clear
    }
}
