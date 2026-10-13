import QuartzCore
import SwiftUI

/// Central design tokens. Dark is the baseline; each colour resolves against the appearance.
enum Theme {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 20
    }

    enum Radius {
        static let panel: CGFloat = 26
        static let row: CGFloat = 10
        static let menu: CGFloat = 6
        /// Hover highlight behind a popover menu row.
        static let menuRow: CGFloat = 10
        /// A header pop-up button; the footer's action pills stay capsules.
        static let barControl: CGFloat = 8
        static let menuPanel: CGFloat = 16
        static let keyCap: CGFloat = 6
        /// Settings shortcut-recorder keycap — smaller than the standard `keyCap` chip.
        static let recorderKeyCap: CGFloat = 4
        static let tooltip: CGFloat = 8
    }

    enum Size {
        static let noteWindow = CGSize(width: 440, height: 180)
        /// The tallest a note window grows to fit its text; past it the editor scrolls.
        static let noteWindowMaxHeight: CGFloat = 860
        /// The editor's left and right margin, MDTextKit's "editor.side margin". The heading markers hang
        /// in it, so MDTextKit widens it for a large text size.
        static let noteSideMargin: CGFloat = 28
        /// Keeps the first line close under the title bar.
        static let noteEditorTopInset: CGFloat = 6
        /// The leading inset of the formatting band's character count.
        static let noteBandInset: CGFloat = 16
        static let noteSearchHeight: CGFloat = 34
        /// The switcher popover, sized independently of a note window that can be 180pt tall.
        static let noteSwitcher = CGSize(width: 300, height: 240)
        static let noteSwitcherEmptyHeight: CGFloat = 96
        static let noteSwitcherDrop: CGFloat = 56
        /// Fixed like every menu's width; the height is exactly the menu's rows.
        static func noteBarMenu(rows: Int) -> CGSize {
            CGSize(
                width: 220,
                height: menuRowHeight * CGFloat(rows) + menuRowSpacing * CGFloat(rows - 1) + Spacing.sm * 2)
        }
        static let noteFooterHeight: CGFloat = 28
        /// Holds the 36-point action capsule with an even margin above and below.
        static let noteTitlebar: CGFloat = 52
        /// Symmetric, so the title stays centred on the window while clearing lights and capsule.
        static let noteTitleInset: CGFloat = 120
        /// Nine points crowds the panel's 26-point corner, so Notes seats its lights further in.
        static let noteTrafficLightInset: CGFloat = 20
        static let bottomBarHeight: CGFloat = 52
        /// A `BarButton`'s hover capsule, shared by the footer group and the header's filter.
        static let barButtonHeight: CGFloat = 28
        static let rowIcon: CGFloat = 24
        static let keyCap: CGFloat = 18
        /// Settings shortcut-recorder keycap — smaller than the standard `keyCap` chip.
        static let recorderKeyCap: CGFloat = 16
        /// Fixed so the recorder can't resize as its binding changes.
        static let shortcutRecorder: CGFloat = 120
        /// One text line in the recorder callout.
        static let shortcutPopoverLine: CGFloat = 14
        /// Summed from the laid-out bands.
        static let shortcutPopover = CGSize(
            width: 132,
            height: Spacing.sm * 2 + heroKeyCap + Spacing.sm + shortcutPopoverLine + Spacing.sm
                + compactKeyCap + calloutCaretHeight)
        /// The callout's pointer: a triangle with a rounded tip.
        static let calloutCaretWidth: CGFloat = 15
        static let calloutCaretHeight: CGFloat = 7
        static let calloutCaretTip: CGFloat = 2.5
        /// Keycaps: `compact` hints, `keyCap` is standard, `hero` where the cap is content.
        static let compactKeyCap: CGFloat = 15
        static let heroKeyCap: CGFloat = 22
        static let noteGlyph: CGFloat = 16
        static let noteEmptyGlyph: CGFloat = 28
        static let hairline: CGFloat = 1
        static let menuRowHeight: CGFloat = menuIcon + Spacing.md * 2
        static let menuRowSpacing: CGFloat = 1
        static let menuIcon: CGFloat = 20
        /// The Settings window's fixed width; each pane sets the height.
        static let settingsWidth: CGFloat = 600
        static let settingsLabelColumn: CGFloat = 180
        static let settingsSlider: CGFloat = 180
        static let settingsFontList = CGSize(width: 280, height: 360)
        /// The size a font name is drawn at beside its Aa button, in that font.
        static let settingsFontSample: CGFloat = 15
    }

    enum Duration {
        static let enter: TimeInterval = 0.18
        static let exit: TimeInterval = 0.12
        static let tooltip: TimeInterval = 0.15
        static let tooltipDelay: TimeInterval = 0.4
        static let menuChevron: TimeInterval = 0.34
    }

    /// Motion shared by Noto's menus and collapsing bars.
    @MainActor
    enum MenuMotion {
        static let chevronAnimation = Animation.timingCurve(
            0.16, 1, 0.3, 1, duration: Theme.Duration.menuChevron)
    }

    /// System text styles (not hardcoded sizes) so the UI honors Dynamic Type.
    enum Typography {
        static let rowTitle = Font.body
        static let rowTrailing = Font.callout
        static let keyCap = Font.caption
        /// Pair with the matching `Size` for `KeyCapChip.Scale`.
        static let compactKeyCap = Font.caption2
        static let heroKeyCap = Font.body
        static let inlineCode = Font.body.monospaced()
        static let bar = Font.callout.weight(.medium)
        static let disclosure = Font.caption.weight(.semibold)
        static let menuRow = Font.body
        static let menuIcon = Font.body
        static let menuSymbolSize: CGFloat = 14
        static let menuSymbolWeight = Font.Weight.medium
        static let noteTitle = Font.headline
    }

    enum Colors {
        /// Resolves against the window's `effectiveAppearance`, so a token repaints on its own.
        static func adaptive(dark: NSColor, light: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { $0.isDark ? dark : light })
        }

        /// The alpha ramp, inverted: white ink over the dark surface, black ink over the light one.
        static func ramp(dark: Double, light: Double) -> Color {
            adaptive(dark: .srgbInk(1, alpha: dark), light: .srgbInk(0, alpha: light))
        }

        /// The ramp's inverse: the scrim darkens the dark surface and lightens the light one.
        static let panelScrim = adaptive(dark: .srgbInk(0, alpha: 0.40), light: .srgbInk(1, alpha: 0.55))
        static let tooltipShadow = adaptive(
            dark: .srgbInk(0, alpha: 0.18), light: .srgbInk(0, alpha: 0.18))

        /// Selection fill, shared by every list so they look identical.
        static let selection = ramp(dark: 0.10, light: 0.09)
        /// Mouse hover: a fainter layer, visually distinct from selection.
        static let rowHover = ramp(dark: 0.05, light: 0.045)
        static let menuHover = ramp(dark: 0.10, light: 0.09)
        static let separator = ramp(dark: 0.10, light: 0.12)
        /// Small control surfaces: kbd chips, glyph tiles.
        static let controlSurface = ramp(dark: 0.10, light: 0.08)
        static let border = ramp(dark: 0.20, light: 0.18)
        static let textSecondary = ramp(dark: 0.60, light: 0.60)
        static let textTertiary = ramp(dark: 0.40, light: 0.42)
        static let menuSymbol = ramp(dark: 0.70, light: 0.70)
        static let noteText = ramp(dark: 0.90, light: 0.85)
        static let cardFill = ramp(dark: 0.05, light: 0.04)
        static let cardStroke = ramp(dark: 0.10, light: 0.10)
        /// A `==highlight==` span's default background: the marker-pen yellow, dimmed over Dark.
        static let highlight = adaptive(
            dark: NSColor(srgbRed: 1.0, green: 0.84, blue: 0.0, alpha: 0.35),
            light: NSColor(srgbRed: 1.0, green: 0.90, blue: 0.20, alpha: 0.60))
        static let destructive = Color.red
        /// The callout tints, one per kind: blue note, green tip, purple important, yellow warning, red caution.
        static let tintBlue = adaptive(dark: .srgb(0x215075), light: .srgb(0xC9E5FF))
        static let tintGreen = adaptive(dark: .srgb(0x355F3A), light: .srgb(0xCDF7BD))
        static let tintPurple = adaptive(dark: .srgb(0x6D487F), light: .srgb(0xFEDAFF))
        static let tintYellow = adaptive(dark: .srgb(0x66522E), light: .srgb(0xFCF195))
        static let tintRed = adaptive(dark: .srgb(0x683735), light: .srgb(0xFFD5D5))
    }
}

extension View {
    /// A floating glass control surface: regular, interactive Liquid Glass.
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive(), in: shape)
    }
}
