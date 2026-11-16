import Foundation

/// Anything that can carry bytes to the organ (CoreMIDI, the in-process simulator, a test).
public protocol MIDIOutput: AnyObject {
    func send(_ bytes: [UInt8])
}

/// MIDI channels and SysEx device ID the session assumes. Channels are 0-based (0 = channel 1).
public struct OrganAddressing: Equatable, Sendable {
    public var deviceID: UInt8 = 0          // p. 157 screenshot shows 0
    public var upperChannel = 0             // Basic template: Upper 1, Lower 2, Pedal 3 (p. 175)
    public var lowerChannel = 1
    public var pedalChannel = 2

    public init() {}

    func part(forChannel c: Int) -> String? {
        if c == upperChannel { return "Upper" }
        if c == lowerChannel { return "Lower" }
        if c == pedalChannel { return "Pedal" }
        return nil
    }
}

/// Something that happened on the organ, decoded.
public enum OrganEvent: Equatable {
    case value(Setting, raw: Int)
    case text(Setting, String)
    case program(part: String, description: String)
    case drawbar(part: DrawbarCC.Part, index: Int, level: Int)
    case leslieSpeed(Int)
    case controller(name: String, on: Bool)
    case identity(device: UInt8)
    case dumpPacket(type: UInt8, packet: Int, checksumOK: Bool, checksumNote: String)
    case acknowledge(type: UInt8, result: UInt8, packet: Int)
    case unknownAddress(Address)

    public static func == (a: OrganEvent, b: OrganEvent) -> Bool { String(describing: a) == String(describing: b) }
}

/// What a memory dump request brought back.
public struct DumpSnapshot {
    public var packets: [(type: UInt8, packet: Int, data: [UInt8], checksumOK: Bool)] = []
    public var rawMessages: [[UInt8]] = []
    public var checksumReadings: Set<String> = []
    public var started: Date = Date()

    public var count: Int { packets.count }
    public var allChecksumsOK: Bool { packets.allSatisfy(\.checksumOK) }
    public var syxData: Data { Data(rawMessages.joined()) }
}

/// The heart of the app, with no UI and no CoreMIDI: decodes what the organ sends, keeps what is
/// known of its settings, sends changes, hides our own echoes, and produces announcement text.
public final class OrganSession {
    public let database: ParameterDatabase
    public var addressing = OrganAddressing()
    public weak var output: MIDIOutput?

    /// Called for every decoded event; `isEcho` is true when it repeats something this app just sent.
    public var onEvent: ((OrganEvent, _ isEcho: Bool) -> Void)?
    /// Called with text ready to be spoken (already coalesced).
    public var onAnnouncement: ((String) -> Void)?
    /// Called instead of `onAnnouncement` for a line that must be said at once, cutting off whatever
    /// is being said (the Leslie speed, switched mid-performance). Falls back to `onAnnouncement`.
    public var onUrgentAnnouncement: ((String) -> Void)?
    /// Called when the device ID was learned from the organ.
    public var onDeviceIDLearned: ((UInt8) -> Void)?
    /// Called once per connection when the organ's controls (NRPN or drawbars) arrive on a channel
    /// other than the Upper channel the app listens on. The argument is that channel, 0-based.
    public var onChannelMismatch: ((Int) -> Void)?
    private var reportedMismatch: Set<Int> = []

    /// Called once per connection when a setting arrives as NRPN before any SysEx Data Set has: the
    /// organ is in NRPN mode, so settings without an NRPN (every Custom set, such as the pedal
    /// registration, and patch names) are never sent. Set Up Organ switches it to SysEx.
    public var onNRPNModeNoticed: (() -> Void)?
    private var sawDataSet = false
    private var toldNRPNMode = false

    /// Called for each dump packet while a dump is being received.
    public var onDumpProgress: ((DumpSnapshot) -> Void)?

    public let coalescer: AnnouncementCoalescer
    public var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// How long after sending a value an identical value coming back counts as our own echo.
    public var echoWindow: TimeInterval = 2.0
    /// Answer each received dump packet with an Acknowledge (p. 177). On by default; see HANDOFF.md.
    public var acknowledgeDumpPackets = true
    /// Hold outgoing messages until the other end has answered an Identity Request. Used for the
    /// simulator's virtual ports, which can drop a message sent the instant they are created. Not
    /// used for the organ, which may never answer and must still receive changes.
    public var holdUntilAnswered = false
    /// The shortest gap between two value changes sent to the organ. Faster changes to the same
    /// setting are merged, latest value wins, so a fast slider sweep cannot flood the organ.
    public var minimumSendGap: TimeInterval = 0.02

