import AppKit

/// Which shortcuts exist and what they run; `HotKeyCenter` owns the Carbon registrations.
@MainActor
@Observable
final class HotKeyManager {
    private let settings: NotoSettings
    @ObservationIgnored private let center = HotKeyCenter()
    @ObservationIgnored private var onCommand: (HotKeyCommand) -> Void = { _ in }
    let capture = ShortcutCaptureSession()

    /// The one recorder that is listening. Every hotkey is paused meanwhile, so a combo is captured.
    var recordingCommand: HotKeyCommand? {
        didSet {
            guard recordingCommand != oldValue else { return }
            center.isPaused = recordingCommand != nil
            if let recordingCommand {
                capture.start(command: recordingCommand, hotKeys: self)
            } else {
                capture.stop()
            }
        }
    }

    init(settings: NotoSettings) {
        self.settings = settings
    }

    func start(onCommand: @escaping (HotKeyCommand) -> Void) {
        self.onCommand = onCommand
        for command in HotKeyCommand.allCases { register(command) }
    }

    func shortcut(for command: HotKeyCommand) -> KeyShortcut? {
        settings.shortcuts[command]
    }

    func setShortcut(_ shortcut: KeyShortcut?, for command: HotKeyCommand) {
        settings.shortcuts[command] = shortcut
        register(command)
    }

    /// The command already holding `shortcut`, by title, or nil when it is free.
    func conflictOwner(of shortcut: KeyShortcut, excluding command: HotKeyCommand) -> String? {
        settings.shortcuts.first { $0.key != command && $0.value == shortcut }?.key.title
    }

    private func register(_ command: HotKeyCommand) {
        guard let shortcut = settings.shortcuts[command] else {
            center.unregister(id: command.rawValue)
            return
        }
        center.register(id: command.rawValue, shortcut: shortcut) { [weak self] in
            self?.onCommand(command)
        }
    }
}
