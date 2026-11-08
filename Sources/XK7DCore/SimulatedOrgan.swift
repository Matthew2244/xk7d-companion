import Foundation

/// A stand-in XK-7D for testing and demonstrating without the real organ.
///
/// It follows the protocol as the manual describes it and as this app implements it: it stores
/// values sent by Data Set or NRPN, answers Identity Request and Dump Request, obeys NRPN Switch
/// and the Individual Parameters setting, and can play "panel" changes the way the real organ is
/// expected to send them. Where the manual is silent (the contents of a dump, whether the organ
/// echoes, how fast it transmits) the simulator's behaviour is an assumption, listed in HANDOFF.md.
/// It is clearly a simulator: its identity reply is the organ's, but every port and window that
/// shows it says "Simulator".
public final class SimulatedOrgan {
    public let database: ParameterDatabase
    public var deviceID: UInt8 = 0
    /// Upper channel, 0-based, used for NRPN and drawbars in both directions.
    public var upperChannel = 0
    public var lowerChannel = 1
    public var pedalChannel = 2
    /// Where the simulator's MIDI goes (the app's input).
    public var send: (([UInt8]) -> Void)?
    /// Called whenever the simulator's stored state changes, for its window.
    public var onChange: ((String) -> Void)?

    public private(set) var values: [Address: Int] = [:]
    public private(set) var texts: [Address: String] = [:]
    /// Every message received, for tests and the simulator window.
    public private(set) var received: [[UInt8]] = []
    public private(set) var acknowledgements = 0

    private var parser = MIDIByteParser()
    private var nrpn: NRPNDecoder
    private var bank: [Int: Int] = [:]

    public init(database: ParameterDatabase = .shared) {
        self.database = database
        self.nrpn = NRPNDecoder { msb, lsb in database.setting(nrpnMSB: msb, lsb: lsb)?.parameter.length }
        loadDefaults()
    }

    // MARK: Settings the simulator obeys (they live in its own parameter store, as on the organ)

    private func systemValue(_ b3: UInt8, _ b4: UInt8) -> Int? { values[Address(0, 0, 0, b3, b4)] }

    public var individualMode: XK7SysEx.IndividualMode {
        get { XK7SysEx.IndividualMode(rawValue: UInt8(systemValue(0x0C, 0x03) ?? 1)) ?? .nrpn }
        set { values[Address(0, 0, 0, 0x0C, 0x03)] = Int(newValue.rawValue) }
    }

    public var transmitsDrawbars: Bool {
        get { (systemValue(0x0C, 0x05) ?? 1) == 1 }
        set { values[Address(0, 0, 0, 0x0C, 0x05)] = newValue ? 1 : 0 }
    }

    public var transmitsProgramChange: Bool {
        get { (systemValue(0x0C, 0x04) ?? 1) == 1 }
        set { values[Address(0, 0, 0, 0x0C, 0x04)] = newValue ? 1 : 0 }
    }

    /// Sensible starting values: the centre of signed ranges, 440 Hz, drawbars 888000000, names.
    public func loadDefaults() {
        values.removeAll(); texts.removeAll()
        for p in database.parameters where !p.hasIndices {
            let s = Setting(p)
            switch p.kind {
            case .text: texts[s.address] = p.manualCategory.contains("Upper") ? "Simulator Upper" :
                                           (p.manualCategory.contains("Lower") ? "Simulator Lower" : "Simulator")
            case .number(let lo, let hi, let zero, _, _, _, _, _, _): values[s.address] = (lo...hi).contains(zero) ? zero : lo
            case .balance(_, _, let center, _, _, _): values[s.address] = center
            case .note: values[s.address] = 60
            default: values[s.address] = p.rawRange.lowerBound
            }
        }
        for (i, level) in [8, 8, 8, 0, 0, 0, 0, 0, 0].enumerated() { values[Address(0, 0, 1, 1, UInt8(i))] = level }
        for (i, level) in [0, 0, 8, 4, 0, 0, 0, 0, 0].enumerated() { values[Address(0, 0, 1, 2, UInt8(i))] = level }
        values[Address(0, 0, 1, 3, 0)] = 5
        values[Address(0, 0, 1, 3, 1)] = 2
        // The Basic MIDI template (p. 175): Local Control On, Individual Parameters NRPN,
        // Program Change On, Drawbar Registration On, channels Upper 1, Lower 2, Pedal 3.
        values[Address(0, 0, 0, 0x0C, 0x01)] = 64
        values[Address(0, 0, 0, 0x0C, 0x02)] = 1
        individualMode = .nrpn
        transmitsProgramChange = true
        transmitsDrawbars = true
        for (i, ch) in [0, 1, 2, 0, 1, 2].enumerated() { values[Address(0, 0, 0, 0x0D, UInt8(i))] = ch }
        values[Address(0, 0, 0, 0x0B, 0x04)] = 0             // Favorites Off (p. 185 default)
    }

