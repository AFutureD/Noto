import Carbon.HIToolbox

enum ASCIIKeyboardLayout {
    /// The key's base character, which is what a shortcut glyph shows.
    @MainActor static func character(for keyCode: Int) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
                .takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(
                source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        // The bytes belong to `source`, which stays retained until the translation returns.
        return withExtendedLifetime(source) {
            character(
                for: keyCode,
                in: unsafeBitCast(
                    CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self))
        }
    }

    private static func character(
        for keyCode: Int, in keyLayout: UnsafePointer<UCKeyboardLayout>
    ) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let error = UCKeyTranslate(
            keyLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard error == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
