import Foundation

/// A five-byte SysEx address, as printed in the manual ("MSB to LSB").
public struct Address: Hashable, Comparable, CustomStringConvertible, Sendable {
    public var bytes: [UInt8]

    public init(_ bytes: [UInt8]) {
        precondition(bytes.count == 5, "an XK-7 address is five bytes")
        self.bytes = bytes
    }

    public init(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8, _ b4: UInt8) {
        self.bytes = [b0, b1, b2, b3, b4]
    }

    public var description: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }

    public static func < (a: Address, b: Address) -> Bool { a.bytes.lexicographicallyPrecedes(b.bytes) }
}

/// How a parameter's raw value maps to what the organ's display shows.
public enum ValueKind: Equatable, Sendable {
    /// A list of named choices.
    case choices([(raw: Int, label: String)])
    /// shown = origin + (raw - zero) * step, with optional names for special raw values.
    case number(min: Int, max: Int, zero: Int, origin: Double, step: Double, decimals: Int, unit: String,
                plus: Bool, special: [Int: String])
    /// The manual publishes only the two end points; in between we can only say "step N".
    case steps(min: Int, max: Int, low: String, high: String)
    /// A MIDI note number, named the way the organ's display names it (note 60 = 3C).
    case note(min: Int, max: Int)
    /// Left / centre / right style values (pan, chorus mix).
    case balance(min: Int, max: Int, center: Int, left: String, right: String, centerLabel: String)
    /// Fixed-length ASCII text (patch and custom names).
    case text(length: Int)

    public static func == (a: ValueKind, b: ValueKind) -> Bool { String(describing: a) == String(describing: b) }
}

public struct IndexDimension: Sendable {
    public let name: String
    /// Which of the five address bytes carries this index.
    public let position: Int
    public let options: [(raw: Int, label: String)]

    public func label(for raw: Int) -> String {
        options.first(where: { $0.raw == raw })?.label ?? String(format: "%02X", raw)
    }

    /// The label as it should be read aloud and shown in pickers: "8 foot" rather than "8'",
    /// "number 13" rather than "#13", "C sharp" rather than "C#".
    public func spokenLabel(for raw: Int) -> String { IndexDimension.spoken(label(for: raw)) }

    static let footSpoken: [(String, String)] = [
        ("5 1/3'", "5 and a third foot"), ("2 2/3'", "2 and two thirds foot"), ("1 3/5'", "1 and three fifths foot"),
        ("1 1/3'", "1 and a third foot"),
    ]

    public static func spoken(_ label: String) -> String {
        var s = label
        for (a, b) in footSpoken { s = s.replacingOccurrences(of: a, with: b) }
        s = s.replacingOccurrences(of: "'", with: " foot")
        if s.hasPrefix("#F") { s = String(s.dropFirst()) }               // foldback wheels: "F96"
        else if s.hasPrefix("#") { s = "number " + s.dropFirst() }
        s = s.replacingOccurrences(of: "#", with: " sharp")
        return s
    }

    /// Whether to say the index's name before its value. "Key 3C" adds nothing to "3C",
    /// and "8 foot" already says it is a footage.
    func namedInSpeech(parameterName: String) -> Bool {
        if parameterName.lowercased().contains(name.lowercased()) { return false }
        return !["Footage", "Drawbar", "Key", "Formant", "Bank and key"].contains(name)
    }
}

public enum Section: String, CaseIterable, Sendable {
    case patch = "Patch", custom = "Custom", system = "System"

    public var title: String {
        switch self {
        case .patch: return "Patch settings"
        case .custom: return "Custom sets (tone wheels, contacts, pipes, Leslie)"
        case .system: return "System settings"
        }
    }
}

/// One row of the manual's MIDI tables (or a family of rows that differ only by an index,
/// such as one level per tone wheel).
public struct Parameter: Sendable, Identifiable {
    public let id: String
    public let section: Section
    public let category: String
    public let manualCategory: String
    public let manualName: String
    /// Plain-English name, front-loaded, used in announcements.
    public let name: String
    public let baseAddress: Address
    public let nrpn: (msb: UInt8, lsb: UInt8)?
    /// Bytes of data: 1, 2 (two 7-bit bytes, MSB first) or 16 (text).
    public let length: Int
    public let kind: ValueKind
    public let page: Int
    public let help: String
    public let notes: String?
    public let indices: [IndexDimension]
    public let xk7Only: Bool