    /// When a User patch or a Favorite is chosen and the organ doesn't send its name by itself,
    /// ask for it with a Temporary dump and read the name out of that (see HANDOFF.md).
    public var askOrganForPatchNames = true
    /// How long a patch change waits for the organ to send the name by itself.
    public var nameWait: TimeInterval = 0.3
    /// How long after a patch change the dump is asked for (patch changes in quick succession ask once).
    public var nameDumpDelay: TimeInterval = 0.15
    /// How long a patch change waits in all when a dump has been asked for.
    public var nameDumpWait: TimeInterval = 1.2

    /// Whether asking the organ for names by dump works on this connection.
    public enum NameDumpState: String, Sendable { case untried, works, gaveUp }
    public private(set) var nameDumpState = NameDumpState.untried
    /// Names learned this session, by part ("Upper" or "Lower") and slot ("patch U05").
    public private(set) var patchNameCache: [String: String] = [:]
    /// Called with a line for the MIDI log whenever the app asks the organ for a name or learns one.
    public var onNameNote: ((String) -> Void)?

    private struct NameLookup {
        var description: String
        var cacheKey: String
        var startedAt: TimeInterval
        var deadline: TimeInterval
    }
    private struct NameFetch {
        var requestedAt: TimeInterval
        var lastPacketAt: TimeInterval?
        var packets: [Int: [UInt8]] = [:]
        var received = 0
        var done = false
        /// A newer patch change came while this dump was on its way: its names are for the old one.
        var stale = false
    }
    private var lookups: [String: NameLookup] = [:]
    private var nameFetch: NameFetch?
    private var nameDumpMisses = 0
    private var currentSlotKey: [String: String] = [:]

    public private(set) var values: [Address: Int] = [:]
    public private(set) var texts: [Address: String] = [:]
    public private(set) var drawbars: [String: Int] = [:]
    public private(set) var lastAnnouncement: String?
    public private(set) var currentDump: DumpSnapshot?
    public private(set) var organAnswered = false

    private var parser = MIDIByteParser()
    private var nrpn: NRPNDecoder
    private var bankMSB: [Int: Int] = [:]
    private var sentValues: [Address: (raw: Int, at: TimeInterval)] = [:]
    private var sentTexts: [Address: (text: String, at: TimeInterval)] = [:]
    private var sentDrawbars: [String: (level: Int, at: TimeInterval)] = [:]
    private var heldUntilAnswered: [[UInt8]] = []
    private var identityAskedAt: TimeInterval?
    private var identityAttempts = 0
    private var lastValueSendAt: TimeInterval = -.infinity
    private var paced: [(address: Address, message: [UInt8])] = []

    public init(database: ParameterDatabase = .shared, coalescer: AnnouncementCoalescer = AnnouncementCoalescer()) {
        self.database = database
        self.coalescer = coalescer
        self.nrpn = NRPNDecoder { msb, lsb in database.setting(nrpnMSB: msb, lsb: lsb)?.parameter.length }
    }

    // MARK: State

    public func value(of setting: Setting) -> Int? { values[setting.address] }
    public func text(of setting: Setting) -> String? { texts[setting.address] }

    /// Start afresh on a new connection: nothing has answered yet and nothing is waiting to go.
    public func resetConnection() {
        organAnswered = false
        heldUntilAnswered.removeAll()
        paced.removeAll()
        identityAskedAt = nil
        identityAttempts = 0
        reportedMismatch.removeAll()
        sawDataSet = false
        toldNRPNMode = false
        lookups.removeAll()
        nameFetch = nil
        nameDumpState = .untried
        nameDumpMisses = 0
        currentSlotKey.removeAll()
    }

    public func forgetAllValues() {
        values.removeAll(); texts.removeAll(); drawbars.removeAll()
    }

    // MARK: Sending

