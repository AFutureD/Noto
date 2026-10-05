import AppKit
import SwiftUI

/// Deliberately not a focusable control. See docs/features/hotkeys.md#recorder.
struct ShortcutRecorder: View {
    let command: HotKeyCommand

    @Environment(HotKeyManager.self) private var hotKeys
    @State private var hovered = false

    private var isRecording: Bool { hotKeys.recordingCommand == command }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        content
            .padding(.horizontal, Theme.Spacing.sm + 1)
            .frame(width: Theme.Size.shortcutRecorder, height: 24)
            .background(shape.fill(Theme.Colors.cardFill))
            .background {
                if isRecording { ShortcutRecorderHitRegion(capture: hotKeys.capture) }
            }
            .overlay(shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
            // An over-long shortcut truncates rather than resizing the field.
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { toggleRecording() }
            .onHover { hovered = $0 }
            // Hand the callout this field's bounds while it's the open one.
            .anchorPreference(key: ShortcutRecorderAnchorKey.self, value: .bounds) {
                isRecording ? $0 : nil
            }
            .onDisappear { if isRecording { hotKeys.recordingCommand = nil } }
            .animation(.easeOut(duration: 0.12), value: hovered)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(command.title) shortcut")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleRecording() }
    }

    private func toggleRecording() {
        hotKeys.recordingCommand = isRecording ? nil : command
    }

    @ViewBuilder
    private var content: some View {
        if let shortcut = hotKeys.shortcut(for: command) {
            boundLabel(shortcut)
        } else {
            Text(isRecording ? "Listening…" : "Record Hotkey")
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func boundLabel(_ shortcut: KeyShortcut) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(shortcut.keycaps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .frame(
                        minWidth: Theme.Size.recorderKeyCap, minHeight: Theme.Size.recorderKeyCap
                    )
                    .background(
                        RoundedRectangle(
                            cornerRadius: Theme.Radius.recorderKeyCap, style: .continuous
                        )
                        .fill(Color.primary.opacity(0.08))
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.keycaps.joined(separator: " "))
        .frame(maxWidth: .infinity)
        // Overlaid, not a row member, so it costs the caps no width.
        .overlay(alignment: .trailing) {
            Button {
                hotKeys.setShortcut(nil, for: command)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear shortcut")
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
        }
    }
}

private struct ShortcutRecorderHitRegion: NSViewRepresentable {
    let capture: ShortcutCaptureSession

    func makeNSView(context: Context) -> PassiveView {
        let view = PassiveView()
        view.capture = capture
        capture.setActiveRecorderView(view)
        return view
    }

    func updateNSView(_ view: PassiveView, context: Context) {
        if view.capture !== capture { view.capture?.clearActiveRecorderView(view) }
        view.capture = capture
        capture.setActiveRecorderView(view)
    }

    static func dismantleNSView(_ view: PassiveView, coordinator: ()) {
        view.capture?.clearActiveRecorderView(view)
    }

    final class PassiveView: NSView {
        weak var capture: ShortcutCaptureSession?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
