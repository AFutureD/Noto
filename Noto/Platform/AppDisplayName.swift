import Foundation

extension Bundle {
    /// The build's display name: "Noto", or "Noto Dev" for a Debug build.
    var appDisplayName: String {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            guard let text = object(forInfoDictionaryKey: key) as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "Noto"
    }
}
