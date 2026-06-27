import AppKit
import SwiftUI
import Combine

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: Store!
    private var panel: NSPanel!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var effectWindow: NSPanel!
    private let effectView = EffectOverlayView(frame: .zero)
    private var effectFrame: CGRect = .zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = Store()

        makePanel()
        makeEffectWindow()
        makeStatusItem()

        // Drive Dopamine effects on the full-screen overlay, anchored at the table.
        store.$effectEvent
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] event in
                guard let self else { return }
                self.repositionEffectWindow()   // keep the surface around the panel
                self.effectView.fire(name: event.name,
                                     anchor: self.overlayAnchor(for: event),
                                     targetSize: CGSize(width: 144, height: 60))   // points
            }
            .store(in: &cancellables)

        // Watch the clipboard: a copied number adds a column, a copied date adds a row.
        Clipboard.shared.onChange = { [weak store] text in
            store?.handlePaste(text)
        }
        Clipboard.shared.start()

        // Register the configurable copy hotkey, and re-register whenever it changes.
        // (.sink fires immediately with the current value, installing it on launch.)
        store.$hotKeyConfig
            .removeDuplicates()
            .sink { [weak self] config in self?.installHotKey(config) }
            .store(in: &cancellables)
    }

    /// Install (or replace) the global hotkey. Setting `hotKey = nil` first forces the old
    /// HotKey's deinit to UnregisterEventHotKey before the new one registers.
    private func installHotKey(_ config: HotKeyConfig) {
        hotKey = nil
        hotKey = HotKey(keyCode: config.keyCode, modifiers: config.modifiers) { [weak self] in
            MainActor.assumeIsolated {
                _ = self?.store.copyLatest()
            }
        }
    }

    private func makePanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        panel.title = "money-date"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: ContentView(store: store))
        panel.delegate = self
        panel.center()
        panel.setFrameAutosaveName("MoneyDatePanel")
        panel.orderFrontRegardless()  // show without stealing focus

        self.panel = panel
    }

    /// A transparent, click-through overlay window covering the whole desktop so the
    /// Metal effects can spill across the screen over other apps' windows.
    private func makeEffectWindow() {
        effectFrame = screenUnionFrame()
        let window = NSPanel(
            contentRect: effectFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true            // never intercept clicks
        window.level = .screenSaver                 // above other apps' windows
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = effectView
        window.orderFrontRegardless()               // never key/main
        effectWindow = window
    }

    /// The union of all screens (fallback: the main screen).
    private func screenUnionFrame() -> CGRect {
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        return union.isNull ? (NSScreen.main?.frame ?? .zero) : union
    }

    private func repositionEffectWindow() {
        effectFrame = screenUnionFrame()
        effectWindow.setFrame(effectFrame, display: false)
    }

    /// Where the effect should originate, in the overlay view's flipped (top-left)
    /// local coords: the event's screen anchor (the clicked cell) if present,
    /// otherwise the table panel's center.
    private func overlayAnchor(for event: Store.EffectEvent) -> CGPoint? {
        let screenPoint = event.anchorScreen ?? panel?.frame.center
        guard let p = screenPoint else { return nil }
        return CGPoint(x: p.x - effectFrame.minX,        // global bottom-left → overlay
                       y: effectFrame.maxY - p.y)         // → top-left origin
    }

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "$⇄"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show money-date", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func showPanel() {
        panel.orderFrontRegardless()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // Closing the red button just hides the panel; the status item brings it back.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel.orderOut(nil)
        return false
    }
}
