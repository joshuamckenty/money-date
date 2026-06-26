import AppKit
import Carbon.HIToolbox

/// A user-configurable hotkey definition. `modifiers` is a Carbon modifier mask.
struct HotKeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    /// Rare default: ⌃⌥⌘C (Control-Option-Command-C), unlikely to collide with app shortcuts.
    static let `default` = HotKeyConfig(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⌃⌥⌘C")

    /// Convert AppKit modifier flags into a Carbon modifier mask.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    /// Human-readable shortcut string, e.g. "⌃⌥⇧⌘C".
    static func displayString(modifiers flags: NSEvent.ModifierFlags, key: String) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result + key.uppercased()
    }
}

/// A system-wide hotkey using Carbon's RegisterEventHotKey (works without
/// Accessibility permissions, even when our app never has focus).
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    /// Default shortcut: ⌘⇧C.
    init(keyCode: UInt32 = UInt32(kVK_ANSI_C),
         modifiers: UInt32 = UInt32(cmdKey | shiftKey),
         callback: @escaping () -> Void) {
        self.callback = callback

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let this = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            this.callback()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D4F4E59), id: 1) // 'MONY'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
