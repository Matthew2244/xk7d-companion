import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// The self-test runs with no Dock icon and no window, so it can be run over ssh on a Mac someone is using.
app.setActivationPolicy(ProcessInfo.processInfo.environment["XK7D_SELFTEST"] != nil ? .prohibited : .regular)
app.run()
