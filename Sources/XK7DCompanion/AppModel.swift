import AppKit
import XK7DCore
import XK7DCoreMIDI

extension Notification.Name {
    static let organValuesChanged = Notification.Name("organValuesChanged")
    static let connectionChanged = Notification.Name("connectionChanged")
    static let historyChanged = Notification.Name("historyChanged")
    static let simulatorChanged = Notification.Name("simulatorChanged")
}

/// Owns the session, the MIDI connection, the simulator and the announcer; the windows observe it.
final class AppModel {
    let database = ParameterDatabase.shared
    let session: OrganSession
    let announcer = Announcer()
    private(set) var connection: CoreMIDIConnection?
    private(set) var choice: PortChoice = .none
    private(set) var statusText = "Not connected."
    private(set) var history: [String] = []

    private(set) var simulator: SimulatedOrgan?
    private var simulatorPorts: VirtualSimulatorPorts?
    private var loopback: LoopbackLink?
    private var timer: Timer?
    private var lastSnapshot: DumpSnapshot?
    private var readTimeout: DispatchWorkItem?

    init() {
        let settle = UserDefaults.standard.object(forKey: "settleMilliseconds") as? Int ?? 350
        session = OrganSession(coalescer: AnnouncementCoalescer(settle: Double(settle) / 1000, maxWait: 2.0))
        var a = OrganAddressing()
        let d = UserDefaults.standard
        if d.object(forKey: "deviceID") != nil { a.deviceID = UInt8(d.integer(forKey: "deviceID") & 0x7F) }
        if d.object(forKey: "upperChannel") != nil { a.upperChannel = d.integer(forKey: "upperChannel") }
        if d.object(forKey: "lowerChannel") != nil { a.lowerChannel = d.integer(forKey: "lowerChannel") }
        if d.object(forKey: "pedalChannel") != nil { a.pedalChannel = d.integer(forKey: "pedalChannel") }
        session.addressing = a

        announcer.onAnnounced = { [weak self] text in
            guard let self else { return }
            self.history.insert(text, at: 0)
            if self.history.count > 200 { self.history.removeLast() }
            NotificationCenter.default.post(name: .historyChanged, object: nil)
        }
        session.onAnnouncement = { [weak self] in self?.announcer.announce($0) }
        session.onEvent = { [weak self] event, _ in self?.eventArrived(event) }
        session.onChannelMismatch = { [weak self] channel in
            guard let self else { return }
            let mine = self.session.addressing.upperChannel + 1
            self.statusText = "The organ is sending its controls on channel \(channel + 1), but this app listens for them on channel \(mine). Set Upper channel to \(channel + 1) in Settings (Command comma)."
            self.announcer.announce("Channels don't match. The organ sends on channel \(channel + 1), the app listens on \(mine). Change Upper channel in Settings.", force: true)
            NotificationCenter.default.post(name: .connectionChanged, object: nil)
        }
        session.onDeviceIDLearned = { id in
            UserDefaults.standard.set(Int(id), forKey: "deviceID")
            NotificationCenter.default.post(name: .connectionChanged, object: nil)
        }

        do {
            connection = try CoreMIDIConnection()
            connection?.onReceive = { [weak self] in self?.session.receive($0) }
            connection?.onSetupChanged = { [weak self] in self?.portsChanged() }
        } catch {
            statusText = "MIDI is not available: \(error)"
        }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.session.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Ports

    /// Real MIDI devices by name (our own simulator ports are left out; the simulator has its own entry).
    func deviceNames() -> [String] {
        let names = CoreMIDIConnection.sources().filter { !$0.name.hasPrefix("XK-7D Simulator") }.map(\.name)
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    func choices() -> [PortChoice] {
        [.none] + deviceNames().map { .device($0) } + [.simulator]
    }

    /// At launch: the port used last time if it is present, else anything that looks like the organ,
    /// else the simulator if that was used last. A plugged-in organ beats a remembered simulator.
    func connectAtLaunch() {
        let names = deviceNames()
        let pick = PortPolicy.launchChoice(remembered: UserDefaults.standard.string(forKey: "port"), devices: names)
        if pick != .none { choose(pick); return }
        statusText = names.isEmpty
            ? "No organ found. Connect the XK-7D by USB, or choose the built-in simulator from the Organ popup."
            : "Choose your organ from the Organ popup."
        NotificationCenter.default.post(name: .connectionChanged, object: nil)
    }

    /// True while the chosen organ's port has gone (unplugged or turned off).
    private(set) var organMissing = false

    private func portsChanged() {
        let change = PortPolicy.afterPortsChanged(choice: choice, missing: organMissing,
                                                  remembered: UserDefaults.standard.string(forKey: "port"),
                                                  devices: deviceNames())
        switch change {
        case .nothing:
            break
        case .lost(let name):
            organMissing = true
            connection?.disconnect()
            statusText = "\(name) was disconnected. The app will connect again when it comes back."
            announcer.announce("Organ disconnected", force: true)
        case .back(let name):
            choose(.device(name))
            announcer.announce("Organ connected again", force: true)
            return
        case .found(let name):
            choose(.device(name))
            announcer.announce("Organ connected: \(name)", force: true)
            return
        }
        NotificationCenter.default.post(name: .connectionChanged, object: nil)
    }

    func choose(_ c: PortChoice, remember: Bool = true) {
        connection?.disconnect()
        organMissing = false
        session.holdUntilAnswered = false
        session.resetConnection()
        loopback = nil
        simulatorPorts = nil
        session.output = nil
        choice = c
        switch c {
        case .none:
            if remember { UserDefaults.standard.set("none", forKey: "port") }
            statusText = "Not connected."
        case .simulator:
            if remember { UserDefaults.standard.set("simulator", forKey: "port") }
            startSimulator()
        case .device(let name):
            if remember { UserDefaults.standard.set(name, forKey: "port") }
            let src = CoreMIDIConnection.sources().first { $0.name == name }
            let dst = CoreMIDIConnection.destinations().first { $0.name == name }
            do {
                try connection?.connect(source: src, destination: dst)
                session.output = connection
                statusText = dst == nil ? "Listening to \(name). It has no MIDI input, so changes cannot be sent."
                                        : "Connected to \(name). Checking that the organ answers…"
                session.forgetAllValues()
                session.requestIdentity()
                scheduleAnswerCheck(name: name)
            } catch {
                statusText = "Could not connect to \(name): \(error)"
            }
        }
        NotificationCenter.default.post(name: .connectionChanged, object: nil)
        NotificationCenter.default.post(name: .organValuesChanged, object: nil)
    }

    private func startSimulator() {
        let organ = simulator ?? SimulatedOrgan()
        organ.deviceID = session.addressing.deviceID
        organ.upperChannel = session.addressing.upperChannel
        organ.lowerChannel = session.addressing.lowerChannel
        organ.pedalChannel = session.addressing.pedalChannel
        organ.onChange = { _ in NotificationCenter.default.post(name: .simulatorChanged, object: nil) }
        simulator = organ
        session.forgetAllValues()
        // Prefer real CoreMIDI virtual ports (the same path as the organ); fall back to in-process.
        // Virtual ports can drop a message sent the instant they appear (seen once on a first
        // launch), so hold changes until the simulator has answered.
        session.holdUntilAnswered = true
        if let connection, let ports = try? VirtualSimulatorPorts(organ: organ) {
            simulatorPorts = ports
            let src = CoreMIDIConnection.sources().first { $0.uniqueID == ports.sourceID }
            let dst = CoreMIDIConnection.destinations().first { $0.uniqueID == ports.destinationID }
            if let src, let dst, (try? connection.connect(source: src, destination: dst)) != nil {
                session.output = connection
                statusText = "Connected to the built-in simulator through virtual MIDI ports. This is not a real organ."
                session.requestIdentity()
                return
            }
            simulatorPorts = nil
        }
        session.holdUntilAnswered = false
        loopback = LoopbackLink(session: session, organ: organ)
        statusText = "Connected to the built-in simulator. This is not a real organ."
    }

    private func scheduleAnswerCheck(name: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.choice == .device(name) else { return }
            self.statusText = self.session.organAnswered
                ? "Connected to \(name). The organ answered (device ID \(self.session.addressing.deviceID))."
                : "Connected to \(name), but the organ has not answered an identity request yet. Changes on the organ are still announced if it sends them."
            NotificationCenter.default.post(name: .connectionChanged, object: nil)
        }
    }

    /// What to say when something needs the organ and there isn't one.
    var notConnectedMessage: String {
        organMissing ? "The organ is disconnected, so nothing was sent. Check the USB cable and that the organ is on."
                     : "Not connected. Choose the organ or the simulator first."
    }

    var isConnected: Bool { choice != .none && session.output != nil && !organMissing }

    // MARK: Values

    private func eventArrived(_ e: OrganEvent) {
        NotificationCenter.default.post(name: .organValuesChanged, object: nil, userInfo: ["event": e])
    }

    func send(_ setting: Setting, raw: Int) {
        guard isConnected else {
            announcer.announce(notConnectedMessage, force: true)
            return
        }
        session.set(setting, raw: raw)
        NotificationCenter.default.post(name: .organValuesChanged, object: nil)
    }

    func send(_ setting: Setting, text: String) {
        guard isConnected else {
            announcer.announce(notConnectedMessage, force: true)
            return
        }
        session.set(setting, text: text)
        NotificationCenter.default.post(name: .organValuesChanged, object: nil)
    }

    func repeatLast() {
        announcer.announce(history.first ?? "Nothing has been announced yet.", force: true)
    }

    // MARK: Read from organ

    /// Identity request, then a Temporary dump request. The manual does not publish the dump's
    /// layout, so values cannot be read out of it; the dump is kept as a snapshot file instead.
    func readFromOrgan(completion: @escaping (String) -> Void) {
        guard isConnected else { completion(notConnectedMessage); return }
        readTimeout?.cancel()
        session.requestIdentity()
        session.requestDump(.temporary)
        var lastCount = -1
        func check(_ attempt: Int) {
            let count = session.currentDump?.count ?? 0
            let expected = XK7SysEx.temporaryPackets + XK7SysEx.adjustPackets
            if count >= expected || (attempt > 6 && count == lastCount) || attempt > 40 {
                let snap = session.finishDump()
                lastSnapshot = (snap?.count ?? 0) > 0 ? snap : lastSnapshot
                completion(readSummary(snap, expected: expected))
                return
            }
            lastCount = count
            let item = DispatchWorkItem { check(attempt + 1) }
            readTimeout = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
        }
        check(0)
    }

    private func readSummary(_ snap: DumpSnapshot?, expected: Int) -> String {
        let answered = session.organAnswered ? "The organ answered. " : "No identity reply. "
        guard let snap, snap.count > 0 else {
            return answered + "No memory dump arrived. Check the MIDI or USB connection. Settings still fill in as you change them on the organ."
        }
        let checks = snap.allChecksumsOK ? "all checks good" : "some checks failed"
        return answered + "Received \(snap.count) of \(expected) dump packets, \(checks). The manual doesn't say what's inside a dump, so the app can't show those values yet. Save Organ Snapshot keeps it as a file. Settings fill in as you change them on the organ."
    }

    var snapshot: DumpSnapshot? { lastSnapshot }

    // MARK: Organ setup

    struct SetupStep {
        let title: String
        let setting: Setting
        let raw: Int
        var onByDefault = true
    }

    func setupSteps() -> [SetupStep] {
        func s(_ b3: UInt8, _ b4: UInt8) -> Setting { database.setting(at: Address(0, 0, 0, b3, b4))! }
        return [
            SetupStep(title: "Send every setting change as SysEx (Individual Parameters: SysEx). Needed to hear Leslie cabinet, custom and other SysEx-only settings.",
                      setting: s(0x0C, 0x03), raw: 2),
            SetupStep(title: "Send and receive program changes (Program Change: On), so patch changes are announced.",
                      setting: s(0x0C, 0x04), raw: 1),
            SetupStep(title: "Send and receive drawbar moves (Drawbar Registration: On), so drawbars are announced.",
                      setting: s(0x0C, 0x05), raw: 1),
            SetupStep(title: "Change the organ's Upper send channel to \(session.addressing.upperChannel + 1), to match this app (Tx Upper). Only needed if the app says the channels don't match. It also moves the organ's Upper notes, so other MIDI gear listening to the organ may need changing too. Usually it's easier to change Upper channel in this app's Settings instead.",
                      setting: s(0x0D, 0x00), raw: session.addressing.upperChannel, onByDefault: false),
        ]
    }

    // MARK: Simulator panel actions

    func simulatorAction(_ action: SimulatorAction) {
        guard let organ = simulator, choice == .simulator else { return }
        action.perform(on: organ, database: database)
    }

    // MARK: Self-test (no speech, writes what would have been announced to a file)

    func runSelfTest(logPath: String, updaterLine: String) {
        var log: [String] = [updaterLine]
        func write() { try? (log.joined(separator: "\n") + "\n").write(toFile: logPath, atomically: true, encoding: .utf8) }
        announcer.silentSink = { log.append("ANNOUNCE " + $0); write() }
        choose(.simulator, remember: false)
        log.append("STATUS " + statusText)
        let steps: [(TimeInterval, () -> Void)] = [
            (0.5, { self.send(self.database.setting(at: Address(0, 0, 0, 0x10, 0x04))!, raw: 5)
                    log.append("SENT organ type Pipe") }),
            (1.0, { let v = self.simulator?.value(self.database.setting(at: Address(0, 0, 0, 0x10, 0x04))!)
                    log.append("SIMULATOR organ type raw \(v.map(String.init) ?? "nil"); simulator received \(self.simulator?.received.count ?? -1) messages: " +
                               (self.simulator?.received.map { $0.map { String(format: "%02X", $0) }.joined(separator: " ") }.joined(separator: " | ") ?? "")) }),
            (1.2, { self.simulator?.individualMode = .sysex
                    SimulatorAction.leslieHornSweep.perform(on: self.simulator!, database: self.database) }),
            (2.5, { SimulatorAction.togglePercussion.perform(on: self.simulator!, database: self.database) }),
            (3.2, { SimulatorAction.nextPatch.perform(on: self.simulator!, database: self.database) }),
            (3.8, { SimulatorAction.moveDrawbar.perform(on: self.simulator!, database: self.database) }),
            (4.5, { self.readFromOrgan { log.append("READ " + $0); write() } }),
            (8.0, { log.append("SELFTEST DONE \(self.database.parameters.count) settings"); write(); NSApp.terminate(nil) }),
        ]
        for (t, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + t) { f(); write() } }
    }
}

