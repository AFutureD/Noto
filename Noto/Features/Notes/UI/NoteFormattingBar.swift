import SwiftUI

/// The title bar capsule's recipe along the bottom: a button per common edit, a menu for the rest.
struct NoteFormattingBar: View {
    @Environment(NotesCoordinator.self) private var notes

    private struct Control: Sendable {
        let symbol: String
        let title: String
        let shortcut: String
        let action: NoteEditAction
        let isLit: @Sendable (NoteFormatting) -> Bool
    }

    private static let styles = [
        Control(symbol: "bold", title: "Bold", shortcut: "⌘B", action: .toggleInline(.bold)) {
            $0.inlineStyles.contains(.bold)
        },
        Control(symbol: "italic", title: "Italic", shortcut: "⌘I", action: .toggleInline(.italic)) {
            $0.inlineStyles.contains(.italic)
        },
        Control(
            symbol: "highlighter", title: "Highlight", shortcut: "⇧⌘H", action: .toggleInline(.highlight)
        ) { $0.inlineStyles.contains(.highlight) },
        Control(symbol: "link", title: "Link", shortcut: "⌘K", action: .toggleLink) { $0.isLink }
    ]

    private static let blocks = [
        Control(symbol: "text.quote", title: "Quote", shortcut: "⇧⌘B", action: .toggleQuote) { $0.isQuote }
    ]

    var body: some View {
        let formatting = notes.formatting
        let isExpanded = notes.isFormattingBarExpanded
        HStack(spacing: Theme.Spacing.sm) {
            if isExpanded {
                HStack(spacing: Theme.Spacing.sm) {
                    menuButton(.heading, formatting, tooltipAlignment: .leading)
                    group(Self.styles, formatting)
                    group(Self.blocks, formatting)
                    menuButton(.list, formatting, tooltipAlignment: .center)
                    menuButton(.more, formatting, tooltipAlignment: .trailing)
                }
                // Grows out of the round button; nothing leaves the capsule, so no clip is needed.
                .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            }
            NoteFormattingToggle(isExpanded: isExpanded, action: notes.toggleFormattingBar)
                // Drawn above the buttons, so they grow out from behind it.
                .zIndex(1)
        }
        .padding(Theme.Spacing.xs)
        // Behind the buttons, not around them: glass clips content, tooltips draw outside it.
        .background { Capsule().fill(Color.clear).frosted(in: Capsule()) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
    }

    private func group(_ controls: [Control], _ formatting: NoteFormatting) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(controls, id: \.title) { control in
                let lit = control.isLit(formatting)
                BarButton(isSelected: lit, isCompact: true, action: { notes.format(control.action) }) {
                    NoteBarGlyph(name: control.symbol)
                }
                .focusable(false)
                .accessibilityLabel(control.title)
                .accessibilityAddTraits(lit ? .isSelected : [])
                .tooltip("\(control.title)  \(control.shortcut)")
            }
        }
    }

    private func menuButton(
        _ menu: NoteBarMenu, _ formatting: NoteFormatting, tooltipAlignment: HorizontalAlignment
    ) -> some View {
        NoteMenuButton(
            menu: menu, isLit: menu.isLit(formatting), isOpen: notes.presentedBarMenu == menu,
            tooltipAlignment: tooltipAlignment, action: { notes.toggleBarMenu(menu) }
        ) { notes.barMenuButtonFrames[menu] = $0 }
    }
}

/// The bar's handle: one round button that shows and hides every other control.
private struct NoteFormattingToggle: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        BarButton(isSelected: isExpanded, isCompact: true, action: action) {
            NoteBarGlyph(name: "paintbrush")
        }
        .focusable(false)
        .accessibilityLabel("Formatting")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        // Against the window's trailing edge, so a centred label would run off it.
        .tooltip("Formatting  ⌥⌘T", alignment: .trailing)
    }
}

/// Symbols differ in width, so a fixed frame keeps every button the same square.
private struct NoteBarGlyph: View {
    let name: String

    var body: some View {
        SymbolImage(name: name, size: Theme.Size.noteGlyph)
            .frame(width: Theme.Size.noteGlyph, height: Theme.Size.noteGlyph)
    }
}

/// A glyph with a chevron that opens one of the bar's menus.
private struct NoteMenuButton: View {
    let menu: NoteBarMenu
    let isLit: Bool
    let isOpen: Bool
    let tooltipAlignment: HorizontalAlignment
    let action: () -> Void
    let onFrameChange: (CGRect) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BarButton(isSelected: isLit || isOpen, isCompact: true, action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                NoteBarGlyph(name: menu.symbol)
                // Rotates rather than swaps, so opening the menu cannot shift the bar.
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.disclosure)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(reduceMotion ? nil : Theme.MenuMotion.chevronAnimation, value: isOpen)
            }
        }
        // Its menu hangs off this frame, which only the laid-out view knows.
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            onFrameChange($0)
        }
        .focusable(false)
        .accessibilityLabel(menu.title)
        .accessibilityAddTraits(isLit ? .isSelected : [])
        .tooltip(isOpen ? nil : menu.title, alignment: tooltipAlignment)
    }
}
