import Foundation

/// A complete MIDI message, after running status and SysEx reassembly.
public enum MIDIMessage: Equatable, Sendable {
    case controlChange(channel: Int, controller: Int, value: Int)
    case programChange(channel: Int, program: Int)
    case noteOn(channel: Int, note: Int, velocity: Int)
    case noteOff(channel: Int, note: Int, velocity: Int)
    case pitchBend(channel: Int, value: Int)
    case other([UInt8])
    case sysex([UInt8])

    public var bytes: [UInt8] {
        switch self {
        case .controlChange(let c, let n, let v): return [0xB0 | UInt8(c & 0xF), UInt8(n & 0x7F), UInt8(v & 0x7F)]
        case .programChange(let c, let p): return [0xC0 | UInt8(c & 0xF), UInt8(p & 0x7F)]
        case .noteOn(let c, let n, let v): return [0x90 | UInt8(c & 0xF), UInt8(n & 0x7F), UInt8(v & 0x7F)]
        case .noteOff(let c, let n, let v): return [0x80 | UInt8(c & 0xF), UInt8(n & 0x7F), UInt8(v & 0x7F)]
        case .pitchBend(let c, let v): return [0xE0 | UInt8(c & 0xF), UInt8(v & 0x7F), UInt8((v >> 7) & 0x7F)]
        case .other(let b), .sysex(let b): return b
        }
    }
}

/// Turns a raw byte stream (as CoreMIDI delivers it, in any chunking) into messages.
/// Handles running status, real-time bytes inside other messages, and SysEx split across packets.
public struct MIDIByteParser {
    private var status: UInt8 = 0
    private var data: [UInt8] = []
    private var sysex: [UInt8]? = nil

    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [MIDIMessage] {
        var out: [MIDIMessage] = []
        for b in bytes {
            if b >= 0xF8 { out.append(.other([b])); continue }          // real-time: never breaks running status
            if b == 0xF0 { sysex = [b]; status = 0; data = []; continue }
            if b == 0xF7 {
                if var s = sysex { s.append(b); out.append(.sysex(s)) }
                sysex = nil
                continue
            }
            if b & 0x80 != 0 {
                if sysex != nil { sysex = nil }                         // unterminated SysEx: drop it
                if b >= 0xF0 { status = 0; data = []; out.append(.other([b])); continue }
                status = b; data = []
                continue
            }
            if sysex != nil { sysex!.append(b); continue }
            guard status != 0 else { continue }                         // stray data byte
            data.append(b)
            let channel = Int(status & 0x0F)
            switch status & 0xF0 {
            case 0xC0:
                out.append(.programChange(channel: channel, program: Int(b))); data = []
            case 0xD0:
                out.append(.other([status, b])); data = []
            case 0x80, 0x90, 0xA0, 0xB0, 0xE0:
                if data.count == 2 {
                    let (d1, d2) = (Int(data[0]), Int(data[1]))
                    switch status & 0xF0 {
                    case 0xB0: out.append(.controlChange(channel: channel, controller: d1, value: d2))
                    case 0x90: out.append(d2 == 0 ? .noteOff(channel: channel, note: d1, velocity: 0)
                                                  : .noteOn(channel: channel, note: d1, velocity: d2))
                    case 0x80: out.append(.noteOff(channel: channel, note: d1, velocity: d2))
                    case 0xE0: out.append(.pitchBend(channel: channel, value: d1 | d2 << 7))
                    default: out.append(.other([status, data[0], data[1]]))
                    }
                    data = []
                }
            default:
                data = []
            }
        }
        return out
    }
}

/// Everything the manual specifies about the XK-7's System Exclusive (p. 177).
public enum XK7SysEx {
    public static let suzukiID: UInt8 = 0x55
    public static let modelID: [UInt8] = [0x10, 0x26]

    public enum Command: UInt8, Sendable {
        case nrpnSwitch = 0x02, dataPacket = 0x11, dumpRequest = 0x12, dataSet = 0x13, acknowledge = 0x14
    }