    public func value(_ s: Setting) -> Int? {
        if let v = values[s.address] { return v }
        return s.parameter.hasIndices ? s.parameter.rawRange.lowerBound : nil
    }

    // MARK: Receiving (what the app sends)

    public func receive(_ bytes: [UInt8]) {
        for m in parser.feed(bytes) {
            received.append(m.bytes)
            switch m {
            case .sysex(let b): handleSysEx(b)
            case .controlChange(let ch, let cc, let v):
                if cc == 0 { bank[ch] = v }
                guard ch == upperChannel, let n = nrpn.handle(controller: cc, value: v),
                      let s = database.setting(nrpnMSB: n.msb, lsb: n.lsb),
                      individualMode == .nrpn else { continue }
                store(s, raw: n.raw)
            default: break
            }
        }
    }

    private func accepts(_ dev: UInt8) -> Bool { dev == deviceID || dev == 0x7F }

    private func handleSysEx(_ b: [UInt8]) {
        switch XK7Inbound.decode(b) {
        case .dataSet(let dev, let address, let data):
            guard accepts(dev) else { return }   // "The receiving is ignored by unmatched Device ID" (p. 157)
            var addr = address
            var rest = ArraySlice(data)
            while !rest.isEmpty, let s = database.setting(at: addr), rest.count >= s.parameter.length {
                let chunk = rest.prefix(s.parameter.length)
                rest = rest.dropFirst(s.parameter.length)
                if s.parameter.isText {
                    texts[s.address] = TextCodec.decode(Array(chunk))
                    onChange?("\(s.spokenName) set to \(texts[s.address] ?? "")")
                } else {
                    store(s, raw: s.parameter.clamp(XK7SysEx.value(from: chunk)))
                }
                var bytes = addr.bytes
                bytes[4] &+= 1
                addr = Address(bytes)
            }
        case .identityRequest(let dev):
            guard accepts(dev) else { return }
            transmit(XK7SysEx.identityReply(device: deviceID))
        case .dumpRequest(let dev, let type):
            guard accepts(dev) else { return }
            sendDump(type: type)
        case .nrpnSwitch(let dev, let mode):
            guard accepts(dev), let m = XK7SysEx.IndividualMode(rawValue: mode) else { return }
            individualMode = m
            onChange?("Individual parameters set to \(["Off", "NRPN", "SysEx"][Int(mode)])")
        case .acknowledge:
            acknowledgements += 1
        default:
            break
        }
    }

    private func store(_ s: Setting, raw: Int) {
        values[s.address] = raw
        onChange?("\(s.spokenName) set to \(s.parameter.display(raw))")
    }

    // MARK: Dump

