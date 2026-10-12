import SwiftUI

/// The open bar menu's rows, in the shared menu-row look.
struct NoteBarMenuView: View {
    @Environment(NotesCoordinator.self) private var notes

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
    }

    var body: some View {
        let menu = notes.presentedBarMenu ?? .heading
        VStack(spacing: Theme.Size.menuRowSpacing) {
            ForEach(menu.rows, id: \.title) { row in
                NoteBarMenuRow(
                    title: row.title, shortcut: row.shortcut, isCurrent: row.isCurrent(notes.formatting)
                ) {
                    notes.choose(row.action)
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: surface)
        .clipShape(surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(menu.title)
    }
}

private struct NoteBarMenuRow: View {
    let title: String
    let shortcut: String
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "checkmark")
                    .font(
                        .system(
                            size: Theme.Typography.menuSymbolSize, weight: Theme.Typography.menuSymbolWeight)
                    )
                    .foregroundStyle(Theme.Colors.menuSymbol)
                    .opacity(isCurrent ? 1 : 0)
                    .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
                Text(title)
                    .font(Theme.Typography.menuRow)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                HStack(spacing: Theme.Spacing.xxs) {
                    ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                        KeyCapChip(text: String(glyph), style: .outline)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(
                maxWidth: .infinity, minHeight: Theme.Size.menuRowHeight,
                maxHeight: Theme.Size.menuRowHeight, alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(hovered ? Theme.Colors.menuHover : Color.clear))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
