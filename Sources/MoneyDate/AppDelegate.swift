import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: Store!
    private var panel: NSPanel!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = Store()

        makePanel()
        makeStatusItem()

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
