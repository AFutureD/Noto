import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationRequestInFlight = false

    /// Must land before the first scroll view exists, or the scroller switch shows as a flash.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCore.shared.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Without Show in Dock the icon only stands for the open windows, so its Quit closes them.
        let core = AppCore.shared
        if isQuitFromDock, !core.settings.showsInDock, core.activationPolicy.hasOpenWindows {
            core.activationPolicy.closeAll()
            return .terminateCancel
        }
        guard !terminationRequestInFlight else { return .terminateLater }
        terminationRequestInFlight = true
        Task { @MainActor [weak self] in
            // A 300 ms-debounced draft still has to reach disk, but it can no longer veto the quit.
            await AppCore.shared.flushNotesForTermination()
            self?.terminationRequestInFlight = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.handleReopen()
        return false
    }

    /// The note panel and Settings each close on their own; the agent outlives both.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// ⌘Q and the menu-bar item call `terminate` directly; only an Apple Event names a sender.
    private var isQuitFromDock: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
            event.eventClass == kCoreEventClass, event.eventID == kAEQuitApplication,
            let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value
        else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock"
    }
}