/// Things the simulator window can do, as if someone touched the organ's panel.
enum SimulatorAction: CaseIterable {
    case leslieHornSweep, toggleLeslieFast, togglePercussion, moveDrawbar, nextPatch, vibratoMode, randomSetting

    var title: String {
        switch self {
        case .leslieHornSweep: return "Turn the Leslie horn fast speed knob"
        case .toggleLeslieFast: return "Press Leslie Fast"
        case .togglePercussion: return "Press Percussion On"
        case .moveDrawbar: return "Move the Upper 8 foot drawbar"
        case .nextPatch: return "Recall the next User patch on Upper"
        case .vibratoMode: return "Turn the vibrato and chorus knob"
        case .randomSetting: return "Change a random setting"
        }
    }

    var help: String {
        switch self {
        case .leslieHornSweep: return "Sends about thirty quick changes, like turning a knob. Only the final value should be spoken. Needs Send changes as SysEx, because this setting has no NRPN."
        case .toggleLeslieFast: return "Turns the Leslie Fast switch on or off."
        case .togglePercussion: return "Turns percussion on or off."
        case .moveDrawbar: return "Moves the Upper 8 foot drawbar to a new position, sent as a drawbar control change."
        case .nextPatch: return "Sends a bank select and program change for the next User patch on the Upper part."
        case .vibratoMode: return "Steps the vibrato and chorus knob to its next position."
        case .randomSetting: return "Picks any setting from the manual's tables and changes it."
        }
    }

