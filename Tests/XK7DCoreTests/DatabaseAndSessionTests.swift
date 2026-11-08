import XCTest
@testable import XK7DCore

final class ParameterDatabaseTests: XCTestCase {
    let db = ParameterDatabase.shared

    func testTableLoadsWithEverySection() {
        XCTAssertEqual(db.parameters.count, 537)
        XCTAssertEqual(Set(db.parameters.map(\.section)), Set(Section.allCases))
        XCTAssertEqual(Set(db.parameters.map(\.id)).count, db.parameters.count, "ids are unique")
    }

    func testEveryNRPNEqualsTheLastTwoAddressBytes() {
        for p in db.parameters {
            guard let n = p.nrpn else { continue }
            XCTAssertEqual(p.baseAddress.bytes[0...2], [0, 0, 0], p.id)
            XCTAssertEqual([n.msb, n.lsb], Array(p.baseAddress.bytes[3...4]).map { $0 }, p.id)
        }
    }

    func testEveryAddressLooksUpToItsOwnParameter() {
        var checked = 0
        for p in db.parameters {
            if p.hasIndices {
                // First, last and a middle choice of every index.
                let picks = p.indices.map { d in [d.options.first!.raw, d.options[d.options.count / 2].raw, d.options.last!.raw] }
                for k in 0..<3 {
                    let iv = picks.map { $0[k] }
                    let s = Setting(p, indexValues: iv)
                    XCTAssertEqual(db.setting(at: s.address)?.parameter.id, p.id, "\(p.id) \(iv)")
                    XCTAssertEqual(db.setting(at: s.address)?.indexValues, iv)
                    checked += 1
                }
            } else {
                XCTAssertEqual(db.setting(at: p.baseAddress)?.parameter.id, p.id)
                checked += 1
            }
            if let n = p.nrpn, !p.hasIndices {
                XCTAssertEqual(db.setting(nrpnMSB: n.msb, lsb: n.lsb)?.parameter.id, p.id)
            }
        }
        XCTAssertGreaterThan(checked, 600)
    }

    func testNoTwoParametersShareAnAddress() {
        var seen: [Address: String] = [:]
        for p in db.parameters where !p.hasIndices {
            XCTAssertNil(seen[p.baseAddress], "\(p.id) and \(seen[p.baseAddress] ?? "") share \(p.baseAddress)")
            seen[p.baseAddress] = p.id
        }
        // An indexed family must not swallow a plain parameter's address.
        for (addr, id) in seen {
            XCTAssertEqual(db.setting(at: addr)?.parameter.id, id)
        }
    }

    func testValuesFitTheirByteLength() {
        for p in db.parameters {
            XCTAssertTrue(p.baseAddress.bytes.allSatisfy { $0 < 0x80 }, "\(p.id) address must be 7-bit")
            if let n = p.nrpn { XCTAssertTrue(n.msb < 0x80 && n.lsb < 0x80, p.id) }
            for d in p.indices {
                XCTAssertTrue(d.options.allSatisfy { Int(p.baseAddress.bytes[d.position]) + $0.raw < 0x80 }, p.id)
            }
        }
        for p in db.parameters where !p.isText {
            let limit = p.length == 1 ? 127 : 16383
            XCTAssertLessThanOrEqual(p.rawRange.upperBound, limit, p.id)
            XCTAssertGreaterThanOrEqual(p.rawRange.lowerBound, 0, p.id)
            XCTAssertTrue([1, 2].contains(p.length), p.id)
            for raw in [p.rawRange.lowerBound, p.rawRange.upperBound] {
                XCTAssertFalse(p.display(raw).hasPrefix("Unknown"), "\(p.id) \(raw)")
            }
        }
    }

    func testIndexedFamiliesUseOnlyManualRanges() {
        let wheel = db.setting(at: Address(0x10, 0, 0, 1, 0x6B))!
        XCTAssertEqual(wheel.spokenName, "Tone wheel level, F96")
        XCTAssertNil(db.setting(at: Address(0x10, 0, 0, 1, 0x6C)), "no tone wheel past 6B")
        XCTAssertEqual(db.setting(at: Address(0x10, 0, 0, 1, 0x18))?.spokenName, "Tone wheel level, number 13")
        XCTAssertEqual(db.setting(at: Address(0x10, 0, 0, 1, 0x0C))?.spokenName, "Tone wheel level, F01")
        XCTAssertNil(db.setting(at: Address(0x11, 0, 0, 0x60, 0)), "leak table stops at 5F")
        XCTAssertNil(db.setting(at: Address(0x11, 2, 0, 0, 0)), "percussion leak footage is 3 or 4 only")
        XCTAssertNotNil(db.setting(at: Address(0x11, 2, 3, 0, 0)))
        XCTAssertNil(db.setting(at: Address(0x13, 1, 3, 0, 0x3D)), "61 keys: 00-3C")
    }

