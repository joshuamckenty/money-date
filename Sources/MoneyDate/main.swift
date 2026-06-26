import AppKit

// Entry point for the money-date menu-bar / floating-panel utility.
// We run as an "accessory" app: no Dock icon, and the window never steals focus.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
