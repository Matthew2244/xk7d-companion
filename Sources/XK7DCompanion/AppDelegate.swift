import AppKit
import UniformTypeIdentifiers
import XK7DCore

/// The app's name lives here and nowhere else in the Swift code (the build script reads it too).
enum AppIdentity {
    static let name = "XK-7D Companion"
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let model = AppModel()
    let updater = AppUpdater()
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
        if let log = ProcessInfo.processInfo.environment["XK7D_UPDATE_TEST"] {
            rehearseUpdate(logPath: log)
            return
        }
        if let log = ProcessInfo.processInfo.environment["XK7D_SELFTEST"] {
            // Silent self-test: no speech, no window, no Dock icon; results go to the log file.
            let ready = updater.start()
            model.runSelfTest(logPath: log, updaterLine: ready ? "UPDATER ready \(updater.feedURL ?? "no feed")" : "UPDATER not started")
            return
        }
        if ProcessInfo.processInfo.environment["XK7D_SILENT"] != nil {
            model.announcer.silentSink = { _ in }
        }
        mainWindow.showWindow(nil)
        mainWindow.window?.center()
        model.connectAtLaunch()
        startUpdates()
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
        help.addItem(item("Check for Updates…", #selector(checkForUpdates(_:)), "u", target: self))
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

    // MARK: Updates

    /// What the background look found, waiting for a good moment to be said.
    private var updateNotice: (version: String, text: String)?
    private var noticeTimer: Timer?

    private func startUpdates() {
        guard updater.start() else { return }
        updater.onFound = { [weak self] version in
            guard let self else { return }
            if UserDefaults.standard.string(forKey: "toldUpdateVersion") == version { return }
            self.updateNotice = (version, "\(AppIdentity.name) \(version) is out. Help, Check for Updates shows what's new and installs it.")
        }
        updater.onSeenByPerson = { version in
            UserDefaults.standard.set(version, forKey: "toldUpdateVersion")
        }
        updater.startLooking()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.deliverUpdateNotice() }
        RunLoop.main.add(t, forMode: .common)
        noticeTimer = t
    }

    /// Say the update news once, only when this app is in front, nothing modal is open and
    /// announcements aren't muted: never over a question someone is answering, never into
    /// another app, never at a gig with announcements off.
    private func deliverUpdateNotice() {
        guard let notice = updateNotice, NSApp.isActive, NSApp.modalWindow == nil,
              !NSApp.windows.contains(where: { $0.attachedSheet != nil }),
              !model.announcer.muted else { return }
        updateNotice = nil
        UserDefaults.standard.set(notice.version, forKey: "toldUpdateVersion")
        model.announcer.announce(notice.text, polite: true)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        if !updater.checkWithWindow() {
            model.announcer.announce("Updates aren't available in this copy of the app. Download the latest from github.com/Matthew2244/xk7d-companion.", force: true)
        }
    }

    /// The update rehearsal (XK7D_UPDATE_TEST=log): no window, no speech. Checks the feed in the
    /// app's Info.plist, downloads and verifies whatever is newer, then quits so Sparkle installs
    /// it. Only a test build (scripts/build-app.sh with XK7D_TEST_FEED) lets Sparkle do this.
    private func rehearseUpdate(logPath: String) {
        model.announcer.silentSink = { _ in }
        var lines: [String] = []
        let write = { try? (lines.joined(separator: "\n") + "\n").write(toFile: logPath, atomically: true, encoding: .utf8) }
        updater.log = { line in
            lines.append(line); write()
            if line.contains("will install") || line.contains("no update") || line.contains("failed") || line.contains("aborted")
                || line.contains("not a test build") || line.contains("cycle ended") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { lines.append("REHEARSAL QUIT"); write(); NSApp.terminate(nil) }
            }
        }
        guard updater.start() else { lines.append("UPDATER not started"); write(); NSApp.terminate(nil); return }
        updater.rehearseSilentInstall()
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { lines.append("REHEARSAL TIMED OUT"); write(); NSApp.terminate(nil) }
    }
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
        There are two ways to use this app. Play the organ and the app says each change you make. Or change settings here, and they go straight to the organ. You can mix the two.

        Setting up, once: connect the organ by USB. The app looks for it by name; if it doesn't find it, choose it in the Organ popup. Then choose Organ, Set Up Organ for This App (Command Shift U) and Send to Organ. Without this, the organ doesn't report every change. Record the System settings on the organ to keep it (manual page 142). Loading one of the organ's MIDI templates undoes it, so run Set Up Organ again after that.

        Playing: changes are spoken name first, for example "Upper 8 foot: 6". A drawbar or knob is spoken once, when you stop moving it. When many settings change at once, such as calling up a patch, you hear the first and how many others changed. Command Shift L repeats the last announcement, and Command Shift M mutes. Recent announcements, at the bottom of this window, lists everything said.

        Command W hides this window and the app keeps listening. If VoiceOver goes quiet while the app is in the background, turn on the Mac voice option in Settings. Command 1 or the Dock icon brings the window back. The app never sends anything to the organ unless you change something here.

        Changing settings here: Command F searches, Command L goes to the list. Each row reads name and value; "not heard yet" means the organ hasn't reported it. Tab reaches the editor. A slider or typed value is sent at once. A choice is sent only when you pick it from the menu, and the app says what it sent.

        If the organ seems silent: check Set Up Organ has been sent since the last MIDI template, that the organ is chosen in the Organ popup, that the app isn't muted, and try with External Zones off.

        Other keys: Command R read from organ, Command S save the last organ snapshot, Command 2 the simulator, Command comma Settings, Command U check for updates, Command Q quit.
        """
        alert.runModal()
    }
}