    func testSearchFindsByFriendlyOrManualName() {
        XCTAssertTrue(db.search("leslie horn fast").contains { $0.manualName == "Fast Speed Horn" })
        XCTAssertTrue(db.search("Organ Type").contains { $0.manualName == "Organ Type" })
        XCTAssertTrue(db.search("percussion third").isEmpty == false || db.search("percussion harmonic").count > 0)
        XCTAssertTrue(db.search("master tune").contains { $0.manualName == "Master Tune" })
        XCTAssertEqual(db.search("").count, db.parameters.count)
    }
}

final class ValueFormatTests: XCTestCase {
    let db = ParameterDatabase.shared

    func p(_ a: Address) -> Parameter { db.setting(at: a)!.parameter }

    func testNotesFollowTheDisplay() {
        XCTAssertEqual(NoteName.display(60), "3C")
        XCTAssertEqual(NoteName.display(0), "-2C")
        XCTAssertEqual(NoteName.display(127), "8G")      // "Setting Range: -2C – 8G" (p. 103)
        XCTAssertEqual(NoteName.display(61), "3C#")
        XCTAssertEqual(NoteName.spoken(61), "C sharp 3")
    }

    func testBalanceValues() {
        let pan = p(Address(0, 0, 0, 0x30, 0x0A))
        XCTAssertEqual(pan.display(0), "L64")
        XCTAssertEqual(pan.display(64), "Center")
        XCTAssertEqual(pan.display(127), "R63")
        XCTAssertEqual(pan.spoken(0), "left 64")
        let mix = p(Address(0, 0, 0, 0x12, 0x04))
        XCTAssertEqual(mix.display(0), "D64")
        XCTAssertEqual(mix.display(64), "Even")
        XCTAssertEqual(mix.display(127), "63V")
        XCTAssertEqual(mix.spoken(127), "vibrato 63")
    }

    func testStepsOnlyNameTheEndPoints() {
        let rate = p(Address(0, 0, 0, 0x12, 0x03))
        XCTAssertEqual(rate.display(0), "5.78 Hz")
        XCTAssertEqual(rate.display(127), "7.90 Hz")
        XCTAssertEqual(rate.display(64), "step 64 of 127")
        let rise = p(Address(0x42, 0, 0, 0, 2))
        XCTAssertEqual(rise.display(0), "0.8 sec")
        XCTAssertEqual(rise.display(0x24), "12.5 sec")
    }

    func testOtherDisplays() {
        XCTAssertEqual(p(Address(0, 0, 0, 0x18, 0x01)).display(0x31), "5.0 sec")
        XCTAssertEqual(p(Address(0, 0, 0, 0x18, 0x01)).display(0), "0.1 sec")
        XCTAssertEqual(p(Address(0, 0, 0, 0x18, 0x00)).display(0x28), "-24 semitones")
        XCTAssertEqual(p(Address(0, 0, 0, 0x18, 0x00)).display(0x4C), "+12 semitones")
        XCTAssertEqual(p(Address(0, 0, 0, 0x16, 0x03)).display(0), "-9")
        XCTAssertEqual(p(Address(0, 0, 0, 0x16, 0x03)).display(9), "0")
        XCTAssertEqual(p(Address(0, 0, 0, 0x0D, 0x00)).display(0), "1")
        XCTAssertEqual(p(Address(0, 0, 0, 0x0D, 0x00)).display(16), "Off")
        XCTAssertEqual(p(Address(0, 0, 0, 0x04, 0x04)).display(0), "Off")
        XCTAssertEqual(p(Address(0, 0, 0, 0x04, 0x04)).display(1), "-40 dB")
        XCTAssertEqual(p(Address(0, 0, 0, 0x04, 0x04)).display(0x29), "0 dB")
        XCTAssertEqual(p(Address(0x43, 0, 0, 0, 3)).display(0x0E), "-50 cm")
        XCTAssertEqual(p(Address(0x43, 0, 0, 0, 0)).display(0x4D), "0 dB")
        XCTAssertEqual(p(Address(0x43, 0, 0, 0, 0)).spoken(0), "minus infinity")
        XCTAssertEqual(p(Address(0, 0, 0, 0x1F, 0x09)).display(0x0A), "Continue")
        XCTAssertEqual(p(Address(0, 0, 0, 0x03, 0x00)).display(0x10), "Bass 1C")
        XCTAssertEqual(p(Address(0, 0, 0, 0x03, 0x00)).display(0x28), "Bass 3C")
        XCTAssertEqual(p(Address(0, 0, 0, 0x03, 0x00)).display(0x29), "To Adjust A#")
    }
}

