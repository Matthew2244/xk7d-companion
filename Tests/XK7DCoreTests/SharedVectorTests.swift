import XCTest
@testable import XK7DCore

/// The answers the Swift core gives, written to Tests/Vectors/core-vectors.json. The Windows core
/// (windows/XK7DCore.Tests) reads the same file and must give the same answer to every one, so
/// both are checked against one set: every value of every setting as displayed and spoken, what
/// typing gives, lookups by address and NRPN, Data Set and NRPN bytes, patch names.
///
/// This test fails if the file is out of date. To rewrite it after a deliberate change:
///     XK7D_WRITE_VECTORS=1 swift test --filter SharedVectorTests
final class SharedVectorTests: XCTestCase {
    static let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vectors/core-vectors.json")

    func testVectorsFileMatchesTheSwiftCore() throws {
        let text = CoreVectors.build()
        if ProcessInfo.processInfo.environment["XK7D_WRITE_VECTORS"] != nil {
            try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: Self.file, atomically: true, encoding: .utf8)
        }
        let onDisk = try String(contentsOf: Self.file, encoding: .utf8)
        XCTAssertEqual(onDisk.count, text.count, "Tests/Vectors/core-vectors.json is out of date; see this test's comment")
        XCTAssertTrue(onDisk == text, "Tests/Vectors/core-vectors.json is out of date; see this test's comment")
    }
}

enum CoreVectors {
    /// Things people might type, tried on every setting that takes a typed value.
    static let typedInputs = [
        "", " ", "-", "+", "±", "0", "1", "-1", "+1", "±3", "1.5", "-1.5", ".5", "5.", "1e2", "1e", "1E-1", "1e400",
        "-1e400", "99999999999999999999", "inf", "-inf", "nan", "0x10", "1,5", " 12 ", "\t7", "abc", "12abc",
        "- 1", "--1", "1.2.3", "\u{0663}", "\u{FF13}", "00012", "-0", "+0", "1 1",
        "c", "l", "r", "d", "v", "center", "centre", "even", "c 3", "left 3", "right 3", "L3", "R3", "3V", "d3",
        "vib 2", "dry 2", "l-3", "step", "step 1", "step 99", "Step 3", "3C", "C3", "c#3", "3c#", "C sharp 3",
        "-2c", "8g", "9c", "h3", "random", "rand", "r", "off", "o", "on", "mono", "m", "cont", "continue",
        "-inf dB", "340 rpm", "200", "199", "0 rpm", "442 hz", "-12.1 db", "+4.0 dB", "2.5 sec", "100", "127",
        "128", "16383", "16384", "8192", "-24", "+12", "1.25 kHz", "1.2 kHz", "20 hz", "104", "-64", "+63",
        "64", "Center", "3C (middle C)",
    ]

