import Foundation

/// Note names the way the XK-7 display writes them: octave first, so note 60 is "3C"
/// and note 0 is "-2C" (manual p. 103, "Setting Range: -2C – 8G").
public enum NoteName {
    static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    public static func display(_ note: Int) -> String {
        "\(note / 12 - 2)\(names[((note % 12) + 12) % 12])"
    }

    /// For speech: "C sharp 3" reads better than "3C#".
    public static func spoken(_ note: Int) -> String {
        let n = names[((note % 12) + 12) % 12].replacingOccurrences(of: "#", with: " sharp")
        return "\(n) \(note / 12 - 2)"
    }
}

extension Parameter {
    /// The value as the organ's display would show it.
    public func display(_ raw: Int) -> String {
        switch kind {
        case .choices(let options):
            return options.first(where: { $0.raw == raw })?.label ?? "Unknown value \(raw)"
        case .number(_, _, let zero, let origin, let step, let decimals, let unit, let plus, let special):
            if let s = special[raw] { return s }
            let v = origin + Double(raw - zero) * step
            var text = String(format: "%.\(decimals)f", v)
            if text.hasPrefix("-") && Double(text) == 0 { text.removeFirst() }
            if plus && v > 0 { text = "+" + text }
            return unit.isEmpty ? text : "\(text) \(Self.unitText(unit, value: v))"
        case .steps(let lo, let hi, let low, let high):
            if raw == lo { return low }
            if raw == hi { return high }
            return "step \(raw - lo) of \(hi - lo)"
        case .note:
            return NoteName.display(raw)
        case .balance(_, _, let center, let left, let right, let centerLabel):
            if raw == center { return centerLabel }
            if raw < center { return left.replacingOccurrences(of: "%d", with: "\(center - raw)") }
            return right.replacingOccurrences(of: "%d", with: "\(raw - center)")
        case .text:
            return ""
        }
    }

    /// The same value phrased for speech, where the display's shorthand would be misread.
    public func spoken(_ raw: Int) -> String {
        switch kind {
        case .note: return NoteName.spoken(raw)
        case .balance(_, _, let center, _, _, let centerLabel):
            if raw == center { return centerLabel }
            let d = display(raw)
            if d.hasPrefix("L") { return "left \(center - raw)" }
            if d.hasPrefix("R") { return "right \(raw - center)" }
            if d.hasPrefix("D") { return "dry \(center - raw)" }
            if d.hasSuffix("V") { return "vibrato \(raw - center)" }
            return d
        default:
            return display(raw)
                .replacingOccurrences(of: "-inf", with: "minus infinity")
                .replacingOccurrences(of: "A#", with: "A sharp")
        }
    }

    static func unitText(_ unit: String, value: Double) -> String {
        if abs(value) == 1 {
            switch unit {
            case "octaves": return "octave"
            case "semitones": return "semitone"
            case "cents": return "cent"
            default: break
            }
        }
        return unit
    }

    /// Every raw value, in order, for controls that step through them.
    public var allRawValues: [Int] {
        if case .choices(let o) = kind { return o.map(\.raw) }
        return Array(rawRange)
    }

    /// The step a slider or stepper should take with the arrow keys.
    public func clamp(_ raw: Int) -> Int { min(max(raw, rawRange.lowerBound), rawRange.upperBound) }
}

/// Text values: the organ uses 7-bit ASCII, padded to 16 characters.
public enum TextCodec {
    /// Typographic quotes and dashes (which macOS can put in a text field) become their plain
    /// ASCII forms, so a name like "Jimmy’s" doesn't reach the organ as "Jimmy?s".
    public static func plain(_ s: String) -> String {
        var t = s
        for (a, b) in [("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\""),
                       ("\u{2013}", "-"), ("\u{2014}", "-"), ("\u{00A0}", " ")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t
    }

    public static func encode(_ s: String, length: Int = 16) -> [UInt8] {
        var bytes = plain(s).unicodeScalars.map { $0.value < 0x80 && $0.value >= 0x20 ? UInt8($0.value) : UInt8(ascii: "?") }
        if bytes.count > length { bytes = Array(bytes.prefix(length)) }
        while bytes.count < length { bytes.append(0x20) }
        return bytes
    }

    public static func decode(_ bytes: [UInt8]) -> String {
        let chars = bytes.map { $0 >= 0x20 && $0 < 0x7F ? Character(UnicodeScalar($0)) : " " }
        return String(chars).trimmingCharacters(in: .whitespaces)
    }
}

extension Parameter {
    /// A typed number as a whole number, or nil when it's far outside any range. Converting
    /// infinity ("1e400") or 1e20 to Int would stop the app.
    static func whole(_ d: Double) -> Int? {
        guard d.isFinite, abs(d) < 1_000_000_000 else { return nil }
        return Int(d)
    }

