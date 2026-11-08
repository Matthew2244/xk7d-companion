import XCTest
@testable import XK7DCore

final class SysExCodecTests: XCTestCase {
    func testNibblizeMatchesManualExample() {
        // "128 Bytes nibblized ASCII, ex: 7EH = 37H, 45H"
        XCTAssertEqual(XK7SysEx.nibblize([0x7E]), [0x37, 0x45])
        XCTAssertEqual(XK7SysEx.denibblize([0x37, 0x45]), [0x7E])
        let all = (0...255).map { UInt8($0) }
        XCTAssertEqual(XK7SysEx.denibblize(XK7SysEx.nibblize(all)), all)
        XCTAssertNil(XK7SysEx.denibblize([0x37]))
        XCTAssertNil(XK7SysEx.denibblize([0x37, 0x5A]))
    }

    func testCheckDigitIsLowSevenBitsOfXor() {
        XCTAssertEqual(XK7SysEx.checkDigit([0x30, 0x41]), 0x71)
        XCTAssertEqual(XK7SysEx.checkDigit([0x7F, 0x7F]), 0)
        XCTAssertEqual(XK7SysEx.checkDigit([0x46, 0x46, 0x46]), 0x46)
    }

    func testDataPacketIs139BytesAndRoundTrips() {
        let data = (0..<64).map { UInt8($0 * 3 & 0xFF) }
        let p = XK7SysEx.dataPacket(device: 0x05, type: 0x07, packet: 3, data64: data)
        XCTAssertEqual(p.count, 139)
        XCTAssertEqual(Array(p.prefix(9)), [0xF0, 0x55, 0x05, 0x10, 0x26, 0x11, 0x07, 0x00, 0x03])
        XCTAssertTrue(p.dropFirst().dropLast().allSatisfy { $0 < 0x80 }, "SysEx body must be 7-bit")
        guard case .dataPacket(let dev, let type, let pn, let decoded, let ok, let note) = XK7Inbound.decode(p) else {
            return XCTFail("not decoded as a data packet")
        }
        XCTAssertEqual(dev, 5); XCTAssertEqual(type, 7); XCTAssertEqual(pn, 3)
        XCTAssertEqual(decoded, data); XCTAssertTrue(ok); XCTAssertEqual(note, "XOR of nibblized data")
        var bad = p
        bad[137] ^= 0x01
        if case .dataPacket(_, _, _, _, let ok2, _) = XK7Inbound.decode(bad) { XCTAssertFalse(ok2) } else { XCTFail() }
    }

    func testOtherMessagesAsPrinted() {
        XCTAssertEqual(XK7SysEx.dumpRequest(device: 0, type: .temporary), [0xF0, 0x55, 0x00, 0x10, 0x26, 0x12, 0x07, 0xF7])
        XCTAssertEqual(XK7SysEx.dumpRequest(device: 0, type: .system), [0xF0, 0x55, 0x00, 0x10, 0x26, 0x12, 0x0A, 0xF7])
        XCTAssertEqual(XK7SysEx.nrpnSwitch(device: 0, mode: .sysex), [0xF0, 0x55, 0x00, 0x10, 0x26, 0x02, 0x02, 0xF7])
        XCTAssertEqual(XK7SysEx.acknowledge(device: 0, type: 7, result: 0, packet: 130),
                       [0xF0, 0x55, 0x00, 0x10, 0x26, 0x14, 0x07, 0x00, 0x01, 0x02, 0xF7])
        XCTAssertEqual(XK7SysEx.identityRequest(device: 0x7F), [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7])
        XCTAssertEqual(XK7SysEx.identityReply(device: 0),
                       [0xF0, 0x7E, 0x00, 0x06, 0x02, 0x55, 0x00, 0x10, 0x00, 0x26, 0x00, 0x00, 0x00, 0x00, 0xF7])
        XCTAssertEqual(XK7Inbound.decode(XK7SysEx.identityReply(device: 3)),
                       .identityReply(device: 3, manufacturer: 0x55, family: [0, 0x10], member: [0, 0x26]))
        XCTAssertEqual(XK7Inbound.decode([0xF0, 0x55, 0x00, 0x10, 0x26, 0x13, 0, 0, 0, 0x10, 0x04, 0x01, 0xF7]),
                       .dataSet(device: 0, address: Address(0, 0, 0, 0x10, 4), data: [1]))
        XCTAssertEqual(XK7Inbound.decode([0xF0, 0x43, 0x10, 0xF7]), .unknown([0xF0, 0x43, 0x10, 0xF7]))
        // A different model's ID must not be read as ours.
        XCTAssertEqual(XK7Inbound.decode([0xF0, 0x55, 0x00, 0x10, 0x25, 0x13, 0, 0, 0, 0x10, 0x04, 0x01, 0xF7]),
                       .unknown([0xF0, 0x55, 0x00, 0x10, 0x25, 0x13, 0, 0, 0, 0x10, 0x04, 0x01, 0xF7]))
    }

