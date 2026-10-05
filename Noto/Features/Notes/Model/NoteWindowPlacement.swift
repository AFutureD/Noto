import CoreGraphics

enum NoteWindowPlacement {
    static func topRight(_ frame: CGRect, in visibleFrame: CGRect, inset: CGFloat) -> CGRect {
        let horizontalInset = min(inset, max(0, visibleFrame.width - frame.width))
        let verticalInset = min(inset, max(0, visibleFrame.height - frame.height))
        return CGRect(
            x: visibleFrame.maxX - frame.width - horizontalInset,
            y: visibleFrame.maxY - frame.height - verticalInset,
            width: frame.width,
            height: frame.height)
    }
}
