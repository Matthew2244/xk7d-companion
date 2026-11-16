import XCTest
@testable import XK7DCore

/// What is said, kept short for listening while playing.
final class SpeechLineTests: XCTestCase {
    var session: OrganSession!
    var now: TimeInterval = 100
    var spoken: [String] = []
    var urgent: [String] = []

    override func setUp() {
        session = OrganSession(coalescer: AnnouncementCoalescer(settle: 0.3, maxWait: 2))
        session.clock = { [unowned self] in self.now }
        session.onAnnouncement = { [unowned self] in self.spoken.append($0) }
        session.onUrgentAnnouncement = { [unowned self] in self.urgent.append($0) }
    }

    func nrpn(_ msb: UInt8, _ lsb: UInt8, _ v: UInt8) { session.receive([0xB0, 0x63, msb, 0x62, lsb, 0x06, v]) }

    func testLeslieSpeedIsOneWordAndSaidAtOnce() {
        nrpn(0x12, 0x0A, 1)
        XCTAssertEqual(urgent, ["Fast"], "no waiting for the coalescer")
        nrpn(0x12, 0x0A, 0)
        XCTAssertEqual(urgent.last, "Slow")
        nrpn(0x12, 0x09, 1)               // [STOP] lit while slow: the rotors stop
        XCTAssertEqual(urgent.last, "Stop")
        nrpn(0x12, 0x0A, 1)
        XCTAssertEqual(urgent.last, "Fast")
        nrpn(0x12, 0x0A, 0)               // [FAST] toggles between Fast and Stop now
        XCTAssertEqual(urgent.last, "Stop")
        nrpn(0x12, 0x0A, 1)
        nrpn(0x12, 0x09, 0)               // the mode, while fast
        XCTAssertEqual(urgent.last, "Stop mode off")
        now += 1; session.tick()
        XCTAssertEqual(spoken, [], "nothing said twice through the normal path")
    }

    func testLeslieFastControlChange() {
        session.receive([0xB0, 92, 127])
        session.receive([0xB0, 92, 0])
        XCTAssertEqual(urgent, ["Fast", "Slow"])
    }

    func testLeslieFallsBackToTheNormalCallback() {
        session.onUrgentAnnouncement = nil
        nrpn(0x12, 0x0A, 1)
        XCTAssertEqual(spoken, ["Fast"])
    }

    func testOwnLeslieChangeEchoedIsNotSaid() {
        let fast = session.database.setting(at: Address(0, 0, 0, 0x12, 0x0A))!
        session.set(fast, raw: 1)
        nrpn(0x12, 0x0A, 1)
        XCTAssertEqual(urgent, [])
    }

    func testOffOnSettingsAreSaidShort() {
        let db = session.database
        func line(_ a: Address, _ raw: Int) -> String { OrganSession.line(db.setting(at: a)!, raw: raw) }
        XCTAssertEqual(line(Address(0, 0, 0, 0x11, 0x00), 1), "Percussion on")
        XCTAssertEqual(line(Address(0, 0, 0, 0x11, 0x00), 0), "Percussion off")
        XCTAssertEqual(line(Address(0, 0, 0, 0x12, 0x08), 1), "Leslie bypass on")
        XCTAssertEqual(line(Address(0, 0, 0, 0x30, 0x00), 0), "External zone Upper 1 off")
        XCTAssertEqual(line(Address(0, 0, 0, 0x10, 0x04), 1), "Organ type: Mellow")
    }

    func testDrawbarSpeechCanBeTurnedOff() {
        session.receive([0xB0, 14, 0x60])                       // Upper 8' as a CC
        session.speakDrawbars = false                            // turned off while it waits: dropped
        session.receive([0xB0, 0x23, 0x7F])                      // Pedal 8' as a CC
        session.receive([0xF0, 0x55, 0, 0x10, 0x26, 0x13, 0, 0, 1, 2, 3, 5, 0xF7])   // Lower 4' as SysEx
        nrpn(0x11, 0x00, 1)                                      // percussion is still said
        now += 1; session.tick()
        XCTAssertEqual(spoken, ["Percussion on"])
        XCTAssertEqual(session.drawbars["Pedal.1"], 8, "still tracked")
        XCTAssertEqual(session.value(of: session.registrationSetting(part: .lower, index: 3)!), 5)
        session.speakDrawbars = true
        session.receive([0xB0, 14, 0x20])
        now += 1; session.tick()
        XCTAssertEqual(spoken.last, "Upper 8 foot: 2")
    }

    func testOrganInNRPNModeIsNoticedOnce() {
        var told = 0
        session.onNRPNModeNoticed = { told += 1 }
        nrpn(0x10, 0x04, 1)
        nrpn(0x10, 0x04, 2)
        XCTAssertEqual(told, 1)
        session.resetConnection()
        session.receive(XK7SysEx.dataSet(device: 0, setting: session.database.setting(at: Address(0, 0, 0, 0x10, 0x04))!, raw: 1))
        nrpn(0x10, 0x04, 2)
        XCTAssertEqual(told, 1)
    }
}

/// Every setting the manual lists is said when it arrives, the way the organ sends it: as a SysEx
/// Data Set (Individual Parameters: SysEx, which every setting can travel as) and, for settings with
/// an NRPN, as NRPN on the Upper channel (Individual Parameters: NRPN).
final class EverySettingSpeaksTests: XCTestCase {
    func check(viaNRPN: Bool) -> (checked: Int, silent: [String]) {
        let db = ParameterDatabase.shared
        var silent: [String] = []
        var checked = 0
        for p in db.parameters {
            if viaNRPN && p.nrpn == nil { continue }
            for indices in CoreVectors.samples(p) {
                var now: TimeInterval = 100
                var said: [String] = []
                let session = OrganSession(coalescer: AnnouncementCoalescer(settle: 0.3, maxWait: 2))
                session.clock = { now }
                session.onAnnouncement = { said.append($0) }
                session.onUrgentAnnouncement = { said.append($0) }
                let s = Setting(p, indexValues: indices)
                if viaNRPN {
                    let n = p.nrpn!
                    let raw = p.rawRange.upperBound
                    for m in NRPN.messages(channel: 0, msb: n.msb, lsb: n.lsb, raw: raw, length: p.length) { session.receive(m.bytes) }
                } else if p.isText {
                    session.receive(XK7SysEx.dataSet(device: 0, setting: s, text: "Jazz"))
                } else {
                    session.receive(XK7SysEx.dataSet(device: 0, setting: s, raw: p.rawRange.upperBound))
                }
                now += 1; session.tick()
                checked += 1
                let expectedStart = s.spokenName.prefix(6)
                if said.count != 1 || !(said[0].hasPrefix(expectedStart) || ["Fast", "Slow", "Stop"].contains(said[0])
                                         || said[0].contains("foot")) {
                    silent.append("\(p.id) \(indices): \(said)")
                }
            }
        }
        return (checked, silent)
    }

    func testEverySettingArrivingAsSysExIsSaid() {
        let r = check(viaNRPN: false)
        XCTAssertEqual(r.silent, [])
        XCTAssertGreaterThan(r.checked, 3000)
    }

    func testEverySettingWithAnNRPNArrivingAsNRPNIsSaid() {
        let r = check(viaNRPN: true)
        XCTAssertEqual(r.silent, [])
        XCTAssertGreaterThan(r.checked, 300)
    }
}