    func testValueBytePacking() {
        XCTAssertEqual(XK7SysEx.valueBytes(5, length: 1), [5])
        XCTAssertEqual(XK7SysEx.valueBytes(442, length: 2), [0x03, 0x3A])
        XCTAssertEqual(XK7SysEx.valueBytes(1041, length: 2), [0x08, 0x11])
        XCTAssertEqual(XK7SysEx.value(from: [0x03, 0x3A]), 442)
        XCTAssertEqual(XK7SysEx.value(from: [0x7F]), 127)
        for v in stride(from: 0, through: 16383, by: 97) {
            XCTAssertEqual(XK7SysEx.value(from: ArraySlice(XK7SysEx.valueBytes(v, length: 2))), v)
        }
    }

    func testTextCodec() {
        XCTAssertEqual(TextCodec.encode("Jimmy"), Array("Jimmy           ".utf8))
        XCTAssertEqual(TextCodec.encode("A name that is far too long").count, 16)
        XCTAssertEqual(TextCodec.encode("Café")[3], UInt8(ascii: "?"))
        XCTAssertEqual(TextCodec.decode(Array("Jimmy           ".utf8)), "Jimmy")
    }
}

final class ByteParserTests: XCTestCase {
    func testRunningStatusNRPN() {
        var p = MIDIByteParser()
        // The manual's Organ Type example with running status: B0 63 10 62 04 06 01
        let m = p.feed([0xB0, 0x63, 0x10, 0x62, 0x04, 0x06, 0x01])
        XCTAssertEqual(m, [.controlChange(channel: 0, controller: 0x63, value: 0x10),
                           .controlChange(channel: 0, controller: 0x62, value: 0x04),
                           .controlChange(channel: 0, controller: 0x06, value: 0x01)])
    }

    func testMessagesSplitAcrossPacketsAndRealTimeInterleaved() {
        var p = MIDIByteParser()
        var out: [MIDIMessage] = []
        out += p.feed([0xF0, 0x55, 0x00, 0x10])
        out += p.feed([0xF8, 0x26, 0x13, 0, 0, 0])      // clock byte inside SysEx
        out += p.feed([0x10, 0x04, 0x01, 0xF7, 0xB1, 0x0E])
        out += p.feed([0xFE, 0x7F])                      // active sensing inside a CC
        XCTAssertEqual(out, [.other([0xF8]),
                             .sysex([0xF0, 0x55, 0x00, 0x10, 0x26, 0x13, 0, 0, 0, 0x10, 0x04, 0x01, 0xF7]),
                             .other([0xFE]),
                             .controlChange(channel: 1, controller: 0x0E, value: 0x7F)])
    }

    func testProgramChangeAndNotes() {
        var p = MIDIByteParser()
        XCTAssertEqual(p.feed([0xC2, 0x0F, 0x10]), [.programChange(channel: 2, program: 15), .programChange(channel: 2, program: 16)])
        XCTAssertEqual(p.feed([0x90, 60, 0]), [.noteOff(channel: 0, note: 60, velocity: 0)])
        XCTAssertEqual(p.feed([0x90, 60, 100, 62, 90]), [.noteOn(channel: 0, note: 60, velocity: 100),
                                                         .noteOn(channel: 0, note: 62, velocity: 90)])
    }

    func testUnterminatedSysExIsDropped() {
        var p = MIDIByteParser()
        XCTAssertEqual(p.feed([0xF0, 0x55, 0x00, 0xB0, 0x07, 0x40]), [.controlChange(channel: 0, controller: 7, value: 0x40)])
    }
}

final class NRPNDecoderTests: XCTestCase {
    let db = ParameterDatabase.shared
    func decoder() -> NRPNDecoder { NRPNDecoder { [db] m, l in db.setting(nrpnMSB: m, lsb: l)?.parameter.length } }

    func feed(_ d: inout NRPNDecoder, _ pairs: [(Int, Int)]) -> [NRPNDecoder.Value] {
        pairs.compactMap { d.handle(controller: $0.0, value: $0.1) }
    }

    func testOneByteParameterCompletesOnDataEntryMSB() {
        var d = decoder()
        XCTAssertEqual(feed(&d, [(99, 0x10), (98, 0x04), (6, 0x01)]), [.init(msb: 0x10, lsb: 0x04, raw: 1)])
        // Data entry again on the same NRPN: another value.
        XCTAssertEqual(feed(&d, [(6, 0x03)]), [.init(msb: 0x10, lsb: 0x04, raw: 3)])
    }

    func testTwoByteParameterWaitsForLSB() {
        var d = decoder()
        XCTAssertEqual(feed(&d, [(99, 0), (98, 0), (6, 3)]), [])
        XCTAssertEqual(feed(&d, [(38, 0x3A)]), [.init(msb: 0, lsb: 0, raw: 442)])
        // A further fine change sends only the LSB.
        XCTAssertEqual(feed(&d, [(38, 0x3B)]), [.init(msb: 0, lsb: 0, raw: 443)])
    }

