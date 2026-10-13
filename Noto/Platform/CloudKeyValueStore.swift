import Foundation

/// The surface of `NSUbiquitousKeyValueStore` that Noto uses, so a harness can stand in for iCloud.
protocol CloudKeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStore {}