    /// Packets framed exactly as p. 177 describes. Their 64-byte contents are this simulator's own
    /// invention (the manual does not publish the dump layout): parameter values in address order.
    private func sendDump(type: UInt8) {
        let plan: [(UInt8, Int)]
        switch type {
        case 0x07: plan = [(0x07, XK7SysEx.temporaryPackets), (0x08, XK7SysEx.adjustPackets)]
        case 0x0A: plan = [(0x0A, XK7SysEx.systemPackets)]
        default: return
        }
        var stream: [UInt8] = []
        for (addr, v) in values.sorted(by: { $0.key < $1.key }) {
            stream += addr.bytes + [UInt8((v >> 7) & 0x7F), UInt8(v & 0x7F)]
        }
        var offset = 0
        for (t, count) in plan {
            for n in 0..<count {
                var chunk = [UInt8](repeating: 0, count: 64)
                for i in 0..<64 where offset + i < stream.count { chunk[i] = stream[offset + i] }
                offset += 64
                transmit(XK7SysEx.dataPacket(device: deviceID, type: t, packet: n, data64: chunk))
            }
        }
    }

    // MARK: Panel actions (what a player does on the organ)

    /// A change made on the organ's panel or menu. Sent as the Individual Parameters setting says:
    /// SysEx Data Set, NRPN on the Upper channel (only for parameters that have one), or nothing.
    public func panelChange(_ s: Setting, raw: Int) {
        let raw = s.parameter.clamp(raw)
        store(s, raw: raw)
        if let part = drawbarPart(s) {
            // A drawbar move also goes out as its control change.
            if transmitsDrawbars {
                transmit(MIDIMessage.controlChange(channel: upperChannel,
                                                   controller: DrawbarCC.controller(part: part.0, index: part.1),
                                                   value: DrawbarCC.value(forLevel: raw)).bytes)
            }
            return
        }
        transmitParameter(s, raw: raw)
    }

    public func panelText(_ s: Setting, _ text: String) {
        texts[s.address] = TextCodec.decode(TextCodec.encode(text, length: s.parameter.length))
        onChange?("\(s.spokenName) set to \(text)")
        if individualMode == .sysex {
            transmit(XK7SysEx.dataSet(device: deviceID, setting: s, text: text))
        }
    }

    private func transmitParameter(_ s: Setting, raw: Int) {
        switch individualMode {
        case .sysex:
            transmit(XK7SysEx.dataSet(device: deviceID, setting: s, raw: raw))
        case .nrpn:
            guard let n = s.parameter.nrpn ?? nrpnFromAddress(s) else { return }
            for m in NRPN.messages(channel: upperChannel, msb: n.msb, lsb: n.lsb, raw: raw, length: s.parameter.length) {
                transmit(m.bytes)
            }
        case .off:
            break
        }
    }

    private func nrpnFromAddress(_ s: Setting) -> (msb: UInt8, lsb: UInt8)? {
        guard s.parameter.nrpn != nil else { return nil }
        return (s.address.bytes[3], s.address.bytes[4])
    }

    private func drawbarPart(_ s: Setting) -> (DrawbarCC.Part, Int)? {
        let b = s.address.bytes
        guard b[0] == 0, b[1] == 0, b[2] == 1 else { return nil }
        switch b[3] {
        case 1: return (.upper, Int(b[4]))
        case 2: return (.lower, Int(b[4]))
        case 3: return (.pedal, Int(b[4]))
        default: return nil
        }
    }

    /// Recall a patch from the panel: bank select and program change on the part's channel.
    public func selectPatch(part: String, bankMSB: Int, program: Int) {
        guard transmitsProgramChange else { return }
        let ch = part == "Lower" ? lowerChannel : (part == "Pedal" ? pedalChannel : upperChannel)
        transmit(MIDIMessage.controlChange(channel: ch, controller: 0, value: bankMSB).bytes)
        transmit(MIDIMessage.controlChange(channel: ch, controller: 32, value: 0).bytes)
        transmit(MIDIMessage.programChange(channel: ch, program: program).bytes)
    }

    /// The raw values a knob passes through when turned from its current value to `to`.
    public func knobSweep(_ s: Setting, to target: Int, steps: Int) -> [Int] {
        let start = value(s) ?? s.parameter.rawRange.lowerBound
        let target = s.parameter.clamp(target)
        guard steps > 1 else { return [target] }
        return (1...steps).map { i in start + Int((Double(target - start) * Double(i) / Double(steps)).rounded()) }
    }

    private func transmit(_ bytes: [UInt8]) { send?(bytes) }
}
