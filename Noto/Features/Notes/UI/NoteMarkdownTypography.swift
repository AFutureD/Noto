import AppKit

/// The editor's `NSFont`s: the system text styles one step up, since a note is for reading.
@MainActor
enum NoteMarkdownTypography {
    typealias Attributes = [NSAttributedString.Key: Any]

    static var body: NSFont { fonts.body }
    static var heading1: NSFont { fonts.heading1 }
    static var heading2: NSFont { fonts.heading2 }
    static var heading3: NSFont { fonts.heading3 }
    static var inlineCode: NSFont { fonts.inlineCode }
    static var codeBlock: NSFont { fonts.codeBlock }
    /// Small enough that a hidden marker leaves no visible gap, while staying a real glyph run.
    static let hidden = NSFont.systemFont(ofSize: 0.01)

    /// The body size when the user sets none.
    static let standardBodySize = size(.title3)

    /// The font an ordered list's number is drawn in, nil while the text family is the system's.
    static var labelFontName: String? { settings.textFamily == nil ? nil : fonts.body.fontName }

    private(set) static var settings = NoteFontSettings.standard
    private static var fonts = Fonts(.standard)
    private static var emphasisCache: [EmphasisKey: Attributes] = [:]
    private static var codeCache: [CGFloat: NSFont] = [:]

    private static let syntheticObliqueness = 0.2
    /// Negative strokes and fills, in percent of the point size.
    private static let syntheticBoldStroke = -3.0

    /// Returns false when `next` is what the fonts were already built from.
    static func apply(_ next: NoteFontSettings) -> Bool {
        guard next != settings else { return false }
        settings = next
        fonts = Fonts(next)
        emphasisCache.removeAll(keepingCapacity: true)
        codeCache.removeAll(keepingCapacity: true)
        return true
    }

    /// Levels 4 to 6 share the third heading's style.
    static func heading(_ level: Int) -> NSFont {
        switch level {
        case 1: heading1
        case 2: heading2
        default: heading3
        }
    }

    /// The heading's font, plus a drawn weight when its family has no bold face.
    static func headingLook(_ level: Int) -> Attributes {
        let font = heading(level)
        guard !font.fontDescriptor.symbolicTraits.contains(.bold) else { return [.font: font] }
        return [.font: font, .strokeWidth: syntheticBoldStroke]
    }

    /// `font` with `traits`, drawn where the family has no face for one of them.
    static func emphasized(_ font: NSFont, with traits: NSFontDescriptor.SymbolicTraits) -> Attributes {
        let key = EmphasisKey(name: font.fontName, size: font.pointSize, traits: traits.rawValue)
        if let cached = emphasisCache[key] { return cached }
        var face = font
        var look: Attributes = [:]
        for (trait, attribute, value) in [
            (NSFontDescriptor.SymbolicTraits.bold, NSAttributedString.Key.strokeWidth, syntheticBoldStroke),
            (.italic, .obliqueness, syntheticObliqueness)
        ] where traits.contains(trait) {
            if let variant = Self.variant(of: face, adding: trait) {
                face = variant
            } else {
                look[attribute] = value
            }
        }
        look[.font] = face === font ? font : cascaded(face)
        emphasisCache[key] = look
        return look
    }

    static func inlineCode(matching font: NSFont) -> NSFont {
        let size = font.pointSize
        if size == body.pointSize { return inlineCode }
        if let cached = codeCache[size] { return cached }
        let code = cascaded(Self.code(size: size))
        codeCache[size] = code
        return code
    }

    // MARK: - Construction

    private struct EmphasisKey: Hashable {
        let name: String
        let size: CGFloat
        let traits: UInt32
    }

    private struct Fonts {
        let body: NSFont
        let heading1: NSFont
        let heading2: NSFont
        let heading3: NSFont
        let inlineCode: NSFont
        let codeBlock: NSFont

        @MainActor
        init(_ settings: NoteFontSettings) {
            let bodySize = settings.size.map { CGFloat($0) } ?? standardBodySize
            let scale = bodySize / standardBodySize
            let text = { (family: String?, style: NSFont.TextStyle, weight: NSFont.Weight) in
                NoteMarkdownTypography.cascaded(
                    NoteMarkdownTypography.text(
                        family: family, size: (size(style) * scale).rounded(), weight: weight),
                    onto: settings.cjkFamily)
            }
            let headingFamily = settings.headingFamily ?? settings.textFamily
            let code = { (size: CGFloat) in
                NoteMarkdownTypography.cascaded(
                    NoteMarkdownTypography.code(family: settings.codeFamily, size: size),
                    onto: settings.cjkFamily)
            }
            body = text(settings.textFamily, .title3, .regular)
            heading1 = text(headingFamily, .largeTitle, .bold)
            heading2 = text(headingFamily, .title1, .bold)
            heading3 = text(headingFamily, .title2, .semibold)
            inlineCode = code(body.pointSize)
            codeBlock = code(body.pointSize - 1)
        }
    }

    private static func size(_ style: NSFont.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: style).pointSize
    }

    /// A family that is not installed falls back to the system font; the setting itself is kept.
    private static func text(family: String?, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        guard let base = named(family, size: size) else { return .systemFont(ofSize: size, weight: weight) }
        guard weight != .regular else { return base }
        return variant(of: base, adding: .bold) ?? base
    }

    private static func code(family: String?, size: CGFloat) -> NSFont {
        named(family, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func code(size: CGFloat) -> NSFont {
        code(family: settings.codeFamily, size: size)
    }

    private static func named(_ family: String?, size: CGFloat) -> NSFont? {
        guard let family,
            let font = NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: size),
            font.familyName == family
        else { return nil }
        return font
    }

    /// Nil when the family has no face with the trait, so the caller can draw it instead.
    private static func variant(of font: NSFont, adding trait: NSFontDescriptor.SymbolicTraits) -> NSFont? {
        let current = font.fontDescriptor.symbolicTraits
        guard !current.contains(trait) else { return font }
        let descriptor = font.fontDescriptor.withSymbolicTraits(current.union(trait))
        guard let variant = NSFont(descriptor: descriptor, size: font.pointSize),
            variant.fontDescriptor.symbolicTraits.contains(trait)
        else { return nil }
        return variant
    }

    private static func cascaded(_ font: NSFont) -> NSFont {
        cascaded(font, onto: settings.cjkFamily)
    }

    /// The cascade entry takes the font's own weight: a descriptor's traits do not reach its list.
    private static func cascaded(_ font: NSFont, onto family: String?) -> NSFont {
        guard let family else { return font }
        var fallback = NSFontDescriptor(fontAttributes: [.family: family])
        if font.fontDescriptor.symbolicTraits.contains(.bold) {
            let bold = fallback.withSymbolicTraits(.bold)
            if NSFont(descriptor: bold, size: font.pointSize)?.familyName == family { fallback = bold }
        }
        let descriptor = font.fontDescriptor.addingAttributes([.cascadeList: [fallback]])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}
