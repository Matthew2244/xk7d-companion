import Foundation

/// Turns MIDI going to and from the organ into lines for the MIDI log, a file someone with a real
/// XK-7D can send back so we can see what the organ really sends. One line per message: direction,
/// the bytes in hex, and a short note of what it is. Notes, the expression pedal and real-time
/// bytes are counted, not written, so playing doesn't bury the rest.
public final class MIDILogger {
    private var inbound = MIDIByteParser()
    private var outbound = MIDIByteParser()
    private let database: ParameterDatabase
    /// Messages left out since the last line written (notes, expression, clock and active sensing).
    public private(set) var skipped = 0

    public init(database: ParameterDatabase = .shared) { self.database = database }

    /// Lines for bytes received from the organ (`incoming` true) or sent to it.
    public func lines(incoming: Bool, _ bytes: [UInt8]) -> [String] {
        let messages = incoming ? inbound.feed(bytes) : outbound.feed(bytes)
        var out: [String] = []
        for m in messages {
            if Self.isChatter(m) { skipped += 1; continue }
            if skipped > 0 {
                out.append("    (\(skipped) note, expression or timing message\(skipped == 1 ? "" : "s") not written)")
                skipped = 0
            }
            let hex = m.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            out.append("\(incoming ? "IN " : "OUT") \(hex)  [\(describe(m))]")
        }
        return out
    }

    static func isChatter(_ m: MIDIMessage) -> Bool {
        switch m {
        case .noteOn, .noteOff, .pitchBend: return true
        case .controlChange(_, let cc, _): return cc == 11 || cc == 64
        case .other(let b): return b.count == 1 && b[0] >= 0xF8
        default: return false
        }
    }

    /// What a message is, in a few words.
    public func describe(_ m: MIDIMessage) -> String {
        switch m {
        case .programChange(let ch, let p): return "program change, channel \(ch + 1), program \(p)"
        case .controlChange(let ch, let cc, let v):
            let name: String
            switch cc {
            case 0: name = "bank select MSB"
            case 32: name = "bank select LSB"
            case 99: name = "NRPN MSB"
            case 98: name = "NRPN LSB"
            case 6: name = "data entry MSB"
            case 38: name = "data entry LSB"
            case 1: name = "Leslie speed"
            case 92: name = "Leslie fast"
            default:
                if let d = DrawbarCC.drawbar(forController: cc) {
                    name = "\(d.part.rawValue) drawbar \(DrawbarCC.footageName(part: d.part, index: d.index))"
                } else {
                    name = "control \(cc)"
                }
            }
            return "\(name), channel \(ch + 1), value \(v)"
        case .sysex(let b):
            switch XK7Inbound.decode(b) {
            case .dataSet(_, let a, let data):
                let what = database.setting(at: a)?.spokenName ?? "unknown address"
                return "Data Set \(a.description) \(what), \(data.count) byte\(data.count == 1 ? "" : "s")"
            case .dataPacket(_, let t, let n, _, let ok, _):
                return String(format: "dump packet type %02X number %d, check %@", t, n, ok ? "good" : "failed")
            case .acknowledge(_, let t, let r, let n): return String(format: "acknowledge type %02X result %02X packet %d", t, r, n)
            case .dumpRequest(_, let t): return String(format: "dump request type %02X", t)
            case .nrpnSwitch(_, let mode): return "NRPN switch \(mode)"
            case .identityRequest(let d): return "identity request, device \(d)"
            case .identityReply(let d, _, _, _): return "identity reply, device \(d)"
            case .unknown: return "SysEx"
            }
        default: return "other"
        }
    }
}
