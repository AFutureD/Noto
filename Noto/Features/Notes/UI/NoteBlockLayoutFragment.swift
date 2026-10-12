import AppKit

/// Draws one line's block chrome (code bands, quote bars, rules, list markers) around its text.
final class NoteBlockLayoutFragment: NSTextLayoutFragment {
    let decoration: NoteBlockDecoration

    private static let bulletScale: CGFloat = 0.35
    private static let dashScale: CGFloat = 0.5
    private static let dashThicknessScale: CGFloat = 0.1
    private static let boxRadiusScale: CGFloat = 0.25
    private static let checkStrokeScale: CGFloat = 0.12

    init(textElement: NSTextElement, range: NSTextRange?, decoration: NoteBlockDecoration) {
        self.decoration = decoration
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Drawing is clipped to this; it starts a slot left of the container so wide numbers show.
    override var renderingSurfaceBounds: CGRect {
        let bounds = super.renderingSurfaceBounds
        let frame = layoutFragmentFrame
        let chrome = CGRect(
            x: -frame.minX - slot, y: 0, width: containerWidth + slot, height: frame.height)
        return bounds.union(chrome)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let left = point.x - layoutFragmentFrame.minX
        if case .code(let row, let language) = decoration.shape {
            drawBand(row: row, language: language, left: left, top: point.y, in: context)
        }
        super.draw(at: point, in: context)
        context.saveGState()
        defer { context.restoreGState() }
        switch decoration.shape {
        case .code:
            break
        case .quote(let depth):
            drawQuoteBars(depth: depth, left: left, top: point.y, in: context)
        case .rule:
            let y = (point.y + layoutFragmentFrame.height / 2).rounded(.down)
            context.setFillColor(decoration.fill.cgColor)
            let width = containerWidth.rounded()
            context.fill(CGRect(x: left.rounded(), y: y, width: width, height: Theme.Size.hairline))
        case .bullet(let level, let dash):
            drawBullet(level: level, dash: dash, left: left, top: point.y, in: context)
        case .ordered(let level, let label):
            drawLabel(label, level: level, left: left, top: point.y, in: context)
        case .task(let level, let checked):
            drawBox(level: level, checked: checked, left: left, top: point.y, in: context)
        }
    }

    // MARK: - Shapes

    private var slot: CGFloat { NoteListGeometry.slot(bodyFont: decoration.bodyFont) }

    private var containerWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? super.renderingSurfaceBounds.width
    }

    /// The first line of text, which markers align with when an item wraps.
    var firstLine: CGRect {
        firstTextLine?.typographicBounds ?? CGRect(origin: .zero, size: layoutFragmentFrame.size)
    }

    var firstBaseline: CGFloat {
        guard let line = firstTextLine else { return layoutFragmentFrame.height }
        return line.typographicBounds.minY + line.glyphOrigin.y
    }

    /// A word too wide for the first line wraps, leaving the hidden marker alone on a hairline.
    private var firstTextLine: NSTextLineFragment? {
        textLineFragments.first { $0.typographicBounds.height > decoration.bodyPointSize / 2 }
    }

