import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: Store!
    private var panel: NSPanel!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = Store()

        makePanel()
        makeStatusItem()

        // Watch the clipboard: a copied number adds a column, a copied date adds a row.
        Clipboard.shared.onChange = { [weak store] text in
            store?.handlePaste(text)
        }
        Clipboard.shared.start()

        // ⌘⇧C copies the latest value for the topmost date — without adding a column.
        hotKey = HotKey { [weak self] in
            MainActor.assumeIsolated {
                guard let value = self?.store.latestCellCADPlain() else { return }
                Clipboard.shared.copy(value)
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