/// The session on its own, fed raw bytes, with a fake clock.
final class OrganSessionTests: XCTestCase {
    var session: OrganSession!
    var now: TimeInterval = 100
    var spoken: [String] = []
    var sent: [[UInt8]] = []
    var events: [(OrganEvent, Bool)] = []

    final class Capture: MIDIOutput {
        var onSend: ([UInt8]) -> Void = { _ in }
        func send(_ bytes: [UInt8]) { onSend(bytes) }
    }
    let out = Capture()

    override func setUp() {
        session = OrganSession(coalescer: AnnouncementCoalescer(settle: 0.3, maxWait: 2))
        session.clock = { [unowned self] in self.now }
        session.onAnnouncement = { [unowned self] in self.spoken.append($0) }
        session.onEvent = { [unowned self] e, echo in self.events.append((e, echo)) }
        out.onSend = { [unowned self] in self.sent.append($0) }
        session.output = out
    }

    func advance(_ dt: TimeInterval) { now += dt; session.tick() }

    func testIncomingNRPNIsAnnounced() {
        session.receive([0xB0, 0x63, 0x10, 0x62, 0x04, 0x06, 0x01])
        XCTAssertEqual(spoken, [])
        advance(0.4)
        XCTAssertEqual(spoken, ["Organ type: Mellow"])
        XCTAssertEqual(session.value(of: session.database.setting(at: Address(0, 0, 0, 0x10, 4))!), 1)
    }

    func testNRPNOnAnotherChannelIsIgnored() {
        session.receive([0xB3, 0x63, 0x10, 0x62, 0x04, 0x06, 0x01])
        advance(1)
        XCTAssertEqual(spoken, [])
    }

    func testIncomingDataSetIsAnnouncedFrontLoaded() {
        session.receive([0xF0, 0x55, 0x00, 0x10, 0x26, 0x13, 0x42, 0, 0, 0, 0, 0x01, 0x0D, 0xF7])
        advance(0.4)
        XCTAssertEqual(spoken, ["Leslie horn fast speed: 340 rpm"])
    }

    func testKnobBurstSpeaksOnceWithTheLatestValue() {
        for v in stride(from: 100, through: 141, by: 1) {
            let b = XK7SysEx.valueBytes(v, length: 2)
            session.receive([0xF0, 0x55, 0x00, 0x10, 0x26, 0x13, 0x42, 0, 0, 0, 0] + b + [0xF7])
            advance(0.03)
        }
        advance(0.4)
        XCTAssertEqual(spoken, ["Leslie horn fast speed: 340 rpm"])
    }

    func testOwnEchoIsNotReannounced() {
        let s = session.database.setting(at: Address(0, 0, 0, 0x11, 0x00))!
        session.set(s, raw: 1)
        XCTAssertEqual(sent.last, [0xF0, 0x55, 0x00, 0x10, 0x26, 0x13, 0, 0, 0, 0x11, 0x00, 0x01, 0xF7])
        session.receive([0xB0, 0x63, 0x11, 0x62, 0x00, 0x06, 0x01])   // the organ repeats it back
        advance(1)
        XCTAssertEqual(spoken, [])
        XCTAssertEqual(events.last?.1, true, "reported as an echo")
        // A different value is not an echo.
        session.receive([0xB0, 0x06, 0x00])
        advance(1)
        XCTAssertEqual(spoken, ["Percussion on: Off"])
        // And the same value much later is a real change.
        session.set(s, raw: 1)
        now += 10
        session.receive([0xB0, 0x63, 0x11, 0x62, 0x00, 0x06, 0x01])
        advance(1)
        XCTAssertEqual(spoken.last, "Percussion on: On")
    }

