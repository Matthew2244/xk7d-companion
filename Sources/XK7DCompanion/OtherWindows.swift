import AppKit
import XK7DCore

/// The simulator's own window: clearly labelled, with panel actions and a log of what it received.
final class SimulatorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    let model: AppModel
    private let modePopup = NSPopUpButton()
    private let stateLabel = makeLabel("", wraps: true)
    private let logTable = NSTableView()
    private var log: [String] = []
    private var actionButtons: [NSButton] = []

    init(model: AppModel) {
        self.model = model
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "XK-7D Simulator (not a real organ)"
        w.setFrameAutosaveName("SimulatorWindow")
        super.init(window: w)
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .simulatorChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .connectionChanged, object: nil)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        let intro = makeLabel("This is a pretend XK-7D built into the app, for trying things out without the organ. Its buttons act as if someone touched the organ's panel. Changes made in the main window are stored here, just as the organ would store them.", wraps: true)
        modePopup.addItems(withTitles: ["Off", "NRPN (what the organ's MIDI templates set)", "SysEx (every setting, including Leslie cabinet and custom)"])
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        modePopup.setAccessibilityLabel("Simulator sends changes as")
        modePopup.toolTip = "How the simulated organ reports panel changes. This is the organ's Individual Parameters setting."
        modePopup.setAccessibilityHelp(modePopup.toolTip)
        let modeRow = NSStackView(views: [makeLabel("Send changes as:"), modePopup])
        modeRow.spacing = 8

        var buttons: [NSView] = []
        for (i, action) in SimulatorAction.allCases.enumerated() {
            let b = makeButton(action.title, help: action.help, target: self, action: #selector(performPanelAction(_:)))
            b.tag = i
            buttons.append(b)
            actionButtons.append(b)
        }
        let buttonGrid = NSStackView(views: buttons)
        buttonGrid.orientation = .vertical
        buttonGrid.alignment = .leading
        buttonGrid.spacing = 6

        stateLabel.setAccessibilityLabel("Simulator state")
        let logLabel = makeLabel("What the simulator received from the app, newest first", bold: true)
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("m"))
        logTable.addTableColumn(col)
        logTable.headerView = nil
        logTable.dataSource = self
        logTable.delegate = self
        logTable.setAccessibilityLabel("Simulator log")
        let scroll = NSScrollView()
        scroll.documentView = logTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let root = NSStackView(views: [intro, modeRow, buttonGrid, stateLabel, logLabel, scroll])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
            intro.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28),
            stateLabel.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28),
        ])
        window?.autorecalculatesKeyViewLoop = true
    }

    @objc func refresh() {
        let active = model.choice == .simulator
        if let organ = model.simulator {
            modePopup.selectItem(at: Int(organ.individualMode.rawValue))
            if active {
                stateLabel.stringValue = "The app is connected to this simulator. Device ID \(organ.deviceID). It has received \(organ.received.count) messages."
            } else {
                stateLabel.stringValue = "The app is not connected to the simulator. Choose Built-in simulator from the Organ popup in the main window to use it."
            }
            log = organ.received.suffix(200).reversed().map { $0.map { String(format: "%02X", $0) }.joined(separator: " ") }
        } else {
            stateLabel.stringValue = "The simulator is not running. Choose Built-in simulator from the Organ popup in the main window to start it."
            log = []
        }
        modePopup.isEnabled = active
        actionButtons.forEach { $0.isEnabled = active }
        logTable.reloadData()
    }

    @objc private func modeChanged() {
        guard let organ = model.simulator, let m = XK7SysEx.IndividualMode(rawValue: UInt8(modePopup.indexOfSelectedItem)) else { return }
        organ.individualMode = m
    }

    @objc private func performPanelAction(_ sender: NSButton) {
        model.simulatorAction(SimulatorAction.allCases[sender.tag])
        refresh()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { log.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let t = NSTextField(labelWithString: log[row])
        t.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        t.lineBreakMode = .byTruncatingTail
        return t
    }
}

/// Settings: how to speak, how long to wait, and MIDI addressing.
final class SettingsWindowController: NSWindowController {
    let model: AppModel
    private let methodPopup = NSPopUpButton()
    private let backgroundCheckbox = NSButton(checkboxWithTitle: "Use the Mac's voice while this app is in the background", target: nil, action: nil)
    private let voicePopup = NSPopUpButton()
    private let speedPopup = NSPopUpButton()
    private let volumePopup = NSPopUpButton()
    private let sampleButton = NSButton(title: "Say a Sample", target: nil, action: nil)
    private let drawbarCheckbox = NSButton(checkboxWithTitle: "Speak drawbar changes", target: nil, action: nil)
    private let namesCheckbox = NSButton(checkboxWithTitle: "Ask the organ for User patch names", target: nil, action: nil)
    private var voices: [(id: String, title: String)] = []
    private static let volumes = [100, 75, 50, 25]
    private let settleField = NSTextField(string: "")
    private let settleStepper = NSStepper()
    private let deviceField = NSTextField(string: "")
    private let deviceStepper = NSStepper()
    private var channelPopups: [NSPopUpButton] = []