    func perform(on organ: SimulatedOrgan, database db: ParameterDatabase) {
        func s(_ a: Address) -> Setting { db.setting(at: a)! }
        func toggle(_ a: Address) { let st = s(a); organ.panelChange(st, raw: (organ.value(st) ?? 0) == 0 ? 1 : 0) }
        switch self {
        case .leslieHornSweep:
            let st = s(Address(0x42, 0, 0, 0, 0))
            let current = organ.value(st) ?? 141
            let target = current > 200 ? Int.random(in: 60...160) : Int.random(in: 220...300)
            let values = organ.knobSweep(st, to: target, steps: 30)
            for (i, v) in values.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.025) { organ.panelChange(st, raw: v) }
            }
        case .toggleLeslieFast: toggle(Address(0, 0, 0, 0x12, 0x0A))
        case .togglePercussion: toggle(Address(0, 0, 0, 0x11, 0x00))
        case .moveDrawbar:
            let st = s(Address(0, 0, 1, 1, 2))
            var level = Int.random(in: 0...8)
            if level == organ.value(st) { level = (level + 3) % 9 }
            organ.panelChange(st, raw: level)
        case .nextPatch:
            let n = (UserDefaults.standard.integer(forKey: "simulatorPatch") + 1) % 100
            UserDefaults.standard.set(n, forKey: "simulatorPatch")
            organ.selectPatch(part: "Upper", bankMSB: 0, program: n)
        case .vibratoMode:
            let st = s(Address(0, 0, 0, 0x12, 0x01))
            organ.panelChange(st, raw: ((organ.value(st) ?? 0) + 1) % 6)
        case .randomSetting:
            // Leave the simulator's own MIDI settings alone, or it could stop talking to the app.
            let plain = db.parameters.filter { !$0.hasIndices && !$0.isText &&
                !["MIDI Common", "MIDI Channel", "USB MIDI"].contains($0.manualCategory) }
            let p = plain.randomElement()!
            organ.panelChange(Setting(p), raw: p.allRawValues.randomElement()!)
        }
    }
}