    static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }

    static func json(_ o: Any) -> String {
        let d = try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        return String(decoding: d, as: UTF8.self)
    }

    static func typedApplies(_ p: Parameter) -> Bool {
        switch p.kind {
        case .number, .note, .balance, .steps: return true
        default: return false
        }
    }

    /// Index choices worth checking: every option of each index with the others at their first,
    /// and the last option of all of them together.
    static func samples(_ p: Parameter) -> [[Int]] {
        guard p.hasIndices else { return [[]] }
        let firsts = p.indices.map { $0.options.first!.raw }
        var out: [[Int]] = []
        for (i, d) in p.indices.enumerated() {
            for o in d.options {
                var v = firsts
                v[i] = o.raw
                if !out.contains(v) { out.append(v) }
            }
        }
        let lasts = p.indices.map { $0.options.last!.raw }
        if !out.contains(lasts) { out.append(lasts) }
        return out
    }

    static func lookup(_ s: Setting?) -> Any {
        guard let s else { return NSNull() }
        return [s.parameter.id, s.indexValues] as [Any]
    }

    static func build() -> String {
        let db = ParameterDatabase.shared
        var params: [String] = []
        var settings: [String] = []
        for p in db.parameters {
            var o: [String: Any] = ["id": p.id, "length": p.length, "address": p.baseAddress.description]
            if !p.isText {
                let raws = p.allRawValues
                o["rawRange"] = [p.rawRange.lowerBound, p.rawRange.upperBound]
                o["values"] = raws.map { [$0, p.display($0), p.spoken($0)] as [Any] }
                o["clamp"] = [p.rawRange.lowerBound - 1, p.rawRange.upperBound + 1, -100000, 100000].map { p.clamp($0) }
                if typedApplies(p) {
                    o["typedDisplay"] = raws.map { p.rawValue(fromTyped: p.display($0)) as Any? ?? NSNull() }
                    o["typedSpoken"] = raws.map { p.rawValue(fromTyped: p.spoken($0)) as Any? ?? NSNull() }
                    o["typedOther"] = typedInputs.map { p.rawValue(fromTyped: $0) as Any? ?? NSNull() }
                }
            }
            params.append(json(o))

            for iv in samples(p) {
                let s = Setting(p, indexValues: iv)
                var bytes = s.address.bytes
                let message: [UInt8]
                if p.isText {
                    message = XK7SysEx.dataSet(device: 0x10, setting: s, text: "Jimmy\u{2019}s \u{201C}Ballad\u{201D} \u{2013} Caf\u{E9}")
                } else {
                    message = XK7SysEx.dataSet(device: 0x10, setting: s, raw: p.rawRange.upperBound)
                }
                // The address one past this one, to check where each family stops.
                var next: Any = NSNull()
                if bytes[4] < 0x7F { bytes[4] += 1; next = lookup(db.setting(at: Address(bytes))) }
                settings.append(json([p.id, iv, s.address.description, s.spokenName, hex(message), next] as [Any]))
            }
        }

        var nrpn: [String] = []
        for msb in 0..<128 {
            for lsb in 0..<128 {
                guard let s = db.setting(nrpnMSB: UInt8(msb), lsb: UInt8(lsb)) else { continue }
                let m = NRPN.messages(channel: 2, msb: UInt8(msb), lsb: UInt8(lsb), raw: s.parameter.rawRange.upperBound,
                                      length: s.parameter.length).flatMap(\.bytes)
                nrpn.append(json([msb, lsb, s.parameter.id, s.indexValues, hex(m)] as [Any]))
            }
        }

        var patches: [String] = []
        for bank in [-1, 0, 1, 2, 0x63, 0x64, 0x65, 0x6D, 0x6E, 0x7F] {
            let names = (0..<128).map { PatchSelect.describe(bank: bank < 0 ? nil : bank, program: $0) }
            patches.append(json([bank, names, names.map(PatchSelect.spoken)] as [Any]))
        }

        // Patch names: the factory table, the spoken line, names read out of dumps.
        let factory = (0..<100).map { [PatchNames.factoryUpper[$0], PatchNames.factoryLower[$0],
                                       PatchNames.spoken(PatchNames.factoryUpper[$0]), PatchNames.spoken(PatchNames.factoryLower[$0])] }
        var announcements: [[String]] = []
        for part in ["Upper", "Lower", "Pedal"] {
            for (bank, program) in [(1, 0), (1, 21), (1, 99), (0, 5), (0x65, 0x69), (nil, 0x7E), (2, 3)] as [(Int?, Int)] {
                let desc = PatchSelect.describe(bank: bank, program: program)
                let factoryName = PatchNames.factoryName(part: part, bank: bank, program: program) ?? ""
                announcements.append([part, desc, factoryName, PatchNames.isLookupSlot(bank: bank, program: program) ? "lookup" : "",
                                      PatchNames.announcement(part: part, description: desc, name: nil),
                                      PatchNames.announcement(part: part, description: desc, name: "Jazz 8\u{B4} Lead")])
            }
        }
        func dumpStream(_ names: String, at offset: Int, fill: UInt8) -> [UInt8] {
            var b = [UInt8](repeating: fill, count: 120)
            for (i, c) in Array(names.utf8).enumerated() where offset + i < b.count { b[offset + i] = c }
            return b
        }
        let dumpCases: [[UInt8]] = [
            dumpStream("Dr. L.S.       UDr. L.S.       L", at: 10, fill: 0),
            dumpStream("Jazz Lead       Bass            ", at: 0, fill: 0),
            dumpStream("Jazz Lead                       ", at: 50, fill: 0),
            dumpStream("Ab              x               ", at: 3, fill: 0),
            dumpStream("A               b               ", at: 3, fill: 0),
            dumpStream("", at: 0, fill: 0x40),
            dumpStream("12345678901234567890123456789012", at: 0, fill: 0),
            dumpStream("Jazz Lead       Bass Line       ", at: 0, fill: 0x41),
            Array(TextCodec.encode("Short").prefix(5)),
        ]
        let dumps = dumpCases.map { d -> [Any] in
            let r = PatchNames.fromTemporaryDump(d)
            return [hex(d), r.map { [$0.upper, $0.lower] as Any } ?? NSNull()]
        }
        let cleanInputs = ["  Jazz    Lead  ", "Dr. L.S.       U", "A  L", "Organ  L", "\u{0}x\u{0}", ""]
        let cleaned = cleanInputs.map { [$0, PatchNames.clean($0)] }
        // The spoken line for every setting at its lowest and highest value.
        var lines: [[Any]] = []
        for p in db.parameters where !p.isText {
            let st = Setting(p, indexValues: p.indices.map { $0.options.first!.raw })
            lines.append([p.id, OrganSession.line(st, raw: p.rawRange.lowerBound), OrganSession.line(st, raw: p.rawRange.upperBound)])
        }
        // The MIDI log for a stream of mixed messages, in both directions.
        let logStream: [UInt8] = [0xB0, 0x00, 0x00, 0xB0, 0x20, 0x00, 0xC0, 0x05, 0x90, 60, 100, 0x80, 60, 0, 0xFE,
                                  0xB0, 0x0B, 0x40, 0xB0, 0x0E, 0x60, 0xB0, 0x63, 0x12, 0xB0, 0x62, 0x0A, 0xB0, 0x06, 0x01]
            + XK7SysEx.dumpRequest(device: 0, type: .temporary)
            + XK7SysEx.dataSet(device: 0, setting: db.setting(at: Address(0, 0, 0x10, 0, 0))!, text: "Gospel")
            + XK7SysEx.dataPacket(device: 0, type: 7, packet: 2, data64: [UInt8](repeating: 0x41, count: 64))
            + XK7SysEx.acknowledge(device: 0, type: 7, result: 0, packet: 2)
            + XK7SysEx.identityRequest(device: 0x7F) + XK7SysEx.identityReply(device: 3)
            + [0xF0, 0x55, 0x00, 0x10, 0x26, 0x02, 0x02, 0xF7, 0xF0, 0x01, 0x02, 0xF7, 0xB2, 92, 127, 0xE0, 0, 64, 0xB1, 1, 30]
        let logger = MIDILogger(database: db)
        let logLines = logger.lines(incoming: true, Array(logStream.prefix(13))) + logger.lines(incoming: true, Array(logStream.dropFirst(13)))
            + logger.lines(incoming: false, logStream)

        let notes = (0..<128).map { [NoteName.display($0), NoteName.spoken($0)] }
        let drawbars = (0..<128).map { DrawbarCC.level(forValue: $0) }
        let drawbarValues = (0...8).map { DrawbarCC.value(forLevel: $0) }
        let texts = ["", "Jimmy", "A name that is far too long", "Caf\u{E9}", "Jimmy\u{2019}s \u{201C}Ballad\u{201D}",
                     "Gospel \u{2013} Slow", "tab\there", "\u{00A0}lead space"]
            .map { [$0, hex(TextCodec.encode($0)), TextCodec.decode(TextCodec.encode($0))] }

        return """
        {
         "about": "Answers from the Swift core (Tests/XK7DCoreTests/SharedVectorTests.swift). The Windows tests check the C# core gives the same. Regenerate: XK7D_WRITE_VECTORS=1 swift test --filter SharedVectorTests",
         "typedInputs": \(json(typedInputs)),
         "notes": \(json(notes)),
         "drawbarLevels": \(json(drawbars)),
         "drawbarValues": \(json(drawbarValues)),
         "texts": \(json(texts)),
         "patches": [
        \(patches.joined(separator: ",\n"))
         ],
         "factoryPatchNames": \(json(factory)),
         "patchAnnouncements": \(json(announcements)),
         "dumpNames": \(json(dumps)),
         "cleanNames": \(json(cleaned)),
         "midiLog": \(json(logLines)),
         "lines": [
        \(lines.map(json).joined(separator: ",\n"))
         ],
         "nrpn": [
        \(nrpn.joined(separator: ",\n"))
         ],
         "settings": [
        \(settings.joined(separator: ",\n"))
         ],
         "parameters": [
        \(params.joined(separator: ",\n"))
         ]
        }

        """
    }
}
