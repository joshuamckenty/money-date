import AppKit

/// Watches the system pasteboard and writes to it. A single owner of `changeCount`
/// so that our *own* writes (cell copies, hotkey copies) never re-trigger `onChange`.
@MainActor
final class Clipboard {
    static let shared = Clipboard()

    /// Called with sanitized pasteboard text whenever the user copies something new.
    var onChange: ((String) -> Void)?

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    /// Reject absurdly large clipboard payloads before any parsing happens.
    private let maxLength = 256

    private init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        guard let raw = pasteboard.string(forType: .string) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return }
        onChange?(trimmed)
    }

    /// Write text to the clipboard *without* tripping our own monitor.
    func copy(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }
}