    /// Send a value with SysEx Data Set. Works for every parameter in the table, NRPN or not,
    /// and the organ receives SysEx whatever its Individual Parameters setting.
    @discardableResult
    public func set(_ setting: Setting, raw: Int) -> [UInt8] {
        let raw = setting.parameter.clamp(raw)
        let msg = XK7SysEx.dataSet(device: addressing.deviceID, setting: setting, raw: raw)
        values[setting.address] = raw
        sentValues[setting.address] = (raw, clock())
        if let d = drawbarKey(for: setting) {
            drawbars[d] = raw
            sentDrawbars[d] = (raw, clock())
        }
        coalescer.cancel(key: announceKey(for: setting))
        let now = clock()
        if now - lastValueSendAt < minimumSendGap || !paced.isEmpty {
            if let i = paced.firstIndex(where: { $0.address == setting.address }) {
                paced[i].message = msg
            } else {
                paced.append((setting.address, msg))
            }
        } else {
            lastValueSendAt = now
            transmit(msg)
        }
        return msg
    }

    /// Messages waiting for the pacing gap, oldest first (for tests).
    public var pacedCount: Int { paced.count }

    private func transmit(_ msg: [UInt8]) {
        let isIdentityRequest = msg.count == 6 && msg[1] == 0x7E && msg[3] == 0x06 && msg[4] == 0x01
        if holdUntilAnswered && !organAnswered && !isIdentityRequest {
            heldUntilAnswered.append(msg)
            return
        }
        deliver(msg)
    }

    private func flushPaced() {
        guard !paced.isEmpty, clock() - lastValueSendAt >= minimumSendGap else { return }
        let batch = paced
        paced.removeAll()
        lastValueSendAt = clock()
        for p in batch { transmit(p.message) }
    }

    private func releaseHeld() {
        let held = heldUntilAnswered
        heldUntilAnswered.removeAll()
        for var m in held {
            // The organ may have told us a different Device ID while these waited.
            if m.count > 2, m[1] == XK7SysEx.suzukiID { m[2] = addressing.deviceID }
            deliver(m)
        }
    }

    /// Messages held until the other end answers (for tests).
    public var heldCount: Int { heldUntilAnswered.count }

    @discardableResult
    public func set(_ setting: Setting, text: String) -> [UInt8] {
        let msg = XK7SysEx.dataSet(device: addressing.deviceID, setting: setting, text: text)
        let stored = TextCodec.decode(TextCodec.encode(text, length: setting.parameter.length))
        texts[setting.address] = stored
        sentTexts[setting.address] = (stored, clock())
        learnCurrentName(at: setting.address, PatchNames.clean(stored))
        transmit(msg)
        return msg
    }

    public func requestIdentity() {
        if !holdUntilAnswered { organAnswered = false }
        identityAskedAt = clock()
        identityAttempts = 1
        deliver(XK7SysEx.identityRequest(device: addressing.deviceID))
        if addressing.deviceID != 0x7F {
            // All-call as well, in case the organ's Device ID is not the one we assume.
            deliver(XK7SysEx.identityRequest(device: 0x7F))
        }
    }

    public func requestDump(_ type: XK7SysEx.DumpType) {
        nameFetch = nil
        currentDump = DumpSnapshot()
        transmit(XK7SysEx.dumpRequest(device: addressing.deviceID, type: type))
    }

    public func finishDump() -> DumpSnapshot? {
        defer { currentDump = nil }
        return currentDump
    }

    // MARK: Receiving

    public func receive(_ bytes: [UInt8]) {
        onMIDI?(true, bytes)
        for m in parser.feed(bytes) { handle(m) }
    }

    /// Every byte received (true) or sent (false), for the MIDI log.
    public var onMIDI: ((_ incoming: Bool, _ bytes: [UInt8]) -> Void)?

    private func deliver(_ bytes: [UInt8]) {
        guard let output else { return }
        onMIDI?(false, bytes)
        output.send(bytes)
    }

    /// Speak whatever has settled. Call this often (the app does every 50 ms).
    public func tick() {
        flushPaced()
        if holdUntilAnswered, !organAnswered, let asked = identityAskedAt, clock() - asked >= 0.3 {
            // Ask again a few times; after about three seconds send anyway rather than hold forever.
            if identityAttempts < 10 {
                identityAttempts += 1
                identityAskedAt = clock()
                deliver(XK7SysEx.identityRequest(device: addressing.deviceID))
                deliver(XK7SysEx.identityRequest(device: 0x7F))
            } else {
                identityAskedAt = nil
                releaseHeld()
            }
        }
        tickNames()
        for text in coalescer.due(at: clock()) { speak(text) }
    }