    public enum DumpType: UInt8, Sendable {
        case temporary = 0x07, adjustKeys = 0x08, system = 0x0A

        public var title: String {
            switch self {
            case .temporary: return "current patch"
            case .adjustKeys: return "Adjust A# and B keys"
            case .system: return "system settings"
            }
        }
    }

    public enum IndividualMode: UInt8, Sendable { case off = 0, nrpn = 1, sysex = 2 }

    static func header(_ device: UInt8, _ command: Command) -> [UInt8] {
        [0xF0, suzukiID, device & 0x7F] + modelID + [command.rawValue]
    }

    /// Data Set: F0 55 dd 10 26 13 [address x5] [data] F7
    public static func dataSet(device: UInt8, address: Address, data: [UInt8]) -> [UInt8] {
        header(device, .dataSet) + address.bytes + data.map { $0 & 0x7F } + [0xF7]
    }

    /// The data bytes for a value: one byte, or two 7-bit bytes MSB first.
    public static func valueBytes(_ raw: Int, length: Int) -> [UInt8] {
        switch length {
        case 1: return [UInt8(raw & 0x7F)]
        case 2: return [UInt8((raw >> 7) & 0x7F), UInt8(raw & 0x7F)]
        default:
            precondition(false, "length \(length) is not a number")
            return []
        }
    }

    public static func value(from bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { $0 << 7 | Int($1 & 0x7F) }
    }

    /// Data Set for one setting and raw value.
    public static func dataSet(device: UInt8, setting: Setting, raw: Int) -> [UInt8] {
        dataSet(device: device, address: setting.address, data: valueBytes(raw, length: setting.parameter.length))
    }

    public static func dataSet(device: UInt8, setting: Setting, text: String) -> [UInt8] {
        dataSet(device: device, address: setting.address, data: TextCodec.encode(text, length: setting.parameter.length))
    }

    /// Dump Request (organ receives only): F0 55 dd 10 26 12 [type] F7
    public static func dumpRequest(device: UInt8, type: DumpType) -> [UInt8] {
        header(device, .dumpRequest) + [type.rawValue, 0xF7]
    }

    /// NRPN Switch: F0 55 dd 10 26 02 [00 Off / 01 NRPN / 02 SysEx] F7
    public static func nrpnSwitch(device: UInt8, mode: IndividualMode) -> [UInt8] {
        header(device, .nrpnSwitch) + [mode.rawValue, 0xF7]
    }

    /// Acknowledge: F0 55 dd 10 26 14 [type] [result] [PNH] [PNL] F7
    public static func acknowledge(device: UInt8, type: UInt8, result: UInt8, packet: Int) -> [UInt8] {
        header(device, .acknowledge) + [type, result, UInt8((packet >> 7) & 0x7F), UInt8(packet & 0x7F), 0xF7]
    }

    /// Identity Request (universal): F0 7E dd 06 01 F7
    public static func identityRequest(device: UInt8) -> [UInt8] { [0xF0, 0x7E, device & 0x7F, 0x06, 0x01, 0xF7] }

    /// Identity Reply as printed on p. 177: F0 7E dd 06 02 55 00 10 00 26 00 00 00 00 F7
    public static func identityReply(device: UInt8) -> [UInt8] {
        [0xF0, 0x7E, device & 0x7F, 0x06, 0x02, 0x55, 0x00, 0x10, 0x00, 0x26, 0x00, 0x00, 0x00, 0x00, 0xF7]
    }

    // MARK: Memory dump packets

