import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// The self-test and the update rehearsal run with no Dock icon and no window, so it can be run over ssh on a Mac someone is using.
let env = ProcessInfo.processInfo.environment
app.setActivationPolicy(env["XK7D_SELFTEST"] != nil || env["XK7D_UPDATE_TEST"] != nil ? .prohibited : .regular)
app.run()
