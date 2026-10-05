import CoreText
import Foundation

/// The installed font families, sorted into the lists the Settings font menus show.
enum FontCatalog {
    struct Families: Sendable {
        var all: [String] = []
        /// Families that draw Han characters themselves.
        var cjk: [String] = []
        var fixedPitch: [String] = []
    }

    @MainActor private static var loaded: Families?

    /// Read off the main thread: one font is made per family, which costs hundreds of milliseconds.
    @MainActor
    static func families() async -> Families {
        if let loaded { return loaded }
        let families = await Task.detached(priority: .userInitiated) { read() }.value
        loaded = families
        return families
    }

    private nonisolated static func read() -> Families {
        var families = Families()
        let names = (CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let han = UniChar(0x4F60)
        for name in names {
            let attributes = [kCTFontFamilyNameAttribute: name] as CFDictionary
            let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes), 13, nil)
            guard CTFontCopyFamilyName(font) as String == name else { continue }
            families.all.append(name)
            if CTFontGetSymbolicTraits(font).contains(.traitMonoSpace) { families.fixedPitch.append(name) }
            if CFCharacterSetIsCharacterMember(CTFontCopyCharacterSet(font), han) { families.cjk.append(name) }
        }
        return families
    }
}