    public var isText: Bool { if case .text = kind { return true } else { return false } }
    public var hasIndices: Bool { !indices.isEmpty }

    public var rawRange: ClosedRange<Int> {
        switch kind {
        case .choices(let o): return (o.map(\.raw).min() ?? 0)...(o.map(\.raw).max() ?? 0)
        case .number(let lo, let hi, _, _, _, _, _, _, _): return lo...hi
        case .steps(let lo, let hi, _, _): return lo...hi
        case .note(let lo, let hi): return lo...hi
        case .balance(let lo, let hi, _, _, _, _): return lo...hi
        case .text: return 0...0
        }
    }

    /// The concrete address for a choice of index values (in the order of `indices`).
    public func address(indexValues: [Int]) -> Address {
        var b = baseAddress.bytes
        for (dim, v) in zip(indices, indexValues) {
            b[dim.position] = UInt8(truncatingIfNeeded: Int(b[dim.position]) + v)
        }
        return Address(b)
    }

    /// Recover index values from a concrete address, or nil if it is not one of ours.
    public func indexValues(for address: Address) -> [Int]? {
        let positions = Set(indices.map(\.position))
        for i in 0..<5 where !positions.contains(i) {
            if address.bytes[i] != baseAddress.bytes[i] { return nil }
        }
        var out: [Int] = []
        for dim in indices {
            let v = Int(address.bytes[dim.position]) - Int(baseAddress.bytes[dim.position])
            guard dim.options.contains(where: { $0.raw == v }) else { return nil }
            out.append(v)
        }
        return out
    }
}

/// A parameter with its indices filled in: one real setting on the organ.
public struct Setting: Hashable, Sendable {
    public let parameter: Parameter
    public let indexValues: [Int]

    public init(_ parameter: Parameter, indexValues: [Int] = []) {
        self.parameter = parameter
        self.indexValues = indexValues
    }

    public var address: Address { parameter.address(indexValues: indexValues) }

    /// "Tone wheel level, tone wheel #13" or just "Organ type".
    public var spokenName: String {
        guard parameter.hasIndices else { return parameter.name }
        let parts = zip(parameter.indices, indexValues).map { dim, v -> String in
            let label = dim.spokenLabel(for: v)
            return dim.namedInSpeech(parameterName: parameter.name) ? "\(dim.name.lowercased()) \(label)" : label
        }
        return parameter.name + ", " + parts.joined(separator: ", ")
    }

    public static func == (a: Setting, b: Setting) -> Bool { a.address == b.address }
    public func hash(into h: inout Hasher) { h.combine(address) }
}

public enum ParameterDatabaseError: Error, CustomStringConvertible {
    case malformed(String)

    public var description: String {
        switch self {
        case .malformed(let s): return "parameters.json could not be read: \(s)"
        }
    }
}

/// The whole table from the manual, plus lookups by address, NRPN and name.
public final class ParameterDatabase: @unchecked Sendable {
    public let parameters: [Parameter]
    private var byExactAddress: [Address: Parameter] = [:]
    private var indexed: [Parameter] = []
    private var byNRPN: [UInt16: Parameter] = [:]
    private var byID: [String: Parameter] = [:]

    /// The table compiled into the app. Never crashes: if it can't be read (a broken build), this is
    /// an empty table and `loadError` says why, so the app can explain instead of quitting.
    public static let shared: ParameterDatabase = {
        do { return try ParameterDatabase.loadBundled() } catch {
            loadError = "\(error)"
            return ParameterDatabase(empty: ())
        }
    }()

    /// Set when `shared` couldn't be read.
    public private(set) static var loadError: String?

    /// The table is compiled in (ParameterTable.swift), not read from a resource file: SwiftPM's
    /// Bundle.module looks beside the .app and then in the build machine's .build folder, so 1.0.0
    /// to 1.0.3 crashed at launch on every other Mac.
    public static func loadBundled() throws -> ParameterDatabase {
        try ParameterDatabase(data: Data(parameterTableJSON.utf8))
    }

    private init(empty: Void) { parameters = [] }

