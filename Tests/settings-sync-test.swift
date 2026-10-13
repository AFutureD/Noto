import Foundation

@main
@MainActor
struct SettingsSyncTests {
    private static var failures = 0

    static func main() async throws {
        await testFreshMacAdoptsTheCloud()
        await testFreshMacPublishesNoDefaults()
        await testSwitchingOnPublishesOnlyWhatWasSet()
        await testSwitchingOnLetsTheCloudWin()
        await testLocalChangesPublishWhileOn()
        await testRemoteChangesApplyOnlyWhileOn()
        await testRemoteSwitchOffStopsPublishing()
        await testAdoptingDoesNotEcho()
        await testForeignAndInvalidValuesAreContained()

        print(failures == 0 ? "Settings sync tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testFreshMacAdoptsTheCloud() async {
        let rig = Rig()
        rig.store.values = [
            "settings.syncsWithICloud": ["iCloudSync": true],
            "settings.fonts": ["notesFontSize": 20.0, "notesCodeFont": "Menlo"],
        ]
        rig.start()
        check("a fresh Mac turns sync on when iCloud has it on", rig.settings.syncsWithICloud)
        check(
            "a fresh Mac takes the fonts from iCloud",
            rig.settings.fonts.size == 20 && rig.settings.fonts.codeFamily == "Menlo")
        check("adopting writes nothing back", rig.store.writes == 0)
    }

    private static func testFreshMacPublishesNoDefaults() async {
        let rig = Rig()
        rig.start()
        check("a fresh Mac with iCloud empty stays off", !rig.settings.syncsWithICloud)
        check("a fresh Mac publishes nothing", rig.store.values.isEmpty)
    }

    private static func testSwitchingOnPublishesOnlyWhatWasSet() async {
        let rig = Rig()
        rig.start()
        rig.settings.highlightColor = NoteHighlightColor(hex: "#11223344")
        check("nothing publishes while sync is off", rig.store.values.isEmpty)
        rig.settings.syncsWithICloud = true
        check("the switch publishes", rig.cloud("syncsWithICloud")?["iCloudSync"] as? Bool == true)
        check(
            "a preference set on this Mac publishes",
            rig.cloud("highlightColor")?["notesHighlightColor"] as? String == "#11223344")
        check("a preference at its default does not publish", rig.cloud("showsFormattingBar") == nil && rig.cloud("fonts") == nil)
    }

    private static func testSwitchingOnLetsTheCloudWin() async {
        let rig = Rig()
        rig.store.values = ["settings.accentColor": ["notesAccentColor": "#102030"]]
        rig.start()
        rig.settings.accentColor = NoteAccentColor(hex: "#AABBCC")
        rig.settings.syncsWithICloud = true
        check("iCloud's value replaces the local one when sync turns on", rig.settings.accentColor?.hex == "#102030")
    }

    private static func testLocalChangesPublishWhileOn() async {
        let rig = Rig(on: true)
        rig.start()
        rig.settings.fonts.size = 18
        check("a local change publishes while on", rig.cloud("fonts")?["notesFontSize"] as? Double == 18)
        rig.settings.fonts = .standard
        check("a reset publishes as an empty value", rig.cloud("fonts")?.isEmpty == true)
        rig.settings.showsInDock = true
        check("a General preference never publishes", rig.store.values.keys.allSatisfy { !$0.contains("Dock") })
    }

    private static func testRemoteChangesApplyOnlyWhileOn() async {
        let rig = Rig(on: true)
        rig.start()
        var remote: [NotoSettings.Synced] = []
        rig.mirror.onRemoteChange = { remote.append($0) }
        rig.store.values["settings.showsFormattingBar"] = ["notesShowsFormattingBar": false]
        await rig.post(["settings.showsFormattingBar"])
        check("a remote change applies while on", !rig.settings.showsFormattingBar)
        check("a remote change is reported", remote == [.showsFormattingBar])

        let off = Rig()
        off.start()
        off.store.values["settings.showsFormattingBar"] = ["notesShowsFormattingBar": false]
        await off.post(["settings.showsFormattingBar"])
        check("a remote change is ignored while off", off.settings.showsFormattingBar)
    }

    private static func testRemoteSwitchOffStopsPublishing() async {
        let rig = Rig(on: true)
        rig.start()
        rig.store.values["settings.syncsWithICloud"] = ["iCloudSync": false]
        await rig.post(["settings.syncsWithICloud"])
        check("another Mac turning sync off turns it off here", !rig.settings.syncsWithICloud)
        let writes = rig.store.writes
        rig.settings.fonts.size = 22
        check("nothing publishes after a remote switch-off", rig.store.writes == writes)
    }

    private static func testAdoptingDoesNotEcho() async {
        let rig = Rig(on: true)
        rig.start()
        let writes = rig.store.writes
        let json = #"{"showNotes":{"carbonKeyCode":45,"carbonModifiers":2304}}"#
        rig.store.values["settings.shortcuts"] = ["hotKeys": Data(json.utf8)]
        await rig.post(["settings.shortcuts"])
        check(
            "a remote shortcut applies",
            rig.settings.shortcuts[.showNotes] == KeyShortcut(carbonKeyCode: 45, carbonModifiers: 2304))
        check("a remote change is not written back", rig.store.writes == writes)
    }

    private static func testForeignAndInvalidValuesAreContained() async {
        let rig = Rig(on: true)
        rig.store.values["settings.fonts"] = ["notesFontSize": "big", "showsInDock": true, "notesTextFont": "Avenir"]
        rig.start()
        check("an invalid member falls back to its default", rig.settings.fonts.size == nil)
        check("a valid member still applies", rig.settings.fonts.textFamily == "Avenir")
        check("a key outside the preference is not written", !rig.settings.showsInDock)
    }

    // MARK: - Support

    private final class FakeStore: CloudKeyValueStore {
        var values: [String: Any] = [:]
        var writes = 0
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) {
            values[key] = value
            writes += 1
        }
        func synchronize() -> Bool { true }
    }

    @MainActor
    private struct Rig {
        /// Numbered, not random: each run reuses the same few preference files instead of adding more.
        static var count = 0
        let store = FakeStore()
        let center = NotificationCenter()
        let settings: NotoSettings
        let mirror: CloudSettingsMirror

        init(on: Bool = false) {
            Self.count += 1
            let suite = "noto-settings-sync-test-\(Self.count)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            if on { defaults.set(true, forKey: "iCloudSync") }
            settings = NotoSettings(defaults: defaults)
            mirror = CloudSettingsMirror(settings: settings, store: store, center: center)
        }

        func start() { mirror.start() }

        func cloud(_ synced: String) -> [String: Any]? {
            store.values["settings.\(synced)"] as? [String: Any]
        }

        func post(_ keys: [String]) async {
            center.post(
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store,
                userInfo: [
                    NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreServerChange,
                    NSUbiquitousKeyValueStoreChangedKeysKey: keys,
                ])
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        if condition() { return }
        failures += 1
        print("FAIL: \(name)")
    }
}