    /// Speak a line now, bypassing coalescing (used for the app's own status messages).
    public func speak(_ text: String) {
        lastAnnouncement = text
        onAnnouncement?(text)
    }

    private func handle(_ m: MIDIMessage) {
        switch m {
        case .sysex(let bytes): handleSysEx(bytes)
        case .controlChange(let ch, let cc, let v): handleCC(channel: ch, controller: cc, value: v)
        case .programChange(let ch, let program):
            guard let part = addressing.part(forChannel: ch) else { return }
            patchChanged(part: part, bank: bankMSB[ch], program: program)
        default: break
        }
    }

    private func handleCC(channel: Int, controller: Int, value: Int) {
        if controller == 0 { bankMSB[channel] = value; return }
        guard channel == addressing.upperChannel else {
            // The organ sends NRPN and drawbars only on its Upper channel (p. 156), so seeing them
            // elsewhere means the app's Upper channel doesn't match the organ's.
            if controller == 99 || DrawbarCC.drawbar(forController: controller) != nil,
               reportedMismatch.insert(channel).inserted {
                onChannelMismatch?(channel)
            }
            return
        }
        if let v = nrpn.handle(controller: controller, value: value) {
            if !sawDataSet && !toldNRPNMode {
                toldNRPNMode = true
                onNRPNModeNoticed?()
            }
            if let s = database.setting(nrpnMSB: v.msb, lsb: v.lsb) {
                received(s, raw: v.raw)
            } else {
                emit(.unknownAddress(Address(0, 0, 0, v.msb, v.lsb)), key: nil, text: nil, echo: false)
            }
            return
        }
        if let d = DrawbarCC.drawbar(forController: controller) {
            let level = DrawbarCC.level(forValue: value)
            let key = "\(d.part.rawValue).\(d.index)"
            drawbars[key] = level
            let echo = isRecent(sentDrawbars[key].map { ($0.level == level, $0.at) })
            emit(.drawbar(part: d.part, index: d.index, level: level), key: "drawbar.\(key)",
                 text: "\(d.part.rawValue) \(DrawbarCC.footageName(part: d.part, index: d.index)): \(level)", echo: echo)
            // Keep the registration setting in step with the drawbar.
            if let s = registrationSetting(part: d.part, index: d.index) { values[s.address] = level }
            return
        }
        switch controller {
        case 1:
            let text: String
            switch value {
            case 0: text = "Leslie speed: slow"
            case 127: text = "Leslie speed: fast"
            default: text = "Leslie speed: \(Int((Double(value) / 127 * 100).rounded())) percent"
            }
            emit(.leslieSpeed(value), key: "cc1", text: text, echo: false)
        case 49: onOff("Tone wheel brake", value)
        case 69: onOff("Sustain", value)
        case 85: onOff("ProChord", value)
        case 92:
            // Leslie Fast as a control change (p. 176): said like the panel switch, at once.
            let on = value >= 64
            values[Self.leslieFastAddress] = on ? 1 : 0
            onEvent?(.controller(name: "Leslie fast", on: on), false)
            speakUrgently(leslieLine(changed: Self.leslieFastAddress, raw: on ? 1 : 0)!)
        default: break
        }
    }

    private func onOff(_ name: String, _ value: Int) {
        let on = value >= 64
        emit(.controller(name: name, on: on), key: "cc.\(name)", text: "\(name): \(on ? "on" : "off")", echo: false)
    }