    public init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["parameters"] as? [[String: Any]] else {
            throw ParameterDatabaseError.malformed("no parameter list")
        }
        parameters = try list.map(ParameterDatabase.parse)
        for p in parameters {
            byID[p.id] = p
            if p.hasIndices { indexed.append(p) } else { byExactAddress[p.baseAddress] = p }
            if let n = p.nrpn, !p.hasIndices { byNRPN[UInt16(n.msb) << 8 | UInt16(n.lsb)] = p }
        }
    }

    public func parameter(id: String) -> Parameter? { byID[id] }

    /// The setting living at a SysEx address, if the manual defines one there.
    public func setting(at address: Address) -> Setting? {
        if let p = byExactAddress[address] { return Setting(p) }
        for p in indexed {
            if let v = p.indexValues(for: address) { return Setting(p, indexValues: v) }
        }
        return nil
    }

    /// The setting an NRPN number refers to. Indexed NRPNs (the Favorites tables) are matched too.
    public func setting(nrpnMSB msb: UInt8, lsb: UInt8) -> Setting? {
        if let p = byNRPN[UInt16(msb) << 8 | UInt16(lsb)] { return Setting(p) }
        let address = Address(0, 0, 0, msb, lsb)
        for p in indexed where p.nrpn != nil {
            if let v = p.indexValues(for: address) { return Setting(p, indexValues: v) }
        }
        return nil
    }

    /// Search by any word in the friendly name, manual name or category. Every word must match.
    public func search(_ query: String) -> [Parameter] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard !words.isEmpty else { return parameters }
        return parameters.filter { p in
            let hay = "\(p.name) \(p.manualName) \(p.category) \(p.manualCategory) \(p.section.rawValue)".lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    // MARK: JSON

    private static func parse(_ d: [String: Any]) throws -> Parameter {
        func str(_ k: String) throws -> String {
            guard let s = d[k] as? String else { throw ParameterDatabaseError.malformed("\(k) in \(d["id"] ?? "?")") }
            return s
        }
        guard let addr = d["address"] as? [Int], addr.count == 5,
              let length = d["length"] as? Int,
              let value = d["value"] as? [String: Any],
              let sectionRaw = d["section"] as? String, let section = Section(rawValue: sectionRaw) else {
            throw ParameterDatabaseError.malformed("parameter \(d["id"] ?? "?")")
        }
        var nrpn: (UInt8, UInt8)? = nil
        if let n = d["nrpn"] as? [Int], n.count == 2 { nrpn = (UInt8(n[0]), UInt8(n[1])) }
        let indices: [IndexDimension] = (d["indices"] as? [[String: Any]] ?? []).map { i in
            IndexDimension(name: i["name"] as? String ?? "Index", position: i["position"] as? Int ?? 4,
                           options: options(i["options"]))
        }
        return Parameter(
            id: try str("id"), section: section, category: try str("category"),
            manualCategory: try str("manualCategory"), manualName: try str("manualName"), name: try str("name"),
            baseAddress: Address(addr.map { UInt8($0) }), nrpn: nrpn, length: length,
            kind: try kind(value), page: d["page"] as? Int ?? 0, help: d["help"] as? String ?? "",
            notes: d["notes"] as? String, indices: indices, xk7Only: d["xk7Only"] as? Bool ?? false)
    }

    private static func options(_ any: Any?) -> [(raw: Int, label: String)] {
        (any as? [[Any]] ?? []).compactMap { pair in
            guard pair.count == 2, let r = pair[0] as? Int, let l = pair[1] as? String else { return nil }
            return (r, l)
        }
    }

    private static func kind(_ v: [String: Any]) throws -> ValueKind {
        func i(_ k: String) -> Int { v[k] as? Int ?? 0 }
        func dbl(_ k: String) -> Double { (v[k] as? NSNumber)?.doubleValue ?? 0 }
        switch v["type"] as? String {
        case "enum": return .choices(options(v["options"]))
        case "number":
            var special: [Int: String] = [:]
            for (r, l) in options(v["special"]) { special[r] = l }
            return .number(min: i("min"), max: i("max"), zero: i("zero"), origin: dbl("origin"), step: dbl("step"),
                           decimals: i("decimals"), unit: v["unit"] as? String ?? "", plus: v["plus"] as? Bool ?? false,
                           special: special)
        case "steps": return .steps(min: i("min"), max: i("max"), low: v["low"] as? String ?? "", high: v["high"] as? String ?? "")
        case "note": return .note(min: i("min"), max: i("max"))
        case "pan": return .balance(min: i("min"), max: i("max"), center: i("center"), left: v["left"] as? String ?? "L%d",
                                    right: v["right"] as? String ?? "R%d", centerLabel: v["centerLabel"] as? String ?? "Center")
        case "text": return .text(length: i("length"))
        default: throw ParameterDatabaseError.malformed("value type \(v["type"] ?? "?")")
        }
    }
}
