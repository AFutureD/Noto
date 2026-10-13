import Foundation
import os

/// Mirrors the synced preferences to iCloud key-value storage. `UserDefaults` stays the source of
/// truth; iCloud holds a copy each Mac reads back. See docs/features/sync.md.
@MainActor
final class CloudSettingsMirror {
    /// Called after a remote value replaced a local preference.
    var onRemoteChange: (NotoSettings.Synced) -> Void = { _ in }

    private let settings: NotoSettings
    private let store: any CloudKeyValueStore
    private let center: NotificationCenter
    private var observation: NotificationToken?

    init(
        settings: NotoSettings,
        store: any CloudKeyValueStore = NSUbiquitousKeyValueStore.default,
        center: NotificationCenter = .default
    ) {
        self.settings = settings
        self.store = store
        self.center = center
    }

    /// Observes before it synchronizes, so no change that lands during the first read is missed.
    func start() {
        let token = center.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated { self?.receive(reason: reason, keys: keys) }
        }
        observation = NotificationToken(token, center: center)
        settings.onSyncedChange = { [weak self] in self?.send($0) }
        store.synchronize()
        catchUp()
    }

    // MARK: - Private

    /// The switch follows iCloud when iCloud has one; every other preference follows it only while on.
    private func catchUp() {
        adopt(.syncsWithICloud)
        if settings.syncsWithICloud { reconcile() }
    }

    private func receive(reason: Int?, keys: [String]) {
        switch reason {
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            Logger.sync.error("iCloud key-value storage is over its quota; settings are not syncing")
        case NSUbiquitousKeyValueStoreServerChange:
            let changed = NotoSettings.Synced.allCases.filter { keys.contains(Self.cloudKey(for: $0)) }
            Logger.sync.info("iCloud changed settings: \(changed.map(\.rawValue), privacy: .public)")
            if changed.contains(.syncsWithICloud) {
                catchUp()
                return
            }
            guard settings.syncsWithICloud else { return }
            changed.forEach(adopt)
        default:
            // The first download on this Mac, or another iCloud account: everything may differ.
            Logger.sync.info("iCloud settings reloaded (reason \(reason ?? -1, privacy: .public))")
            catchUp()
        }
    }

    /// A local change, or the echo of a remote one, which `publish` then finds already in iCloud.
    private func send(_ synced: NotoSettings.Synced) {
        if synced == .syncsWithICloud {
            guard publish(.syncsWithICloud), settings.syncsWithICloud else { return }
            reconcile()
            return
        }
        guard settings.syncsWithICloud else { return }
        publish(synced)
    }

    /// iCloud wins where it has a value; a preference only this Mac has set goes up.
    private func reconcile() {
        for synced in NotoSettings.Synced.allCases where synced != .syncsWithICloud {
            if cloudValue(of: synced) != nil {
                adopt(synced)
            } else if !settings.storedValue(of: synced).isEmpty {
                publish(synced)
            }
        }
    }

    /// Replaces the local preference with iCloud's, when iCloud has one and it differs.
    private func adopt(_ synced: NotoSettings.Synced) {
        guard let cloud = cloudValue(of: synced),
            !Self.same(cloud, settings.storedValue(of: synced))
        else { return }
        settings.restore(synced, from: cloud)
        Logger.sync.info("adopted \(synced.rawValue, privacy: .public) from iCloud")
        onRemoteChange(synced)
    }

    /// Writes the local preference to iCloud unless iCloud already holds it. True when it wrote.
    @discardableResult
    private func publish(_ synced: NotoSettings.Synced) -> Bool {
        let local = settings.storedValue(of: synced)
        if let cloud = cloudValue(of: synced), Self.same(cloud, local) { return false }
        store.set(local, forKey: Self.cloudKey(for: synced))
        Logger.sync.info("published \(synced.rawValue, privacy: .public) to iCloud")
        return true
    }

    /// Only the preference's own keys: a value from another build cannot write anything else.
    private func cloudValue(of synced: NotoSettings.Synced) -> [String: Any]? {
        guard let value = store.object(forKey: Self.cloudKey(for: synced)) as? [String: Any] else {
            return nil
        }
        return value.filter { synced.keys.contains($0.key) }
    }

    private static func cloudKey(for synced: NotoSettings.Synced) -> String {
        "settings.\(synced.rawValue)"
    }

    private static func same(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        NSDictionary(dictionary: lhs).isEqual(to: rhs)
    }
}
