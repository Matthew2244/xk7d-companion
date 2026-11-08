import AppKit
import UniformTypeIdentifiers
import XK7DCore

/// The app's name lives here and nowhere else in the Swift code (the build script reads it too).
enum AppIdentity {
    static let name = "XK-7D Companion"
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let model = AppModel()
    var mainWindow: MainWindowController!
    lazy var simulatorWindow = SimulatorWindowController(model: model)
    lazy var settingsWindow = SettingsWindowController(model: model)
    private var muteItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus()
        if let problem = ParameterDatabase.loadError ?? (model.database.parameters.isEmpty ? "the table is empty" : nil) {
            // A broken build. Say so plainly instead of crashing.
            if let log = ProcessInfo.processInfo.environment["XK7D_SELFTEST"] {
                try? "FAILED settings table: \(problem)\n".write(toFile: log, atomically: true, encoding: .utf8)
                exit(2)
            }
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "\(AppIdentity.name) can't start"
            alert.informativeText = "The app's list of organ settings couldn't be read, so it can't work. Please download it again from github.com/Matthew2244/xk7d-companion. Details: \(problem)"
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        mainWindow = MainWindowController(model: model)
        if let log = ProcessInfo.processInfo.environment["XK7D_SELFTEST"] {
            // Silent self-test: no speech, no focus stealing; results go to the log file.
            mainWindow.showWindow(nil)
            model.runSelfTest(logPath: log)
            return
        }
        if ProcessInfo.processInfo.environment["XK7D_SILENT"] != nil {
            model.announcer.silentSink = { _ in }
        }
        mainWindow.showWindow(nil)
        mainWindow.window?.center()
        model.connectAtLaunch()
        if let sim = ProcessInfo.processInfo.environment["XK7D_SHOW"] {
            if sim.contains("simulator") { simulatorWindow.showWindow(nil) }
            if sim.contains("settings") { settingsWindow.showWindow(nil) }
            if let id = sim.split(separator: ":").dropFirst().first { mainWindow.reveal(parameterID: String(id)) }
        }
    }

