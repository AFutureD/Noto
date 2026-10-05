import AppKit

/// The questions Notes asks, injected so the coordinator never names how they are presented.
struct NotesDialogs {
    /// Title, message, confirm button; true when confirmed.
    let confirm: @MainActor (String, String, String) async -> Bool
    /// Title, message, optional recovery button; true when the recovery was chosen.
    let reportFailure: @MainActor (String, String, String?) async -> Bool
}

extension NotesDialogs {
    /// Noto has no dialog system of its own, so both questions are system alerts.
    @MainActor static let alerts = NotesDialogs(
        confirm: { title, message, confirmTitle in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: confirmTitle)
            alert.addButton(withTitle: "Cancel")
            return present(alert) == .alertFirstButtonReturn
        },
        reportFailure: { title, message, recovery in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            guard let recovery else {
                alert.addButton(withTitle: "OK")
                _ = present(alert)
                return false
            }
            alert.addButton(withTitle: recovery)
            alert.addButton(withTitle: "Cancel")
            return present(alert) == .alertFirstButtonReturn
        })

    /// The note panel never activates the app, so an alert would otherwise open behind the front app.
    @MainActor private static func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }
}
