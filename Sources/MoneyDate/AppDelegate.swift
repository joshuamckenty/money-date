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
    /// How far the effect drawing surface extends beyond the panel, each side.
    private let effectMargin: CGFloat = 400
    /// When true, the effect surface covers the whole desktop instead of panel+margin.
    private var fullScreenEffects = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = Store()

        makePanel()
        makeEffectWindow()
        makeStatusItem()

        // Keep the effect overlay tracking the panel — including across displays.
        for note in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
            NotificationCenter.default.addObserver(forName: note, object: panel, queue: .main) { [weak self] _ in
                self?.repositionEffectWindow()
            }
        }

        // Drive Dopamine effects on the full-screen overlay, anchored at the table.
        store.$effectEvent
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] event in
                guard let self else { return }
                self.repositionEffectWindow()   // keep the surface around the panel
                self.effectView.fire(name: event.name, anchor: self.overlayAnchor(for: event))
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
            contentRect: NSRect(x: 0, y: 0, width: 586, height: 727),
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

    /// A transparent, click-through overlay window hosting the Metal effects so they
    /// composite over other apps' windows. Kept to the panel + margin for speed,
    /// and repositioned to follow the panel before each fire.
    private func makeEffectWindow() {
        effectFrame = effectSurfaceFrame()
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

    /// The current effect surface: full desktop, or the panel grown by `effectMargin`.
    private func effectSurfaceFrame() -> CGRect {
        fullScreenEffects ? screenUnionFrame() : panelExpandedFrame()
    }

    /// The panel's frame grown by `effectMargin` on every side (falls back to a
    /// centered box if the panel isn't up yet).
    private func panelExpandedFrame() -> CGRect {
        let base = panel?.frame ?? CGRect(x: 0, y: 0, width: 460, height: 320)
        return base.insetBy(dx: -effectMargin, dy: -effectMargin)
    }

    /// The union of all screens (fallback: the main screen).
    private func screenUnionFrame() -> CGRect {
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        return union.isNull ? (NSScreen.main?.frame ?? .zero) : union
    }

    private func repositionEffectWindow() {
        effectFrame = effectSurfaceFrame()
        effectWindow.setFrame(effectFrame, display: true)   // relocates across screens
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
        let fsItem = NSMenuItem(title: "Full-screen effects", action: #selector(toggleFullScreenEffects), keyEquivalent: "")
        fsItem.state = fullScreenEffects ? .on : .off
        menu.addItem(fsItem)

        let dateMenu = NSMenu()
        let currentFormat = MainActor.assumeIsolated { store.dateFormat }
        for format in Store.dateFormatOptions {
            let mi = NSMenuItem(title: Formatters.displayDate(Store.dateFormatSample, format: format),
                                action: #selector(selectDateFormat(_:)), keyEquivalent: "")
            mi.representedObject = format
            mi.state = (format == currentFormat) ? .on : .off
            dateMenu.addItem(mi)
        }
        let dateItem = NSMenuItem(title: "Date format", action: nil, keyEquivalent: "")
        dateItem.submenu = dateMenu
        menu.addItem(dateItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func showPanel() {
        panel.orderFrontRegardless()
    }

    @objc private func toggleFullScreenEffects(_ sender: NSMenuItem) {
        fullScreenEffects.toggle()
        sender.state = fullScreenEffects ? .on : .off
        repositionEffectWindow()
    }

    @objc private func selectDateFormat(_ sender: NSMenuItem) {
        guard let format = sender.representedObject as? String else { return }
        MainActor.assumeIsolated { store.setDateFormat(format) }
        sender.menu?.items.forEach { $0.state = ($0.representedObject as? String == format) ? .on : .off }
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
