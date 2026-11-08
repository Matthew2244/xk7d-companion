import XCTest
@testable import XK7DCore

/// Every worked example printed in the manual's MIDI appendix, encoded through the generated
/// parameter table. If one of these fails, the table or the encoder disagrees with the manual.
final class ManualExampleTests: XCTestCase {
    let db = ParameterDatabase.shared
    let dd: UInt8 = 0x10   // any device ID; the manual writes "dd"

    func setting(_ address: Address, file: StaticString = #filePath, line: UInt = #line) -> Setting {
        guard let s = db.setting(at: address) else {
            XCTFail("no parameter at \(address)", file: file, line: line)
            fatalError()
        }
        return s
    }

    func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    func cc(_ m: [MIDIMessage]) -> [UInt8] { m.flatMap(\.bytes) }

    // p. 181: "ex: select Organ Type at Mellow
    //  SysEx: F0 55 dd 10 26 13 00 00 00 10 04 01 F7  NRPN: Bx 63 10 Bx 62 04 Bx 06 01"
    func testOrganTypeMellow() {
        let s = setting(Address(0, 0, 0, 0x10, 0x04))
        XCTAssertEqual(s.parameter.manualName, "Organ Type")
        XCTAssertEqual(s.parameter.display(1), "Mellow")
        XCTAssertEqual(XK7SysEx.dataSet(device: dd, setting: s, raw: 1), bytes("F0 55 10 10 26 13 00 00 00 10 04 01 F7"))
        let n = s.parameter.nrpn!
        XCTAssertEqual(cc(NRPN.messages(channel: 0, msb: n.msb, lsb: n.lsb, raw: 1, length: s.parameter.length)),
                       bytes("B0 63 10 B0 62 04 B0 06 01"))
    }

    // p. 185: "ex: set Master Tune set at 442 Hz
    //  SysEx: F0 55 dd 10 26 13 00 00 00 00 00 03 3A F7  NRPN: Bx 63 00 Bx 62 00 Bx 06 03 Bx 26 3A"
    func testMasterTune442() {
        let s = setting(Address(0, 0, 0, 0, 0))
        XCTAssertEqual(s.parameter.manualName, "Master Tune")
        let raw = 442
        XCTAssertEqual(s.parameter.display(raw), "442 Hz")
        XCTAssertEqual(s.parameter.rawRange, 430...450)    // 03 2E - 03 42
        XCTAssertEqual(XK7SysEx.dataSet(device: dd, setting: s, raw: raw), bytes("F0 55 10 10 26 13 00 00 00 00 00 03 3A F7"))
        XCTAssertEqual(cc(NRPN.messages(channel: 0, msb: 0, lsb: 0, raw: raw, length: 2)),
                       bytes("B0 63 00 B0 62 00 B0 06 03 B0 26 3A"))
        XCTAssertEqual(s.parameter.display(0x03 << 7 | 0x38), "440 Hz")  // 0338 is the centre
    }

    // p. 185: "ex: select Expression Source set at MIDI
    //  SysEx: F0 55 dd 10 26 13 00 00 00 04 00 01 F7  NRPN: Bx 63 04 Bx 62 01 Bx 06 01"
    // The SysEx and the table (Source = NRPN 04 00) agree. The printed NRPN says 62 01, which is the
    // table's "Device" parameter: a misprint in the manual. We follow the table; see PARAMETER-REVIEW.md.
    func testExpressionSourceMIDI() {
        let s = setting(Address(0, 0, 0, 0x04, 0x00))
        XCTAssertEqual(s.parameter.manualName, "Source")
        XCTAssertEqual(s.parameter.display(1), "MIDI")
        XCTAssertEqual(XK7SysEx.dataSet(device: dd, setting: s, raw: 1), bytes("F0 55 10 10 26 13 00 00 00 04 00 01 F7"))
        XCTAssertEqual(cc(NRPN.messages(channel: 0, msb: 4, lsb: 0, raw: 1, length: 1)), bytes("B0 63 04 B0 62 00 B0 06 01"))
        XCTAssertEqual(db.setting(nrpnMSB: 4, lsb: 1)?.parameter.manualName, "Device")
    }