    private func drawBand(
        row: NoteBlockDecoration.Shape.CodeRow, language: String?, left: CGFloat, top: CGFloat,
        in context: CGContext
    ) {
        let minY = top.rounded()
        let rect = CGRect(
            x: left.rounded(), y: minY, width: containerWidth.rounded(),
            height: (top + layoutFragmentFrame.height).rounded() - minY)
        let roundsTop = row == .top || row == .single
        let roundsBottom = row == .bottom || row == .single
        context.saveGState()
        context.addPath(
            Self.bandPath(
                rect, topRadius: roundsTop ? Theme.Radius.menu : 0,
                bottomRadius: roundsBottom ? Theme.Radius.menu : 0))
        context.setFillColor(decoration.fill.cgColor)
        context.fillPath()
        if roundsTop, let language {
            let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize)
            let line = Self.line(language, font: font, color: decoration.ink)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            let baseline = top + (layoutFragmentFrame.height + font.capHeight) / 2
            Self.draw(line, at: CGPoint(x: rect.maxX - Theme.Spacing.lg - width, y: baseline), in: context)
        }
        context.restoreGState()
    }

    private func drawQuoteBars(depth: Int, left: CGFloat, top: CGFloat, in context: CGContext) {
        context.setFillColor(decoration.fill.cgColor)
        let step = Theme.Size.markdownQuoteBar + Theme.Spacing.lg
        let minY = top.rounded()
        let height = (top + layoutFragmentFrame.height).rounded() - minY
        for level in 0..<depth {
            let bar = CGRect(
                x: (left + CGFloat(level) * step).rounded(), y: minY, width: Theme.Size.markdownQuoteBar,
                height: height)
            context.addPath(CGPath(roundedRect: bar, cornerWidth: 1, cornerHeight: 1, transform: nil))
        }
        context.fillPath()
    }

    private func drawBullet(level: Int, dash: Bool, left: CGFloat, top: CGFloat, in context: CGContext) {
        let center = CGPoint(x: left + CGFloat(level) * slot + slot / 2, y: top + firstLine.midY)
        context.setFillColor(decoration.fill.cgColor)
        if dash {
            let width = decoration.bodyPointSize * Self.dashScale
            let thickness = (decoration.bodyPointSize * Self.dashThicknessScale).rounded()
            let bar = CGRect(
                x: center.x - width / 2, y: (center.y - thickness / 2).rounded(),
                width: width, height: thickness)
            let radius = thickness / 2
            context.addPath(CGPath(roundedRect: bar, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
            return
        }
        let diameter = decoration.bodyPointSize * Self.bulletScale
        context.fillEllipse(
            in: CGRect(
                x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
    }

    private func drawLabel(_ label: String, level: Int, left: CGFloat, top: CGFloat, in context: CGContext) {
        let font = decoration.bodyFont
        let line = Self.line(label, font: font, color: decoration.ink)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let slotEnd = left + CGFloat(level + 1) * slot - NoteListGeometry.labelPadding(bodyFont: font)
        Self.draw(line, at: CGPoint(x: slotEnd - width, y: top + firstBaseline), in: context)
    }

    private func drawBox(level: Int, checked: Bool, left: CGFloat, top: CGFloat, in context: CGContext) {
        let box = NoteListGeometry.rect(
            level: level, firstLineHeight: firstLine.height, bodyFont: decoration.bodyFont
        ).offsetBy(dx: left, dy: top + firstLine.minY)
        context.addPath(Self.roundedBox(box))
        context.setFillColor(decoration.fill.cgColor)
        context.fillPath()
        guard checked else { return }
        context.move(to: CGPoint(x: box.minX + box.width * 0.25, y: box.minY + box.height * 0.55))
        context.addLine(to: CGPoint(x: box.minX + box.width * 0.45, y: box.minY + box.height * 0.75))
        context.addLine(to: CGPoint(x: box.minX + box.width * 0.78, y: box.minY + box.height * 0.30))
        context.setStrokeColor(decoration.ink.cgColor)
        context.setLineWidth(box.width * Self.checkStrokeScale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    // MARK: - Geometry and text

    /// Rounds only the requested ends, so stacked rows of one band meet without a gap at the seams.
    private static func bandPath(_ rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let corners = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), topRadius),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY), topRadius),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY), bottomRadius),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY), bottomRadius)
        ]
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        for (corner, next, radius) in corners {
            path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
        }
        path.closeSubpath()
        return path
    }

    private static func roundedBox(_ rect: CGRect) -> CGPath {
        let radius = rect.width * boxRadiusScale
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func line(_ string: String, font: NSFont, color: NSColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    /// The view is flipped, so Core Text's y axis is flipped back before a line is drawn.
    private static func draw(_ line: CTLine, at baseline: CGPoint, in context: CGContext) {
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = baseline
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