    private func handleSysEx(_ bytes: [UInt8]) {
        switch XK7Inbound.decode(bytes) {
        case .dataSet(let dev, let address, let data):
            learnDevice(dev)
            sawDataSet = true
            decodeDataSet(address: address, data: data)
        case .identityReply(let dev, let manufacturer, let family, let member):
            guard manufacturer == XK7SysEx.suzukiID, family == [0x00, 0x10], member == [0x00, 0x26] else { return }
            organAnswered = true
            identityAskedAt = nil
            learnDevice(dev)
            releaseHeld()
            emit(.identity(device: dev), key: nil, text: nil, echo: false)
        case .dataPacket(let dev, let type, let packet, let data, let ok, let note):
            learnDevice(dev)
            if nameFetchPacket(type: type, packet: packet, data: data) {
                if acknowledgeDumpPackets {
                    transmit(XK7SysEx.acknowledge(device: dev, type: type, result: ok ? 0x00 : 0x05, packet: packet))
                }
                return
            }
            if currentDump == nil { currentDump = DumpSnapshot() }
            currentDump!.packets.append((type, packet, data, ok))
            currentDump!.rawMessages.append(bytes)
            currentDump!.checksumReadings.insert(note)
            if acknowledgeDumpPackets {
                transmit(XK7SysEx.acknowledge(device: dev, type: type, result: ok ? 0x00 : 0x05, packet: packet))
            }
            emit(.dumpPacket(type: type, packet: packet, checksumOK: ok, checksumNote: note), key: nil, text: nil, echo: false)
            onDumpProgress?(currentDump!)
        case .acknowledge(_, let type, let result, let packet):
            emit(.acknowledge(type: type, result: result, packet: packet), key: nil, text: nil, echo: false)
        default:
            break
        }
    }

    /// One Data Set can carry several neighbouring parameters ("Data (Flexible bytes)"). We read
    /// the first, then step the last address byte by one for each further parameter, as the
    /// tables number them. The organ's real practice is unconfirmed; see HANDOFF.md.
    private func decodeDataSet(address: Address, data: [UInt8]) {
        var addr = address
        var rest = ArraySlice(data)
        while !rest.isEmpty {
            guard let s = database.setting(at: addr) else {
                emit(.unknownAddress(addr), key: nil, text: nil, echo: false)
                return
            }
            let len = s.parameter.length
            guard rest.count >= len else { return }
            let chunk = rest.prefix(len)
            rest = rest.dropFirst(len)
            if s.parameter.isText {
                receivedText(s, TextCodec.decode(Array(chunk)))
            } else {
                received(s, raw: XK7SysEx.value(from: chunk))
            }
            guard addr.bytes[4] < 0x7F else { return }
            var b = addr.bytes
            b[4] += 1
            addr = Address(b)
        }
    }

    private func received(_ s: Setting, raw: Int) {
        values[s.address] = raw
        let echo = isRecent(sentValues[s.address].map { ($0.raw == raw, $0.at) })
        if let d = drawbarKey(for: s) { drawbars[d] = raw }
        if let rotor = leslieLine(changed: s.address, raw: raw) {
            onEvent?(.value(s, raw: raw), echo)
            if !echo { speakUrgently(rotor) }
            return
        }
        emit(.value(s, raw: raw), key: announceKey(for: s), text: Self.line(s, raw: raw), echo: echo)
    }

    /// What is said for a setting's new value. An Off/On setting is said as "Percussion on" or
    /// "Leslie bypass off", not "Percussion on: On".
    public static func line(_ s: Setting, raw: Int) -> String {
        if case .choices(let options) = s.parameter.kind, options.count == 2,
           options[0].raw == 0, options[0].label == "Off", options[1].raw == 1, options[1].label == "On", raw == 0 || raw == 1 {
            var name = s.spokenName
            for suffix in [": on", " on"] where name.hasSuffix(suffix) { name = String(name.dropLast(suffix.count)); break }
            return "\(name) \(raw == 1 ? "on" : "off")"
        }
        return "\(s.spokenName): \(s.parameter.spoken(raw))"
    }

    // MARK: Leslie speed

    static let leslieFastAddress = Address(0, 0, 0, 0x12, 0x0A)
    static let leslieStopAddress = Address(0, 0, 0, 0x12, 0x09)

    /// The rotor state as one word (p. 59): Fast when [FAST] is on; otherwise Stop when [STOP] is
    /// lit, else Slow. Changing [STOP] while [FAST] is on changes nothing you hear yet, so it's
    /// said as the mode. Nil for any other setting.
    func leslieLine(changed a: Address, raw: Int) -> String? {
        if a == Self.leslieFastAddress {
            if raw == 1 { return "Fast" }
            return values[Self.leslieStopAddress] == 1 ? "Stop" : "Slow"
        }
        if a == Self.leslieStopAddress {
            if values[Self.leslieFastAddress] == 1 { return raw == 1 ? "Stop mode on" : "Stop mode off" }
            return raw == 1 ? "Stop" : "Slow"
        }
        return nil
    }

