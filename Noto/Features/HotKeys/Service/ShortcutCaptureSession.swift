import AppKit
import Carbon.HIToolbox

/// Local monitors for the one active recording. See docs/features/hotkeys.md#recorder.
@MainActor
@Observable
final class ShortcutCaptureSession {
    /// A rejected shortcut and whoever already holds it.
    struct Conflict: Equatable {
        let shortcut: KeyShortcut
        let owner: String
    }

    private(set) var heldModifiers: NSEvent.ModifierFlags = []
    private(set) var heldGlobe = false
    private(set) var conflict: Conflict?

    private static let conflictDwell: Duration = .seconds(1.5)

    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var conflictReset: Task<Void, Never>?
    @ObservationIgnored private weak var activeRecorderView: NSView?

    func start(command: HotKeyCommand, hotKeys: HotKeyManager) {
        stop()
        heldModifiers = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])

        // Main-thread handlers that predate actor annotations; only Sendable pieces cross in.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self, weak hotKeys] event in
                let keyCode = Int(event.keyCode)
                let flags = event.modifierFlags
                MainActor.assumeIsolated {
                    guard let self, let hotKeys else { return }
                    self.handleKeyDown(
                        keyCode: keyCode, flags: flags, command: command, hotKeys: hotKeys)
                }
                return nil  // always consume: no beeps, no leaking keys to the window
            })
        {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged,
            handler: { [weak self] event in
                let all = event.modifierFlags
                let keyCode = Int(event.keyCode)
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.heldModifiers = all.intersection([.command, .option, .control, .shift])
                    if keyCode == kVK_Function { self.heldGlobe = all.contains(.function) }
                }
                return event
            })
        {
            monitors.append(monitor)
        }

        // A click ends the recording then travels on, so one click can move to another row.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { @MainActor [weak self, weak hotKeys] event in
                guard self?.activeRecorderContains(event) != true else { return event }
                hotKeys?.recordingCommand = nil
                return event
            })
        {
            monitors.append(monitor)
        }

        // Local monitors go quiet on resign key, so treat it as a cancel and unpause.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak hotKeys] _ in
            MainActor.assumeIsolated { hotKeys?.recordingCommand = nil }
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        conflictReset?.cancel()
        conflictReset = nil
        conflict = nil
        heldModifiers = []
        heldGlobe = false
        activeRecorderView = nil
    }

    func setActiveRecorderView(_ view: NSView) {
        activeRecorderView = view
    }

    func clearActiveRecorderView(_ view: NSView) {
        if activeRecorderView === view { activeRecorderView = nil }
    }

    private func activeRecorderContains(_ event: NSEvent) -> Bool {
        guard let view = activeRecorderView, event.window === view.window else { return false }
        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }

    private func handleKeyDown(
        keyCode: Int, flags: NSEvent.ModifierFlags, command: HotKeyCommand, hotKeys: HotKeyManager
    ) {
        // F-keys also carry `.function`; only the physical Globe press makes it a modifier.
        let flags = heldGlobe ? flags.union(.function) : flags.subtracting(.function)
        let bareKey = flags.isDisjoint(with: [.command, .option, .control, .shift, .function])

        if bareKey, keyCode == kVK_Escape {
            hotKeys.recordingCommand = nil
            return
        }
        // Plain Delete clears the existing shortcut.
        if bareKey, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            hotKeys.setShortcut(nil, for: command)
            hotKeys.recordingCommand = nil
            return
        }
        // Not a bindable combo (e.g. a bare letter): swallow it and keep recording.
        guard let shortcut = KeyShortcut(keyCode: keyCode, modifierFlags: flags) else { return }
        if let owner = hotKeys.conflictOwner(of: shortcut, excluding: command) {
            flashConflict(Conflict(shortcut: shortcut, owner: owner))
            return
        }
        hotKeys.setShortcut(shortcut, for: command)
        hotKeys.recordingCommand = nil
    }

    private func flashConflict(_ rejected: Conflict) {
        conflict = rejected
        conflictReset?.cancel()
        conflictReset = Task { [weak self] in
            try? await Task.sleep(for: Self.conflictDwell)
            guard !Task.isCancelled else { return }
            self?.conflict = nil
        }
    }
}