    /// Turn what the user typed into a raw value, using the same mapping the display uses:
    /// "340 rpm", "+2", "-12.1 dB", "Random", "off", "3C" or "C3", "L10", "center", "step 12".
    public func rawValue(fromTyped text: String) -> Int? {
        let p = self
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }
        func number(_ s: String) -> Double? { Scanner(string: s.replacingOccurrences(of: "+", with: "")).scanDouble() }
        switch p.kind {
        case .steps(let lo, let hi, let low, let high):
            if t == low.lowercased() { return lo }
            if t == high.lowercased() { return hi }
            guard let n = number(t.replacingOccurrences(of: "step", with: "").trimmingCharacters(in: .whitespaces)),
                  let whole = Self.whole(n) else { return nil }
            let raw = lo + whole
            return (lo...hi).contains(raw) ? raw : nil
        case .note(let lo, let hi):
            if let n = Int(t), (lo...hi).contains(n) { return n }
            let names = ["c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"]
            let compact = t.replacingOccurrences(of: " sharp", with: "#").replacingOccurrences(of: " ", with: "")
            // Octave first like the display ("3C#"), or letter first ("C#3").
            let pattern = try! NSRegularExpression(pattern: "^(-?\\d)([a-g]#?)$|^([a-g]#?)(-?\\d)$")
            guard let m = pattern.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) else { return nil }
            func g(_ i: Int) -> String? { Range(m.range(at: i), in: compact).map { String(compact[$0]) } }
            guard let octave = Int(g(1) ?? g(4) ?? ""), let name = g(2) ?? g(3), let k = names.firstIndex(of: name) else { return nil }
            let raw = (octave + 2) * 12 + k
            return (lo...hi).contains(raw) ? raw : nil
        case .balance(let lo, let hi, let center, _, _, let centerLabel):
            if t == centerLabel.lowercased() || t == "center" || t == "centre" || t == "c" { return center }
            var raw: Int?
            if t.hasPrefix("l") || t.hasPrefix("left") || t.hasPrefix("d") || t.hasPrefix("dry"),
               let n = number(t.trimmingCharacters(in: .letters.union(.whitespaces))).flatMap(Self.whole) { raw = center - n }
            else if t.hasPrefix("r") || t.hasPrefix("right") || t.hasSuffix("v") || t.hasPrefix("vib"),
                    let n = number(t.trimmingCharacters(in: .letters.union(.whitespaces))).flatMap(Self.whole) { raw = center + n }
            else if let n = number(t).flatMap(Self.whole) { raw = center + n }
            return raw.flatMap { (lo...hi).contains($0) ? $0 : nil }
        default:
            break
        }
        if case .number(let lo, let hi, let zero, let origin, let step, _, _, _, let special) = p.kind {
            // Named values ("Random", "Off", "-inf", "Mono"): the whole word, or the start of it.
            let hasLetters = t.rangeOfCharacter(from: .letters) != nil
            if let (r, _) = special.first(where: { $0.value.lowercased() == t || (hasLetters && $0.value.lowercased().hasPrefix(t)) }) {
                return r
            }
            let numeric = t.replacingOccurrences(of: "±", with: "").replacingOccurrences(of: "+", with: "")
            guard let v = Scanner(string: numeric).scanDouble(), let steps = Self.whole(((v - origin) / step).rounded())
            else { return nil }
            let raw = steps + zero
            if (lo...hi).contains(raw), special[raw] == nil { return raw }
            // A named value that is also a number, like "0 rpm" for a stopped rotor.
            if let (r, _) = special.first(where: { Scanner(string: $0.value).scanDouble() == v }) { return r }
            return nil
        }
        return nil
    }
}
