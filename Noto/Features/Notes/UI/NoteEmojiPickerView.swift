import SwiftUI

/// The `:` emoji list's rows, in the shared menu-row look. The selected row is the one Return takes.
struct NoteEmojiPickerView: View {
    @Environment(NotesCoordinator.self) private var notes

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
    }

    var body: some View {
        VStack(spacing: Theme.Size.menuRowSpacing) {
            if let picker = notes.emojiPicker {
                ForEach(Array(picker.candidates.enumerated()), id: \.offset) { index, emoji in
                    NoteEmojiPickerRow(emoji: emoji, isSelected: index == picker.selection) {
                        notes.chooseEmoji(at: index)
                    }
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: surface)
        .clipShape(surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Emoji")
    }
}

private struct NoteEmojiPickerRow: View {
    let emoji: Emoji
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Text(emoji.character)
                    .font(Theme.Typography.menuRow)
                    .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
                Text(emoji.name)
                    .font(Theme.Typography.menuRow)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(
                maxWidth: .infinity, minHeight: Theme.Size.menuRowHeight,
                maxHeight: Theme.Size.menuRowHeight, alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(isSelected || hovered ? Theme.Colors.menuHover : Color.clear))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
        .accessibilityLabel(emoji.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