    func testTwoByteParameterWithoutLSBNeverGuesses() {
        var d = decoder()
        XCTAssertEqual(feed(&d, [(99, 0), (98, 0), (6, 3), (99, 0x11), (98, 0), (6, 1)]), [.init(msb: 0x11, lsb: 0, raw: 1)])
    }

    func testNullAndResetAndUnknown() {
        var d = decoder()
        XCTAssertEqual(feed(&d, [(99, 0x10), (98, 0x04), (99, 127), (98, 127), (6, 1)]), [])
        XCTAssertEqual(feed(&d, [(99, 0x10), (98, 0x04), (121, 0), (6, 1)]), [])
        XCTAssertEqual(feed(&d, [(99, 0x7E), (98, 0x7E), (6, 1)]), [], "an NRPN not in the manual is ignored")
        XCTAssertEqual(feed(&d, [(99, 0x10), (98, 0x04), (101, 0), (6, 1)]), [], "RPN selection cancels NRPN")
    }

    func testOrderMSBThenLSBOrLSBThenMSB() {
        var d = decoder()
        XCTAssertEqual(feed(&d, [(98, 0x04), (99, 0x10), (6, 2)]), [.init(msb: 0x10, lsb: 0x04, raw: 2)])
    }
}

final class DrawbarBucketTests: XCTestCase {
    // p. 177: 00-0F 0, 10-1F 1, 20-2F 2, 30-3F 3, 40-4F 4, 50-5F 5, 60-6F 6, 70-7E 7, 7F 8.
    func testEveryValueLandsInTheManualsBucket() {
        let buckets: [(ClosedRange<Int>, Int)] = [(0...15, 0), (16...31, 1), (32...47, 2), (48...63, 3), (64...79, 4),
                                                  (80...95, 5), (96...111, 6), (112...126, 7), (127...127, 8)]
        for (range, level) in buckets {
            for v in range { XCTAssertEqual(DrawbarCC.level(forValue: v), level, "value \(v)") }
        }
        for level in 0...8 { XCTAssertEqual(DrawbarCC.level(forValue: DrawbarCC.value(forLevel: level)), level) }
    }

    func testControllerMap() {
        XCTAssertEqual(DrawbarCC.drawbar(forController: 12)?.part, .upper)
        XCTAssertEqual(DrawbarCC.drawbar(forController: 20)?.index, 8)
        XCTAssertEqual(DrawbarCC.drawbar(forController: 21)?.part, .lower)
        XCTAssertEqual(DrawbarCC.drawbar(forController: 33)?.part, .pedal)
        XCTAssertEqual(DrawbarCC.drawbar(forController: 35)?.index, 1)
        XCTAssertNil(DrawbarCC.drawbar(forController: 34))
        XCTAssertNil(DrawbarCC.drawbar(forController: 11))
        for part in [DrawbarCC.Part.upper, .lower] {
            for i in 0..<9 { XCTAssertEqual(DrawbarCC.drawbar(forController: DrawbarCC.controller(part: part, index: i))?.index, i) }
        }
    }
}

final class CoalescerTests: XCTestCase {
    func testBurstSpeaksOnlyTheLatestAfterSettling() {
        let c = AnnouncementCoalescer(settle: 0.3, maxWait: 5)
        for i in 0..<20 { c.submit(key: "horn", text: "Horn fast speed: \(300 + i) rpm", at: Double(i) * 0.05) }
        XCTAssertEqual(c.due(at: 1.0), [])             // last change at 0.95, not settled yet
        XCTAssertEqual(c.due(at: 1.26), ["Horn fast speed: 319 rpm"])
        XCTAssertEqual(c.due(at: 5), [])
    }

    func testSeparateSettingsEachSpeakInOrder() {
        let c = AnnouncementCoalescer(settle: 0.3, maxWait: 5)
        c.submit(key: "a", text: "A 1", at: 0)
        c.submit(key: "b", text: "B 1", at: 0.1)
        c.submit(key: "a", text: "A 2", at: 0.2)
        XCTAssertEqual(c.due(at: 0.45), ["B 1"])
        XCTAssertEqual(c.due(at: 0.6), ["A 2"])
    }

    func testLongSweepIsNotSilent() {
        let c = AnnouncementCoalescer(settle: 0.3, maxWait: 1.0)
        var spoken: [String] = []
        var t = 0.0
        while t < 2.5 {
            c.submit(key: "k", text: "v\(Int(t * 10))", at: t)
            spoken += c.due(at: t)
            t += 0.1
        }
        XCTAssertGreaterThanOrEqual(spoken.count, 2)
        XCTAssertLessThanOrEqual(spoken.count, 3)
    }

    func testCancelAndFlush() {
        let c = AnnouncementCoalescer()
        c.submit(key: "a", text: "A", at: 0)
        c.submit(key: "b", text: "B", at: 0)
        c.cancel(key: "a")
        XCTAssertEqual(c.flush(), ["B"])
        XCTAssertTrue(c.isEmpty)
    }
}