    func testDrawbarCCAndRegistrationSpeakOnce() {
        session.receive([0xB0, 14, 0x60])                       // Upper 8' to 6 as a CC
        session.receive([0xF0, 0x55, 0, 0x10, 0x26, 0x13, 0, 0, 1, 1, 2, 6, 0xF7])   // and as SysEx
        advance(0.4)
        XCTAssertEqual(spoken, ["Upper 8 foot: 6"])
        // Our own drawbar change echoed as a CC is not spoken.
        let s = session.registrationSetting(part: .lower, index: 3)!
        session.set(s, raw: 4)
        session.receive([0xB0, 24, 0x40])
        advance(1)
        XCTAssertEqual(spoken, ["Upper 8 foot: 6"])
    }

    func testProgramChanges() {
        session.receive([0xB0, 0x00, 0x01, 0xB0, 0x20, 0x00, 0xC0, 0x0F])
        session.receive([0xB1, 0x00, 0x65, 0xC1, 0x69])
        session.receive([0xC2, 0x7F])
        advance(0.4)
        XCTAssertEqual(spoken, ["Upper: patch F15", "Lower: Favorite C sharp-F", "Pedal: Adjust B"])
    }

    func testControllersAndLeslieSpeed() {
        session.receive([0xB0, 0x01, 0x00, 0xB0, 0x31, 0x7F])
        advance(0.4)
        XCTAssertEqual(Set(spoken), ["Leslie speed: slow", "Tone wheel brake: on"])
    }

    func testDataSetCarryingSeveralParameters() {
        // Percussion On, Harmonic, Fast Decay in one Data Set starting at 11 00.
        session.receive([0xF0, 0x55, 0, 0x10, 0x26, 0x13, 0, 0, 0, 0x11, 0x00, 1, 1, 0, 0xF7])
        advance(0.4)
        XCTAssertEqual(spoken, ["Percussion on: On", "Percussion harmonic: Third", "Percussion decay: Slow"])
    }

    func testNamesAndUnknownAddresses() {
        session.receive(XK7SysEx.dataSet(device: 0, address: Address(0, 0, 0x10, 0, 0), data: TextCodec.encode("Jimmy's Blues")))
        session.receive(XK7SysEx.dataSet(device: 0, address: Address(0x7E, 0, 0, 0, 0), data: [1]))
        advance(0.4)
        XCTAssertEqual(spoken, ["Patch name, upper: Jimmy's Blues"])
        XCTAssertTrue(events.contains { if case .unknownAddress = $0.0 { return true } else { return false } })
    }

    func testDeviceIDIsLearnedFromTheOrgan() {
        var learned: UInt8?
        session.onDeviceIDLearned = { learned = $0 }
        session.receive(XK7SysEx.identityReply(device: 0x11))
        XCTAssertEqual(learned, 0x11)
        XCTAssertTrue(session.organAnswered)
        XCTAssertEqual(session.addressing.deviceID, 0x11)
        let s = session.database.setting(at: Address(0, 0, 0, 0x11, 0))!
        XCTAssertEqual(session.set(s, raw: 0)[2], 0x11)
    }

    func testIdentityRequestGoesToOurIDAndAllCall() {
        session.requestIdentity()
        XCTAssertEqual(sent, [[0xF0, 0x7E, 0x00, 0x06, 0x01, 0xF7], [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]])
    }

    func testDumpPacketsAreCollectedAndAcknowledged() {
        session.requestDump(.temporary)
        XCTAssertEqual(sent.last, [0xF0, 0x55, 0x00, 0x10, 0x26, 0x12, 0x07, 0xF7])
        for n in 0..<3 {
            session.receive(XK7SysEx.dataPacket(device: 0, type: 7, packet: n, data64: [UInt8](repeating: UInt8(n), count: 64)))
        }
        XCTAssertEqual(sent.count, 4)
        XCTAssertEqual(sent.last, XK7SysEx.acknowledge(device: 0, type: 7, result: 0, packet: 2))
        let snap = session.finishDump()!
        XCTAssertEqual(snap.count, 3)
        XCTAssertTrue(snap.allChecksumsOK)
        XCTAssertEqual(snap.syxData.count, 3 * 139)
    }

    func testSendingClampsToTheManualRange() {
        let s = session.database.setting(at: Address(0, 0, 0, 0, 0))!   // Master tune 430-450
        let msg = session.set(s, raw: 999)
        XCTAssertEqual(Array(msg[11...12]), [0x03, 0x42])
    }
}
