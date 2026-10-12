import AppKit

/// Where list markers sit, shared by styling, drawing and hit testing so what shows is what clicks.
enum NoteListGeometry {
    /// One list level's marker slot: the shared width grown with the body size, or `0. ` if that is wider.
    static func slot(bodyFont: NSFont) -> CGFloat {
        let scaled = (Theme.Size.markdownListMarker * bodyFont.pointSize / NSFont.systemFontSize).rounded()
        return max(scaled, width(of: "0. ", in: bodyFont).rounded(.up))
    }

    /// The gap between a drawn number and its text: the space the source puts there.
    static func labelPadding(bodyFont: NSFont) -> CGFloat {
        width(of: " ", in: bodyFont)
    }

    /// The box in fragment-local coordinates whose x origin is the container's left edge.
    static func rect(level: Int, firstLineHeight: CGFloat, bodyFont: NSFont) -> CGRect {
        let side = bodyFont.pointSize.rounded()
        let slot = slot(bodyFont: bodyFont)
        return CGRect(
            x: CGFloat(level) * slot + (slot - side) / 2, y: (firstLineHeight - side) / 2,
            width: side, height: side)
    }

    private static func width(of string: String, in font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }
}