    /// Say a line now, cutting off anything being said, and drop anything older waiting under the
    /// same meaning.
    private func speakUrgently(_ text: String) {
        coalescer.cancel(key: "cc.Leslie fast")
        lastAnnouncement = text
        if let urgent = onUrgentAnnouncement { urgent(text) } else { onAnnouncement?(text) }
    }

    private func receivedText(_ s: Setting, _ text: String) {
        texts[s.address] = text
        if nameArrived(at: s.address, PatchNames.clean(text)) {
            // It completed a patch change's line; don't say it again on its own.
            onEvent?(.text(s, text), false)
            return
        }
        let echo = isRecent(sentTexts[s.address].map { ($0.text == text, $0.at) })
        emit(.text(s, text), key: s.address.description, text: "\(s.spokenName): \(text.isEmpty ? "blank" : text)", echo: echo)
    }

    private func isRecent(_ match: (Bool, TimeInterval)?) -> Bool {
        guard let (same, at) = match, same else { return false }
        return clock() - at <= echoWindow
    }

    private func emit(_ e: OrganEvent, key: String?, text: String?, echo: Bool) {
        onEvent?(e, echo)
        guard let key, let text else { return }
        if echo {
            coalescer.cancel(key: key)
        } else {
            coalescer.submit(key: key, text: text, at: clock())
        }
    }

    // MARK: Patch names

    static let nameUpperAddress = Address(0, 0, 0x10, 0, 0)
    static let nameLowerAddress = Address(0, 0, 0x10, 0, 1)

    private static func namePart(_ part: String) -> String { PatchNames.usesUpperName(part: part) ? "Upper" : "Lower" }

    /// The parts a name address belongs to: Upper's name, or Lower's (which Pedal shares).
    private static func parts(forNameAt a: Address) -> [String]? {
        if a == nameUpperAddress { return ["Upper"] }
        if a == nameLowerAddress { return ["Lower", "Pedal"] }
        return nil
    }

    private func patchChanged(part: String, bank: Int?, program: Int) {
        let desc = PatchSelect.describe(bank: bank, program: program)
        let key = "program.\(part)"
        let now = clock()
        onEvent?(.program(part: part, description: desc), false)
        lookups[part] = nil
        if nameFetch != nil { nameFetch!.stale = true }
        let cacheKey = Self.namePart(part) + "|" + desc
        if let name = PatchNames.factoryName(part: part, bank: bank, program: program) {
            currentSlotKey[part] = nil
            coalescer.submit(key: key, text: PatchNames.announcement(part: part, description: desc, name: name), at: now)
        } else if PatchNames.isLookupSlot(bank: bank, program: program) {
            currentSlotKey[part] = cacheKey
            let wait = willAskByDump ? nameDumpWait : nameWait
            lookups[part] = NameLookup(description: desc, cacheKey: cacheKey, startedAt: now, deadline: now + wait)
            coalescer.submit(key: key, text: PatchNames.announcement(part: part, description: desc, name: nil),
                             at: now, holdUntil: now + wait + 0.25)
        } else {
            currentSlotKey[part] = nil
            coalescer.submit(key: key, text: PatchNames.announcement(part: part, description: desc, name: nil), at: now)
        }
    }

    private var willAskByDump: Bool {
        askOrganForPatchNames && output != nil && nameDumpState != .gaveUp
    }

    /// Say a waiting patch change, with its name if there is one, and remember the name.
    private func finishLookup(part: String, name: String?) {
        guard let l = lookups.removeValue(forKey: part) else { return }
        var name = name
        if let n = name, !n.isEmpty { patchNameCache[l.cacheKey] = n } else { name = patchNameCache[l.cacheKey] }
        coalescer.release(key: "program.\(part)", text: PatchNames.announcement(part: part, description: l.description, name: name))
    }

    /// A name arrived from the organ. True if it completed a waiting patch change.
    private func nameArrived(at a: Address, _ name: String) -> Bool {
        guard let parts = Self.parts(forNameAt: a) else { return false }
        var used = false
        for p in parts where lookups[p] != nil {
            onNameNote?("Name for \(p) arrived from the organ: \(name)")
            finishLookup(part: p, name: name)
            used = true
        }
        if !used { learnCurrentName(at: a, name) }
        return used
    }

