import Foundation

extension Bundle {
    /// `CFBundleShortVersionString`: the version Settings shows, and the one a release is named for.
    var appVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
