import SwiftUI
import Carbon.HIToolbox

/// A click-to-record shortcut field. Click it, then press a key combination
/// (at least one modifier required). Escape cancels.
struct HotKeyRecorder: NSViewRepresentable {
    var display: String
    var onCapture: (HotKeyConfig) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(frame: .zero)
        button.onCapture = onCapture
        button.idleTitle = display
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onCapture = onCapture
        button.idleTitle = display
    }
}

final class RecorderButton: NSButton {
    var onCapture: ((HotKeyConfig) -> Void)?

    /// Title shown when not actively recording.
    var idleTitle: String = "" {
        didSet { if !recording { title = idleTitle } }
    }

    private var recording = false {
        didSet { title = recording ? "Type shortcut…" : idleTitle }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 11)
        target = self
        action = #selector(beginRecording)
    }

    @objc private func beginRecording() {
        recording = true
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    // Allow the non-activating panel to become key so we can receive keyDown.
    override var needsPanelToBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            window?.makeFirstResponder(nil)
            return
        }
        let carbonMods = HotKeyConfig.carbonModifiers(from: event.modifierFlags)
        // Require at least one modifier so the shortcut is global-safe.
        guard carbonMods != 0 else {
            NSSound.beep()
            return
        }
        let key = event.charactersIgnoringModifiers ?? ""
        let display = HotKeyConfig.displayString(modifiers: event.modifierFlags, key: key)
        let config = HotKeyConfig(keyCode: UInt32(event.keyCode), modifiers: carbonMods, display: display)
        recording = false
        idleTitle = display
        onCapture?(config)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }
}