    /// The current patch was renamed (on the organ or from here): remember it under its slot.
    private func learnCurrentName(at a: Address, _ name: String) {
        guard let parts = Self.parts(forNameAt: a), !name.isEmpty else { return }
        for p in parts { if let k = currentSlotKey[p] { patchNameCache[k] = name } }
    }

    private func tickNames() {
        let now = clock()
        if let f = nameFetch {
            let since = f.lastPacketAt ?? f.requestedAt
            if f.received >= XK7SysEx.temporaryPackets + XK7SysEx.adjustPackets || now - since > 0.6 {
                nameFetch = nil
                if !f.done && !f.stale { dumpMissed(f.received == 0 ? "no dump came back" : "no names found in the dump") }
            }
        }
        if nameFetch == nil, willAskByDump, currentDump == nil, !lookups.isEmpty,
           let newest = lookups.values.map(\.startedAt).max(), now - newest >= nameDumpDelay,
           lookups.values.contains(where: { now < $0.deadline }) {
            nameFetch = NameFetch(requestedAt: now)
            onNameNote?("Asking the organ for the patch name (Temporary dump request)")
            transmit(XK7SysEx.dumpRequest(device: addressing.deviceID, type: .temporary))
        }
        for (part, l) in lookups where now >= l.deadline {
            finishLookup(part: part, name: nil)
        }
    }

    private func dumpMissed(_ why: String) {
        nameDumpMisses += 1
        onNameNote?("Patch name by dump: \(why)")
        if nameDumpMisses >= 2 && nameDumpState != .works {
            nameDumpState = .gaveUp
            onNameNote?("Stopped asking the organ for patch names on this connection")
        }
        for part in Array(lookups.keys) { finishLookup(part: part, name: nil) }
    }

    /// A dump packet that answers our name request. False if it isn't ours.
    private func nameFetchPacket(type: UInt8, packet: Int, data: [UInt8]) -> Bool {
        guard var f = nameFetch, currentDump == nil else { return false }
        f.received += 1
        f.lastPacketAt = clock()
        if type == XK7SysEx.DumpType.temporary.rawValue { f.packets[packet] = data }
        if !f.done && !f.stale {
            let stream = f.packets.keys.sorted().flatMap { f.packets[$0]! }
            if let names = PatchNames.fromTemporaryDump(stream) {
                f.done = true
                nameDumpState = .works
                nameDumpMisses = 0
                onNameNote?("Names found in the dump: Upper \(names.upper), Lower \(names.lower)")
                texts[Self.nameUpperAddress] = names.upper
                texts[Self.nameLowerAddress] = names.lower
                for p in Array(lookups.keys) {
                    finishLookup(part: p, name: Self.namePart(p) == "Upper" ? names.upper : names.lower)
                }
            } else if type != XK7SysEx.DumpType.temporary.rawValue || f.packets.count >= XK7SysEx.temporaryPackets {
                f.done = true
                nameFetch = f
                dumpMissed("no names found in the dump")
                return true
            }
        }
        nameFetch = f
        return true
    }

    private func learnDevice(_ dev: UInt8) {
        guard dev != 0x7F, dev != addressing.deviceID else { return }
        addressing.deviceID = dev
        onDeviceIDLearned?(dev)
    }

    /// A drawbar can arrive both as a control change and as its registration setting;
    /// both file under one key so a move is spoken once.
    private func announceKey(for s: Setting) -> String {
        if let d = drawbarKey(for: s) { return "drawbar.\(d)" }
        return s.address.description
    }

    // MARK: Drawbars as registration settings (00 00 01 0p 0n)

    private func drawbarKey(for s: Setting) -> String? {
        let b = s.address.bytes
        guard b[0] == 0, b[1] == 0, b[2] == 1 else { return nil }
        switch b[3] {
        case 1: return "Upper.\(b[4])"
        case 2: return "Lower.\(b[4])"
        case 3: return "Pedal.\(b[4])"
        default: return nil
        }
    }

    public func registrationSetting(part: DrawbarCC.Part, index: Int) -> Setting? {
        let p: UInt8 = part == .upper ? 1 : (part == .lower ? 2 : 3)
        return database.setting(at: Address(0, 0, 1, p, UInt8(index)))
    }
}