    // p. 185: "Set Upper E-C# at F04 via System Exclusive: F0 55 dd 10 26 13 00 00 00 50 29 00 68 F7"
    func testFavoriteUpperECSharpF04() {
        let s = setting(Address(0, 0, 0, 0x50, 0x29))
        XCTAssertEqual(s.parameter.manualName, "Assign Upper")
        XCTAssertEqual(s.indexValues, [0x29])
        XCTAssertEqual(s.parameter.indices[0].label(for: 0x29), "E-C#")
        XCTAssertEqual(s.parameter.display(0x68), "F04")
        XCTAssertEqual(XK7SysEx.dataSet(device: dd, setting: s, raw: 0x68), bytes("F0 55 10 10 26 13 00 00 00 50 29 00 68 F7"))
        // And the NRPN of an indexed Favorites entry resolves too.
        XCTAssertEqual(db.setting(nrpnMSB: 0x50, lsb: 0x29)?.address, s.address)
    }

    // p. 183: "Set the Matrix Level for Lower, 4', middle C at -12.1[dB]: F0 55 dd 10 26 13 13 01 03 00 18 06 70 F7"
    func testMatrixLevelLower4MiddleC() {
        let s = setting(Address(0x13, 0x01, 0x03, 0x00, 0x18))
        XCTAssertEqual(s.parameter.name, "Lower matrix level")
        XCTAssertEqual(s.parameter.indices.map(\.name), ["Footage", "Key"])
        XCTAssertEqual(s.parameter.indices[0].label(for: s.indexValues[0]), "4'")
        XCTAssertEqual(s.parameter.indices[1].label(for: s.indexValues[1]), "3C (middle C)")
        let raw = 0x06 << 7 | 0x70
        XCTAssertEqual(s.parameter.display(raw), "-12.1 dB")
        XCTAssertEqual(XK7SysEx.dataSet(device: dd, setting: s, raw: raw), bytes("F0 55 10 10 26 13 13 01 03 00 18 06 70 F7"))
    }

    // p. 183: "Assign the Contact for Middle C, Percussion Third at #3: F0 55 00 10 26 13 21 02 00 01 18 02 F7"
    // (the manual prints device 00 here)
    func testContactPercussionThirdMiddleC() {
        let s = setting(Address(0x21, 0x02, 0x00, 0x01, 0x18))
        XCTAssertEqual(s.parameter.name, "Percussion contact leaf")
        XCTAssertEqual(s.parameter.indices[0].label(for: s.indexValues[0]), "Third")
        XCTAssertEqual(s.parameter.display(2), "3")
        XCTAssertEqual(XK7SysEx.dataSet(device: 0, setting: s, raw: 2), bytes("F0 55 00 10 26 13 21 02 00 01 18 02 F7"))
    }

    // p. 183: "Set Drawbar [LOWER 2] at S04 C-Bourdon 1: F0 55 dd 10 26 13 51 00 01 01 00 00 03 F7"
    func testPipeLower2Bourdon() {
        let s = setting(Address(0x51, 0x00, 0x01, 0x01, 0x00))
        XCTAssertEqual(s.parameter.name, "Lower pipe stop")
        XCTAssertEqual(s.parameter.indices[0].label(for: s.indexValues[0]), "5 1/3'")
        XCTAssertEqual(s.parameter.display(3), "S04 C-Bourdon 1")
        XCTAssertEqual(XK7SysEx.dataSet(device: dd, setting: s, raw: 3), bytes("F0 55 10 10 26 13 51 00 01 01 00 00 03 F7"))
    }

    // p. 177: "ex: Set Lower 8' to level 7 via MIDI. Bx 17 70 (x=UPPER Channel)"
    func testDrawbarLower8Level7() {
        XCTAssertEqual(DrawbarCC.controller(part: .lower, index: 2), 0x17)
        XCTAssertEqual(DrawbarCC.value(forLevel: 7), 0x70)
        XCTAssertEqual(DrawbarCC.level(forValue: 0x70), 7)
        XCTAssertEqual(MIDIMessage.controlChange(channel: 0, controller: 0x17, value: 0x70).bytes, bytes("B0 17 70"))
    }

    // p. 176 program change examples.
    func testProgramChangeExamples() {
        // "select Patch# F15 for the Upper Part: Bx 00 01 Bx 20 00 Cx 0F"
        XCTAssertEqual(PatchSelect.describe(bank: 0x01, program: 0x0F), "patch F15")
        // "select Favorite Bank[C#], Key[F] for the Upper Part: Bx 00 65 Bx 20 00 Cx 69"
        XCTAssertEqual(PatchSelect.describe(bank: 0x65, program: 0x69), "Favorite C#-F")
        // "select Adjust [B] for the Upper Part: Cx 7F"
        XCTAssertEqual(PatchSelect.describe(bank: nil, program: 0x7F), "Adjust B")
        XCTAssertEqual(PatchSelect.describe(bank: 0, program: 7), "patch U07")
    }