    /// Closing the main window hides it; the app keeps listening. Command Q quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon, or opening the app again, brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !(mainWindow.window?.isVisible ?? false) { mainWindow.showWindow(nil) }
        return true
    }

    // MARK: Menus (every command reachable from the keyboard)

    private func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command,
                      target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = target
        return i
    }

    private func buildMenus() {
        let main = NSMenu()
        let name = AppIdentity.name

        let appMenu = NSMenu(title: name)
        appMenu.addItem(item("About \(name)", #selector(showAbout(_:)), target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(showSettings(_:)), ",", target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        appMenu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"))
        addSubmenu(appMenu, to: main)

        let file = NSMenu(title: "File")
        file.addItem(item("Save Organ Snapshot…", #selector(saveSnapshot(_:)), "s", target: self))
        file.addItem(.separator())
        file.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w"))
        addSubmenu(file, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        edit.addItem(.separator())
        edit.addItem(item("Find Setting", #selector(findSetting(_:)), "f", target: self))
        edit.addItem(item("Go to Settings List", #selector(goToList(_:)), "l", target: self))
        addSubmenu(edit, to: main)

        let organ = NSMenu(title: "Organ")
        organ.addItem(item("Read from Organ", #selector(readFromOrgan(_:)), "r", target: self))
        organ.addItem(item("Set Up Organ for This App…", #selector(setUpOrgan(_:)), "u", [.command, .shift], target: self))
        organ.addItem(.separator())
        organ.addItem(item("Use the Built-in Simulator", #selector(useSimulator(_:)), "", target: self))
        organ.addItem(item("Disconnect", #selector(disconnect(_:)), "", target: self))
        addSubmenu(organ, to: main)

        let speech = NSMenu(title: "Announcements")
        muteItem = item("Mute Announcements", #selector(toggleMute(_:)), "m", [.command, .shift], target: self)
        speech.addItem(muteItem)
        speech.addItem(item("Repeat Last Announcement", #selector(repeatLast(_:)), "l", [.command, .shift], target: self))
        addSubmenu(speech, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(item("Main Window", #selector(showMain(_:)), "1", target: self))
        window.addItem(item("Simulator", #selector(showSimulator(_:)), "2", target: self))
        window.addItem(.separator())
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        addSubmenu(window, to: main)
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(item("\(name) Help", #selector(showHelp(_:)), "?", target: self))
        addSubmenu(help, to: main)
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    private func addSubmenu(_ menu: NSMenu, to main: NSMenu) {
        let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        main.addItem(holder)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleMute(_:)):
            menuItem.title = model.announcer.muted ? "Unmute Announcements" : "Mute Announcements"
            return true
        case #selector(saveSnapshot(_:)): return model.snapshot != nil
        case #selector(disconnect(_:)): return model.choice != .none
        default: return true
        }
    }

    // MARK: Commands

    @objc func readFromOrgan(_ sender: Any?) {
        model.announcer.announce("Reading from the organ", force: true)
        model.readFromOrgan { [weak self] summary in
            guard let self else { return }
            let short = summary.components(separatedBy: ". ").prefix(2).joined(separator: ". ")
            self.model.announcer.announce(short, force: true)
            let alert = NSAlert()
            alert.messageText = "Read from Organ"
            alert.informativeText = summary
            alert.addButton(withTitle: "OK")
            if let w = self.mainWindow.window, w.isVisible { alert.beginSheetModal(for: w) } else { alert.runModal() }
        }
    }

    @objc func setUpOrgan(_ sender: Any?) {
        guard model.isConnected else {
            model.announcer.announce(model.notConnectedMessage, force: true)
            return
        }
        showMain(nil)
        let steps = model.setupSteps()
        let alert = NSAlert()
        alert.messageText = "Set up the organ to report changes to this app"
        alert.informativeText = "Tick what to change, then choose Send to Organ. Nothing is sent until you do. These are System settings: to keep them after the organ is turned off, record the System settings on the organ (manual page 142)."
        let boxes = steps.map { s -> NSButton in
            let b = NSButton(checkboxWithTitle: s.title, target: nil, action: nil)
            b.state = s.onByDefault ? .on : .off
            b.setAccessibilityLabel(s.title)
            return b
        }
        let stack = NSStackView(views: boxes)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 520, height: CGFloat(boxes.count) * 44)
        for b in boxes { b.cell?.wraps = true; b.widthAnchor.constraint(equalToConstant: 520).isActive = true }
        alert.accessoryView = stack
        alert.addButton(withTitle: "Send to Organ")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = boxes.first
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            var sent = 0
            for (step, box) in zip(steps, boxes) where box.state == .on {
                self.model.send(step.setting, raw: step.raw)
                sent += 1
            }
            self.model.announcer.announce(sent == 0 ? "Nothing sent." : "Sent \(sent) setting\(sent == 1 ? "" : "s") to the organ.", force: true)
        }
        if let w = mainWindow.window { alert.beginSheetModal(for: w, completionHandler: handle) } else { handle(alert.runModal()) }
    }

    @objc func saveSnapshot(_ sender: Any?) {
        guard let snap = model.snapshot else { return }
        showMain(nil)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "syx") ?? .data]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmm"
        panel.nameFieldStringValue = "XK-7D snapshot \(f.string(from: snap.started)).syx"
        panel.message = "Saves the memory dump exactly as the organ sent it, as a standard .syx file."
        guard let w = mainWindow.window else { return }
        panel.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            do {
                try snap.syxData.write(to: url)
                self?.model.announcer.announce("Snapshot saved.", force: true)
            } catch {
                self?.model.announcer.announce("Could not save the snapshot: \(error.localizedDescription)", force: true)
            }
        }
    }

    @objc func useSimulator(_ sender: Any?) { model.choose(.simulator); simulatorWindow.showWindow(nil) }
    @objc func disconnect(_ sender: Any?) { model.choose(.none) }

    @objc func toggleMute(_ sender: Any?) {
        model.announcer.muted.toggle()
        // Say so even when muting: silence is not confirmation.
        model.announcer.announce(model.announcer.muted ? "Announcements muted" : "Announcements on", force: true)
        NotificationCenter.default.post(name: .connectionChanged, object: nil)
    }

    @objc func repeatLast(_ sender: Any?) { model.repeatLast() }
    @objc func findSetting(_ sender: Any?) { showMain(nil); mainWindow.focusSearch() }
    @objc func goToList(_ sender: Any?) { showMain(nil); mainWindow.focusList() }
    @objc func showMain(_ sender: Any?) { mainWindow.showWindow(nil) }
    @objc func showSimulator(_ sender: Any?) { simulatorWindow.showWindow(nil) }
    @objc func showSettings(_ sender: Any?) { settingsWindow.showWindow(nil) }

    @objc func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = AppIdentity.name
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
        alert.informativeText = "Version \(v). An accessible companion for the Hammond XK-7D: it speaks changes made on the organ and lets you see and change every setting the manual's MIDI tables list. Not made by or affiliated with Hammond. \(model.database.parameters.count) settings from the Owner's Manual V1.10."
        alert.runModal()
    }

    @objc func showHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "\(AppIdentity.name) Help"
        alert.informativeText = """
        Choose your organ in the Organ popup (it shows as XK-7 or similar over USB), or the built-in simulator.

        Changes you make on the organ are spoken, name first. A knob that is turning is spoken once it stops.

        Browse or search every setting in the list. Each row shows its value; "not heard yet" means the organ has not reported it. Press Tab to reach the editor; changes are sent at once.

        Keys: Command F search, Command L the settings list, Command R read from organ, Command Shift U set up the organ, Command Shift M mute, Command Shift L repeat the last announcement, Command S save the last organ snapshot, Command 1 this window, Command 2 the simulator, Command comma settings.

        To hear every setting, use Organ, Set Up Organ for This App, which sets the organ to send changes as SysEx. Loading one of the organ's MIDI templates puts that back to NRPN, so run Set Up Organ again afterwards.

        If the organ is unplugged or turned off, the app says so, and connects again by itself when the organ comes back.

        Command W hides this window. The app keeps listening and speaking organ changes. Command 1 or the Dock icon brings it back. Command Q quits.
        """
        alert.runModal()
    }
}
