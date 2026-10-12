import AppKit
import SFThemeKit
import SwiftUI

/// The editor's theme and font overrides, built from `Theme` so the token source stays one file.
@MainActor
enum NoteEditorTheme {
    /// The body size: one system text style up, as the window chrome's text is `body`.
    static let standardBodySize = NSFont.preferredFont(forTextStyle: .title3).pointSize

    /// Every colour is a dynamic `NSColor`, so the editor follows the appearance without a reload.
    static func make() -> SFTheme {
        let text = NSColor(Theme.Colors.noteText)
        let secondary = NSColor(Theme.Colors.textSecondary)
        let tertiary = NSColor(Theme.Colors.textTertiary)
        let surface = NSColor(Theme.Colors.controlSurface)
        let card = NSColor(Theme.Colors.cardFill)
        let border = NSColor(Theme.Colors.border)
        let selection = NSColor(Theme.Colors.selection)
        func tint(_ color: Color) -> [String: Any] {
            ["background color": NSColor(color), "text color": text]
        }
        return SFTheme(
            name: "Noto",
            jsonObject: [
                "base": [
                    "text color": text,
                    "text secondary color": secondary,
                    "text tertiary color": tertiary,
                    "background color": NSColor.clear,
                    "background secondary color": card,
                    "background tertiary color": surface,
                    "stroke color": border,
                    "accent color": NSColor.controlAccentColor,
                    "selection color": selection
                ],
                "editor": [
                    "background color": NSColor.clear,
                    "text color": text,
                    "text light color": secondary,
                    "marker color": tertiary,
                    "accent color": NSColor.controlAccentColor,
                    "cursor color": text,
                    "link color": NSColor.linkColor,
                    "list marker color": secondary,
                    "selection color": selection,
                    "selection inactive color": selection,
                    "text font": "system",
                    "text size": standardBodySize,
                    "line height multiplier": 1.3,
                    "line width multiplier": 0,
                    "headers": [
                        "text color": text,
                        "font": "system-bold",
                        "modular scale": 1.125,
                        "line height multiplier": 1.2,
                        "add top bottom padding": 1,
                        "padding top multiplier": 0.5,
                        "padding bottom multiplier": 0.3
                    ],
                    "code": [
                        "text color": text,
                        "border color": border,
                        "background color": card,
                        "font": "system-mono"
                    ],
                    "task": ["background color": surface, "border color": secondary, "check color": text],
                    "tag": ["background color": surface, "text color": text, "marker color": secondary],
                    "highlighter": [
                        "default": tint(Theme.Colors.highlight),
                        "red": tint(Theme.Colors.tintRed),
                        "blue": tint(Theme.Colors.tintBlue),
                        "green": tint(Theme.Colors.tintGreen),
                        "yellow": tint(Theme.Colors.tintYellow),
                        "purple": tint(Theme.Colors.tintPurple)
                    ],
                    "separator": ["border color": NSColor(Theme.Colors.separator)],
                    "table": [
                        "border color": border,
                        "cell background color": NSColor.clear,
                        "cell alternate background color": card
                    ]
                ]
            ])
    }

    /// The settings as theme overrides. An uninstalled family leaves the theme's own font in place.
    static func overrides(fonts: NoteFontSettings, highlight: NoteHighlightColor?) -> [String: Any] {
        var overrides: [String: Any] = ["editor.text size": fonts.size ?? Double(standardBodySize)]
        if let name = postScriptName(family: fonts.textFamily, bold: false) {
            overrides["editor.text font"] = name
        }
        if let name = postScriptName(family: fonts.headingFamily ?? fonts.textFamily, bold: true) {
            overrides["editor.headers.font"] = name
        }
        if let name = postScriptName(family: fonts.codeFamily, bold: false) {
            overrides["editor.code.font"] = name
        }
        if let cjk = fonts.cjkFamily, postScriptName(family: cjk, bold: false) != nil {
            for key in ["editor.text font cjk", "editor.headers.font cjk", "editor.code.font cjk"] {
                overrides[key] = cjk
            }
        }
        if let highlight {
            overrides["editor.highlighter.default.background color"] = NSColor(
                srgbRed: highlight.red, green: highlight.green, blue: highlight.blue, alpha: highlight.alpha)
        }
        return overrides
    }

    /// The face a theme names: the family's bold face for headings, else its regular one.
    private static func postScriptName(family: String?, bold: Bool) -> String? {
        guard let family else { return nil }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        guard let regular = NSFont(descriptor: descriptor, size: standardBodySize),
            regular.familyName == family
        else { return nil }
        guard bold else { return regular.fontName }
        let heavy = NSFontManager.shared.font(withFamily: family, traits: .boldFontMask, weight: 9, size: standardBodySize)
        return (heavy?.isBold == true ? heavy : regular)?.fontName
    }
}