    // The signed two-byte forms printed in the tables.
    func testSignedTwoByteRanges() {
        let oct = setting(Address(0, 0, 0, 0x1A, 0x00))
        XCTAssertEqual(oct.parameter.rawRange, (0x3F << 7 | 0x7E)...(0x40 << 7 | 0x02))
        XCTAssertEqual(oct.parameter.display(0x3F << 7 | 0x7E), "-2 octaves")
        XCTAssertEqual(oct.parameter.display(0x40 << 7), "0 octaves")
        XCTAssertEqual(oct.parameter.display(0x40 << 7 | 0x01), "+1 octave")
        XCTAssertEqual(XK7SysEx.valueBytes(0x3F << 7 | 0x7E, length: 2), [0x3F, 0x7E])

        let transpose = setting(Address(0, 0, 0, 0, 1))
        XCTAssertEqual(transpose.parameter.rawRange, (0x3F << 7 | 0x7A)...(0x40 << 7 | 0x06))
        XCTAssertEqual(transpose.parameter.display(0x3F << 7 | 0x7A), "-6 semitones")

        let vel = setting(Address(0, 0, 0, 0x09, 0x00))
        XCTAssertEqual(vel.parameter.display(0x3F << 7 | 0x71), "-15")
        XCTAssertEqual(vel.parameter.display(0x40 << 7 | 0x0F), "+15")

        let detune = setting(Address(0x51, 0, 0, 0, 3))
        XCTAssertEqual(detune.parameter.display(0x3F << 7 | 0x4E), "-50 cents")
        XCTAssertEqual(detune.parameter.display(0x40 << 7 | 0x32), "+50 cents")

        let cutoff = setting(Address(0x51, 0, 0, 0, 6))
        XCTAssertEqual(cutoff.parameter.display(0x3F << 7 | 0x01), "-127")
        XCTAssertEqual(cutoff.parameter.display(0x40 << 7), "0")
    }

    // Two-byte unsigned ranges printed as MSB LSB pairs.
    func testTwoByteUnsignedRanges() {
        let fast = setting(Address(0x42, 0, 0, 0, 0))
        XCTAssertEqual(fast.parameter.rawRange, 0...(0x02 << 7 | 0x2D))
        XCTAssertEqual(fast.parameter.display(0), "0 rpm")
        XCTAssertEqual(fast.parameter.display(1), "200 rpm")
        XCTAssertEqual(fast.parameter.display(0x02 << 7 | 0x2D), "500 rpm")
        let slow = setting(Address(0x42, 0, 0, 1, 1))
        XCTAssertEqual(slow.parameter.display(0x65), "120 rpm")
        let angle = setting(Address(0x42, 0, 0, 0, 6))
        XCTAssertEqual(angle.parameter.display(0x02 << 7 | 0x67), "359 degrees")
        XCTAssertEqual(angle.parameter.display(0x02 << 7 | 0x68), "Random")
        let level = setting(Address(0x10, 0, 0, 0, 6))
        XCTAssertEqual(level.parameter.display(0), "-inf")
        XCTAssertEqual(level.parameter.display(1), "-100.0 dB")
        XCTAssertEqual(level.parameter.display(0x08 << 7 | 0x11), "+4.0 dB")
        let pipeVol = setting(Address(0x51, 0, 0, 0, 1))
        XCTAssertEqual(pipeVol.parameter.display(0x01 << 7 | 0x41), "+4.0 dB")
        XCTAssertEqual(pipeVol.parameter.display(1), "-92.0 dB")
        let fav = setting(Address(0, 0, 0, 0x51, 0))
        XCTAssertEqual(fav.parameter.display(0x00 << 7 | 0x63), "U99")
        XCTAssertEqual(fav.parameter.display(0x00 << 7 | 0x64), "F00")
        XCTAssertEqual(fav.parameter.display(0x01 << 7 | 0x47), "F99")
        let dist = setting(Address(0x43, 0, 0, 0, 4))
        XCTAssertEqual(dist.parameter.rawRange, 0x1E...(0x01 << 7 | 0x48))
    }
}
