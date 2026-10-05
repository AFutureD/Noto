import CoreGraphics

/// Where a callout sits and where its pointer lands; pure, with metrics injected.
struct CalloutPlacement: Equatable {
    enum CaretEdge: Equatable {
        case top
        case bottom
    }

    /// Callout centre in container coordinates, ready for `.position`.
    let center: CGPoint
    let caretEdge: CaretEdge
    /// Tip in the callout's own x, already clear of the corner arcs.
    let caretX: CGFloat

    /// Above the field when it fits, else below; clamped inside the container either way.
    static func resolve(
        field: CGRect, container: CGSize, size: CGSize, gap: CGFloat, inset: CGFloat,
        cornerRadius: CGFloat, caretWidth: CGFloat
    ) -> CalloutPlacement {
        let above = field.minY >= size.height + gap
        let half = size.width / 2

        // `max` guards a container narrower than the callout, where the two bounds cross.
        let lower = half + inset
        let centerX = min(max(field.midX, lower), max(container.width - half - inset, lower))
        let centerY =
            above
            ? field.minY - gap - size.height / 2
            : field.maxY + gap + size.height / 2

        // Once clamped, the tip walks so it still aims at the field.
        let limit = cornerRadius + caretWidth / 2
        let tip = field.midX - (centerX - half)

        return CalloutPlacement(
            center: CGPoint(x: centerX, y: centerY),
            caretEdge: above ? .bottom : .top,
            caretX: min(max(tip, limit), max(size.width - limit, limit))
        )
    }
}