    init(model: AppModel) {
        self.model = model
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 580),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "\(AppIdentity.name) Settings"
        super.init(window: w)
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(deviceIDMayHaveChanged), name: .connectionChanged, object: nil)
    }

    /// Show a Device ID learned from the organ while this window is open (unless it's being typed in).
    @objc private func deviceIDMayHaveChanged() {
        drawbarCheckbox.state = model.session.speakDrawbars ? .on : .off
        guard deviceField.currentEditor() == nil else { return }
        let id = Int(model.session.addressing.deviceID)
        deviceField.integerValue = id
        deviceStepper.integerValue = id
    }

    required init?(coder: NSCoder) { fatalError() }

    private func help(_ v: NSView & NSAccessibilityProtocol, _ label: String, _ text: String) {
        v.setAccessibilityLabel(label)
        v.toolTip = text
        v.setAccessibilityHelp(text)
    }

    private func build() {
        guard let content = window?.contentView else { return }
        methodPopup.addItems(withTitles: Announcer.Method.allCases.map(\.title))
        methodPopup.selectItem(at: Announcer.Method.allCases.firstIndex(of: model.announcer.method) ?? 0)
        methodPopup.target = self; methodPopup.action = #selector(changed)
        help(methodPopup, "Speak with", "How announcements are spoken. Automatic uses VoiceOver when it is running.")

        backgroundCheckbox.state = model.announcer.macVoiceInBackground ? .on : .off
        backgroundCheckbox.target = self; backgroundCheckbox.action = #selector(changed)
        help(backgroundCheckbox, "Use the Mac's voice while this app is in the background",
             "Try this if VoiceOver does not speak organ changes while you are in another app.")

        voices = Announcer.voiceChoices()
        voicePopup.addItems(withTitles: voices.map(\.title))
        voicePopup.target = self; voicePopup.action = #selector(changed)
        help(voicePopup, "Voice", "The Mac's voice for announcements when VoiceOver isn't speaking them. System voice follows System Settings, Accessibility, Spoken Content.")
        speedPopup.addItems(withTitles: Announcer.Speed.allCases.map(\.title))
        speedPopup.target = self; speedPopup.action = #selector(changed)
        help(speedPopup, "Speed", "How fast the Mac's voice speaks. System speed follows Spoken Content when the voice is System voice.")
        volumePopup.addItems(withTitles: Self.volumes.map { "\($0) percent" })
        volumePopup.target = self; volumePopup.action = #selector(changed)
        help(volumePopup, "Loudness", "How loud the Mac's voice is, compared with other sound. VoiceOver keeps its own volume.")
        sampleButton.target = self; sampleButton.action = #selector(saySample)
        help(sampleButton, "Say a Sample", "Says a patch change in the chosen voice, speed and loudness.")
        drawbarCheckbox.target = self; drawbarCheckbox.action = #selector(changed)
        help(drawbarCheckbox, "Speak drawbar changes", "Off keeps quiet about drawbars on all three parts, and still speaks everything else. Command Shift D switches it.")
        namesCheckbox.target = self; namesCheckbox.action = #selector(changed)
        help(namesCheckbox, "Ask the organ for User patch names",
             "When a User patch or Favorite is chosen and the organ doesn't send its name, the app asks for it with a memory dump request. Factory patches are named without asking. Turn off if the organ shows a dump message on every patch change.")

        let settle = Int(model.session.coalescer.settle * 1000)
        settleStepper.minValue = 100; settleStepper.maxValue = 2000; settleStepper.increment = 50
        settleStepper.integerValue = settle
        settleStepper.target = self; settleStepper.action = #selector(stepperChanged)
        settleField.integerValue = settle
        settleField.target = self; settleField.action = #selector(changed)
        settleField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        help(settleStepper, "Wait before speaking, milliseconds", "How long a knob must stop moving before its value is spoken. Shorter is quicker, longer is quieter.")
        help(settleField, "Wait before speaking, milliseconds", settleStepper.toolTip ?? "")

        let a = model.session.addressing
        deviceStepper.minValue = 0; deviceStepper.maxValue = 127; deviceStepper.integerValue = Int(a.deviceID)
        deviceStepper.target = self; deviceStepper.action = #selector(stepperChanged)
        deviceField.integerValue = Int(a.deviceID)
        deviceField.target = self; deviceField.action = #selector(changed)
        deviceField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        help(deviceStepper, "Organ device ID", "The organ's Device ID, MENU, SYSTEM, MIDI, SYS EX page. The app learns it when the organ answers.")
        help(deviceField, "Organ device ID", deviceStepper.toolTip ?? "")

        var rows: [NSView] = [
            makeLabel("Announcements", bold: true),
            hrow(makeLabel("Speak with:"), methodPopup),
            backgroundCheckbox,
            hrow(makeLabel("Voice:"), voicePopup),
            hrow(makeLabel("Speed:"), speedPopup, makeLabel("Loudness:"), volumePopup, sampleButton),
            hrow(makeLabel("Wait before speaking, milliseconds:"), settleField, settleStepper),
            drawbarCheckbox,
            namesCheckbox,
            makeLabel("MIDI", bold: true),
            hrow(makeLabel("Organ device ID:"), deviceField, deviceStepper),
        ]
        for (i, part) in ["Upper", "Lower", "Pedal"].enumerated() {
            let p = NSPopUpButton()
            p.addItems(withTitles: (1...16).map { "Channel \($0)" })
            p.selectItem(at: [a.upperChannel, a.lowerChannel, a.pedalChannel][i])
            p.target = self; p.action = #selector(changed)
            help(p, "\(part) channel", "The organ's \(part) MIDI channel. The Basic template uses Upper 1, Lower 2, Pedal 3. NRPN and drawbars travel on the Upper channel.")
            channelPopups.append(p)
            rows.append(hrow(makeLabel("\(part) channel:"), p))
        }
        rows.append(makeLabel("Changes here take effect at once.", wraps: true))
        let root = NSStackView(views: rows)
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
        ])
        window?.autorecalculatesKeyViewLoop = true
    }

    /// The window is built once, so read the current values each time it opens. Otherwise a Device
    /// ID learned from the organ since then would be shown stale, and written back over the learned
    /// one by the next change made here.
    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
    }

    func reload() {
        methodPopup.selectItem(at: Announcer.Method.allCases.firstIndex(of: model.announcer.method) ?? 0)
        backgroundCheckbox.state = model.announcer.macVoiceInBackground ? .on : .off
        voicePopup.selectItem(at: voices.firstIndex { $0.id == model.announcer.voiceIdentifier } ?? 0)
        speedPopup.selectItem(at: Announcer.Speed.allCases.firstIndex(of: model.announcer.speed) ?? 0)
        volumePopup.selectItem(at: Self.volumes.firstIndex(of: model.announcer.volumePercent) ?? 0)
        namesCheckbox.state = model.session.askOrganForPatchNames ? .on : .off
        drawbarCheckbox.state = model.session.speakDrawbars ? .on : .off
        let settle = Int((model.session.coalescer.settle * 1000).rounded())
        settleStepper.integerValue = settle
        settleField.integerValue = settle
        let a = model.session.addressing
        deviceStepper.integerValue = Int(a.deviceID)
        deviceField.integerValue = Int(a.deviceID)
        for (popup, ch) in zip(channelPopups, [a.upperChannel, a.lowerChannel, a.pedalChannel]) { popup.selectItem(at: ch) }
    }

    private func hrow(_ v: NSView...) -> NSStackView {
        let r = NSStackView(views: v)
        r.spacing = 8
        return r
    }

    @objc private func saySample() {
        changed()
        model.announcer.sample()
    }

    @objc private func stepperChanged() {
        settleField.integerValue = settleStepper.integerValue
        deviceField.integerValue = deviceStepper.integerValue
        changed()
    }

    @objc private func changed() {
        model.announcer.method = Announcer.Method.allCases[max(methodPopup.indexOfSelectedItem, 0)]
        model.announcer.macVoiceInBackground = backgroundCheckbox.state == .on
        if voices.indices.contains(voicePopup.indexOfSelectedItem) { model.announcer.voiceIdentifier = voices[voicePopup.indexOfSelectedItem].id }
        model.announcer.speed = Announcer.Speed.allCases[max(speedPopup.indexOfSelectedItem, 0)]
        model.announcer.volumePercent = Self.volumes[max(volumePopup.indexOfSelectedItem, 0)]
        if model.session.speakDrawbars != (drawbarCheckbox.state == .on) {
            model.session.speakDrawbars = drawbarCheckbox.state == .on
            UserDefaults.standard.set(model.session.speakDrawbars, forKey: "speakDrawbars")
        }
        model.session.askOrganForPatchNames = namesCheckbox.state == .on
        UserDefaults.standard.set(model.session.askOrganForPatchNames, forKey: "askOrganForPatchNames")
        let settle = min(max(settleField.integerValue, 100), 2000)
        settleStepper.integerValue = settle
        model.session.coalescer.settle = Double(settle) / 1000
        UserDefaults.standard.set(settle, forKey: "settleMilliseconds")
        let dev = min(max(deviceField.integerValue, 0), 127)
        deviceStepper.integerValue = dev
        model.session.addressing.deviceID = UInt8(dev)
        UserDefaults.standard.set(dev, forKey: "deviceID")
        let chans = channelPopups.map { max($0.indexOfSelectedItem, 0) }
        model.session.addressing.upperChannel = chans[0]
        model.session.addressing.lowerChannel = chans[1]
        model.session.addressing.pedalChannel = chans[2]
        for (k, v) in zip(["upperChannel", "lowerChannel", "pedalChannel"], chans) { UserDefaults.standard.set(v, forKey: k) }
        if let sim = model.simulator {
            sim.upperChannel = chans[0]; sim.lowerChannel = chans[1]; sim.pedalChannel = chans[2]
        }
    }
}