    /// "64 Bytes Data, 128 Bytes nibblized ASCII, ex: 7EH = 37H, 45H": each byte becomes its two hex digits in ASCII.
    public static func nibblize(_ data: [UInt8]) -> [UInt8] {
        let digits = Array("0123456789ABCDEF".utf8)
        return data.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0x0F)]] }
    }

    public static func denibblize(_ ascii: [UInt8]) -> [UInt8]? {
        guard ascii.count % 2 == 0 else { return nil }
        func v(_ c: UInt8) -> UInt8? {
            switch c {
            case 0x30...0x39: return c - 0x30
            case 0x41...0x46: return c - 0x41 + 10
            case 0x61...0x66: return c - 0x61 + 10
            default: return nil
            }
        }
        var out: [UInt8] = []
        out.reserveCapacity(ascii.count / 2)
        var i = 0
        while i < ascii.count {
            guard let hi = v(ascii[i]), let lo = v(ascii[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
            i += 2
        }
        return out
    }

    /// "Check Digit: Lower 7 bits of XOR [DATA]". [DATA] is the nibblized block as sent.
    public static func checkDigit(_ bytes: [UInt8]) -> UInt8 { bytes.reduce(0, ^) & 0x7F }

    /// Data Packet: F0 55 dd 10 26 11 [type] [PNH] [PNL] [128 ASCII] [check] F7 = 139 bytes.
    public static func dataPacket(device: UInt8, type: UInt8, packet: Int, data64: [UInt8]) -> [UInt8] {
        precondition(data64.count == 64)
        let ascii = nibblize(data64)
        return header(device, .dataPacket) + [type, UInt8((packet >> 7) & 0x7F), UInt8(packet & 0x7F)] + ascii
            + [checkDigit(ascii), 0xF7]
    }

    /// Number of packets per dump (p. 177): temporary 6 + 11 (A and B keys), system 13.
    public static let temporaryPackets = 6, adjustPackets = 11, systemPackets = 13
}

/// A Suzuki/XK-7 SysEx message, decoded.
public enum XK7Inbound: Equatable, Sendable {
    case dataSet(device: UInt8, address: Address, data: [UInt8])
    case dataPacket(device: UInt8, type: UInt8, packet: Int, data: [UInt8], checksumOK: Bool, checksumNote: String)
    case acknowledge(device: UInt8, type: UInt8, result: UInt8, packet: Int)
    case dumpRequest(device: UInt8, type: UInt8)
    case nrpnSwitch(device: UInt8, mode: UInt8)
    case identityRequest(device: UInt8)
    case identityReply(device: UInt8, manufacturer: UInt8, family: [UInt8], member: [UInt8])
    case unknown([UInt8])

    public static func decode(_ m: [UInt8]) -> XK7Inbound {
        guard m.count >= 4, m.first == 0xF0, m.last == 0xF7 else { return .unknown(m) }
        if m[1] == 0x7E, m.count >= 6, m[3] == 0x06 {
            if m[4] == 0x01 { return .identityRequest(device: m[2]) }
            if m[4] == 0x02, m.count >= 11 {
                return .identityReply(device: m[2], manufacturer: m[5], family: Array(m[6...7]), member: Array(m[8...9]))
            }
            return .unknown(m)
        }
        guard m.count >= 7, m[1] == XK7SysEx.suzukiID, m[3] == 0x10, m[4] == 0x26 else { return .unknown(m) }
        let dev = m[2]
        let body = Array(m[6..<(m.count - 1)])
        switch m[5] {
        case XK7SysEx.Command.dataSet.rawValue:
            guard body.count >= 6 else { return .unknown(m) }
            return .dataSet(device: dev, address: Address(Array(body[0..<5])), data: Array(body[5...]))
        case XK7SysEx.Command.dataPacket.rawValue:
            guard body.count == 3 + 128 + 1 else { return .unknown(m) }
            let ascii = Array(body[3..<131])
            let check = body[131]
            let decoded = XK7SysEx.denibblize(ascii) ?? []
            // The manual's wording allows two readings; note which one matched, for the hand-off.
            let okAscii = XK7SysEx.checkDigit(ascii) == check
            let okRaw = XK7SysEx.checkDigit(decoded) == check
            let note = okAscii ? "XOR of nibblized data" : (okRaw ? "XOR of decoded data" : "no match")
            return .dataPacket(device: dev, type: body[0], packet: Int(body[1]) << 7 | Int(body[2]), data: decoded,
                               checksumOK: okAscii || okRaw, checksumNote: note)
        case XK7SysEx.Command.acknowledge.rawValue:
            guard body.count == 4 else { return .unknown(m) }
            return .acknowledge(device: dev, type: body[0], result: body[1], packet: Int(body[2]) << 7 | Int(body[3]))
        case XK7SysEx.Command.dumpRequest.rawValue:
            guard body.count == 1 else { return .unknown(m) }
            return .dumpRequest(device: dev, type: body[0])
        case XK7SysEx.Command.nrpnSwitch.rawValue:
            guard body.count == 1 else { return .unknown(m) }
            return .nrpnSwitch(device: dev, mode: body[0])
        default:
            return .unknown(m)
        }
    }
}

/// NRPN as the manual writes it: Bx 63 MSB, Bx 62 LSB, Bx 06 data MSB [, Bx 26 data LSB].
public enum NRPN {
    public static func messages(channel: Int, msb: UInt8, lsb: UInt8, raw: Int, length: Int) -> [MIDIMessage] {
        var m: [MIDIMessage] = [
            .controlChange(channel: channel, controller: 99, value: Int(msb)),
            .controlChange(channel: channel, controller: 98, value: Int(lsb)),
        ]
        if length == 2 {
            m.append(.controlChange(channel: channel, controller: 6, value: (raw >> 7) & 0x7F))
            m.append(.controlChange(channel: channel, controller: 38, value: raw & 0x7F))
        } else {
            m.append(.controlChange(channel: channel, controller: 6, value: raw & 0x7F))
        }
        return m
    }
}

/// Drawbar control changes (p. 177): all on the UPPER channel.
public enum DrawbarCC {
    public enum Part: String, Sendable { case upper = "Upper", lower = "Lower", pedal = "Pedal" }

    public static let footages = ["16 foot", "5 and a third foot", "8 foot", "4 foot", "2 and two thirds foot",
                                  "2 foot", "1 and three fifths foot", "1 and a third foot", "1 foot"]

    /// Controller number -> (part, drawbar index 0...8, or 0/1 for the pedal's 16' and 8').
    public static func drawbar(forController cc: Int) -> (part: Part, index: Int)? {
        switch cc {
        case 12...20: return (.upper, cc - 12)
        case 21...29: return (.lower, cc - 21)
        case 33: return (.pedal, 0)
        case 35: return (.pedal, 1)
        default: return nil
        }
    }

    public static func controller(part: Part, index: Int) -> Int {
        switch part {
        case .upper: return 12 + index
        case .lower: return 21 + index
        case .pedal: return index == 0 ? 33 : 35
        }
    }

    /// 00-0F = 0, 10-1F = 1, ... 70-7E = 7, 7F = 8.
    public static func level(forValue v: Int) -> Int { v >= 127 ? 8 : min(max(v, 0) / 16, 7) }

    /// The value to send for a level; the bottom of each bucket, and 7F for 8 (manual example: level 7 = 70H).
    public static func value(forLevel level: Int) -> Int { level >= 8 ? 127 : max(level, 0) * 16 }

    public static func footageName(part: Part, index: Int) -> String {
        part == .pedal ? (index == 0 ? "16 foot" : "8 foot") : footages[index]
    }
}

/// Program changes (p. 176): bank MSB 00 User, 01 Factory, 64-6D Favorite banks C-A;
/// program 00-63 patch, 64-6D Favorite key C-A, 7E/7F Adjust A#/B.
public enum PatchSelect {
    static let keys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A"]

    public static func describe(bank: Int?, program: Int) -> String {
        switch program {
        case 0x7E: return "Adjust A#"
        case 0x7F: return "Adjust B"
        case 0x64...0x6D:
            let key = keys[program - 0x64]
            if let b = bank, (0x64...0x6D).contains(b) { return "Favorite \(keys[b - 0x64])-\(key)" }
            return "Favorite key \(key)"
        case 0...0x63:
            switch bank {
            case 0: return String(format: "patch U%02d", program)
            case 1: return String(format: "patch F%02d", program)
            default: return "patch \(program)"
            }
        default:
            return "program \(program)"
        }
    }

    public static func spoken(_ s: String) -> String { s.replacingOccurrences(of: "#", with: " sharp") }
}
