import AppKit
import Carbon.HIToolbox

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
