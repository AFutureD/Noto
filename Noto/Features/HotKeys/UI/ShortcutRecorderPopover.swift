import SwiftUI

/// Bounds of the open recorder, so an ancestor outside the `ScrollView` can draw it.
struct ShortcutRecorderAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// The callout above the field: what to press, what is held, or what is in the way.
struct ShortcutRecorderPopover: View {
    let placement: CalloutPlacement

    @Environment(HotKeyManager.self) private var hotKeys
    private var capture: ShortcutCaptureSession { hotKeys.capture }

    private struct State {
        let caps: [String]
        let label: String
        var isExample = false
        var tint: Color?
    }

    var body: some View {
        let state = self.state
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(state.caps.enumerated()), id: \.offset) { _, cap in
                    KeyCapChip(text: cap, scale: .hero)
                }
            }
            .frame(height: Theme.Size.heroKeyCap)
            .opacity(state.isExample ? 0.5 : 1)

            Text(state.label)
                .font(Theme.Typography.compactKeyCap)
                .foregroundStyle(state.tint ?? Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: Theme.Size.shortcutPopoverLine)
        }
        .offset(y: Theme.Spacing.sm + 1)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .padding(placement.caretEdge == .top ? .top : .bottom, Theme.Size.calloutCaretHeight)
        .frame(
            width: Theme.Size.shortcutPopover.width, height: Theme.Size.shortcutPopover.height
        )
        .overlay(alignment: .topLeading) {
            KeyCapChip(text: "esc", scale: .compact)
                .opacity(0.7)
                .padding(.leading, Theme.Spacing.md)
                .padding(
                    .top,
                    Theme.Spacing.sm
                        + (placement.caretEdge == .top ? Theme.Size.calloutCaretHeight : 0))
        }
        // Stock glass owns its elevation — no hand-tuned shadow.
        .glassEffect(
            .regular, in: CalloutShape(caretEdge: placement.caretEdge, caretX: placement.caretX))
    }

    private var state: State {
        if let conflict = capture.conflict {
            return State(caps: conflict.shortcut.keycaps, label: conflict.owner, tint: .orange)
        }
        let flags =
            capture.heldGlobe
            ? capture.heldModifiers.union(.function) : capture.heldModifiers
        let held = KeyShortcut.modifierSymbols(from: flags)
        guard held.isEmpty else { return State(caps: held, label: "Add a key") }
        return State(caps: ["⌥", "A"], label: "Type a shortcut", isExample: true)
    }
}

// MARK: - Host

/// Draws the open recorder's callout over the pane, where the pane's `ScrollView` can't clip it.
private struct ShortcutRecorderPopoverHost: ViewModifier {
    @Environment(HotKeyManager.self) private var hotKeys

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(ShortcutRecorderAnchorKey.self) { anchor in
            GeometryReader { proxy in
                ShortcutRecorderPopoverLayer(
                    placement: anchor.map { placement(field: proxy[$0], in: proxy.size) },
                    recordingCommand: hotKeys.recordingCommand)
            }
            // Informational: clicks fall through to the session's mouse monitor, which closes.
            .allowsHitTesting(false)
        }
    }

    private func placement(field: CGRect, in size: CGSize) -> CalloutPlacement {
        CalloutPlacement.resolve(
            field: field, container: size, size: Theme.Size.shortcutPopover,
            gap: Theme.Spacing.sm, inset: Theme.Spacing.xs,
            cornerRadius: Theme.Radius.menuPanel, caretWidth: Theme.Size.calloutCaretWidth)
    }
}

/// Retains the last anchor while the callout animates away from it.
private struct ShortcutRecorderPopoverLayer: View {
    let placement: CalloutPlacement?
    let recordingCommand: HotKeyCommand?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentedPlacement: CalloutPlacement?
    @State private var isVisible = false

    var body: some View {
        Color.clear.overlay {
            if let presentedPlacement {
                ShortcutRecorderPopover(placement: presentedPlacement)
                    .scaleEffect(
                        isVisible ? 1 : 0.5, anchor: scaleAnchor(for: presentedPlacement)
                    )
                    .opacity(isVisible ? 1 : 0)
                    .position(presentedPlacement.center)
            }
        }
        .onChange(of: placement, initial: true) { _, placement in
            guard let placement, recordingCommand != nil else { return }
            present(at: placement)
        }
        .onChange(of: recordingCommand, initial: true) { _, recordingCommand in
            if recordingCommand == nil {
                withAnimation(exitAnimation) { isVisible = false }
            } else if let placement {
                present(at: placement)
            }
        }
        .task(id: isVisible) {
            guard !isVisible, presentedPlacement != nil else { return }
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(Theme.Duration.exit))
            }
            guard !Task.isCancelled, !isVisible else { return }
            presentedPlacement = nil
        }
    }

    private var entryAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: Theme.Duration.enter)
    }

    private var exitAnimation: Animation? {
        reduceMotion ? nil : .easeIn(duration: Theme.Duration.exit)
    }

    private func present(at placement: CalloutPlacement) {
        presentedPlacement = placement
        guard !isVisible else { return }
        Task { @MainActor in
            await Task.yield()
            guard recordingCommand != nil, presentedPlacement == placement else { return }
            withAnimation(entryAnimation) { isVisible = true }
        }
    }

    private func scaleAnchor(for placement: CalloutPlacement) -> UnitPoint {
        placement.caretEdge == .bottom ? .bottom : .top
    }
}

extension View {
    /// Hosts the shortcut recorder's callout for every recorder inside this view.
    func shortcutRecorderPopoverHost() -> some View {
        modifier(ShortcutRecorderPopoverHost())
    }
}
