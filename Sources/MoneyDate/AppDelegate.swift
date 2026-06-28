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
    /// Owns Dopamine's `DesktopEffectOverlay` (tracking panel + radial fade + tick) and the
    /// per-effect host cache. Created once the panel exists.
    private var effects: EffectCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = Store()

        makePanel()
        effects = EffectCoordinator(tracking: panel, margin: 200)
        makeStatusItem()

        // Drive Dopamine effects on the desktop overlay, anchored at the table.
        store.$effectEvent
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] event in
                guard let self else { return }
                // Pass the raw global screen point; the overlay maps it to surface-local.
                let anchor = event.anchorScreen ?? self.panel.frame.center
                self.effects.fire(name: event.name, anchorScreen: anchor)
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

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "$⇄"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show money-date", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(.separator())
        let fsItem = NSMenuItem(title: "Full-screen effects", action: #selector(toggleFullScreenEffects), keyEquivalent: "")
        fsItem.state = MainActor.assumeIsolated { effects.overlay.coversWholeScreen } ? .on : .off
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
        MainActor.assumeIsolated {
            effects.overlay.coversWholeScreen.toggle()
            sender.state = effects.overlay.coversWholeScreen ? .on : .off
        }
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
