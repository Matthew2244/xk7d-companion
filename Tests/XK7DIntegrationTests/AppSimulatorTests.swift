import XCTest
import CoreMIDI
@testable import XK7DCore
@testable import XK7DCoreMIDI

/// Shared checks run over two transports: the in-process loopback, and real CoreMIDI through the
/// simulator's virtual ports. Announcements are captured through the session's test hook.
class SimulatorScenario: XCTestCase {
    var session: OrganSession!
    var organ: SimulatedOrgan!
    var spoken: [String] = []
    let db = ParameterDatabase.shared

    func setting(_ a: Address) -> Setting { db.setting(at: a)! }

    /// Spin the main run loop until `condition` holds, ticking the session as the app's timer would.
    @discardableResult
    func waitUntil(_ timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            session.tick()
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        session.tick()
        return condition()
    }

    func runScenario() {
        // 1. A change made in the app reaches the organ.
        let organType = setting(Address(0, 0, 0, 0x10, 0x04))
        session.set(organType, raw: 5)
        XCTAssertTrue(waitUntil { self.organ.value(organType) == 5 }, "simulator stored Organ Type = Pipe")
        let name = setting(Address(0, 0, 0x10, 0, 0))
        session.set(name, text: "Gospel Shout")
        XCTAssertTrue(waitUntil { self.organ.texts[name.address] == "Gospel Shout" })
        let wheel = Setting(db.setting(at: Address(0x10, 0, 0, 1, 0))!.parameter, indexValues: [0x18])
        session.set(wheel, raw: 900)
        XCTAssertTrue(waitUntil { self.organ.value(wheel) == 900 }, "indexed SysEx-only parameter")

        // 2. The organ answers who it is.
        session.requestIdentity()
        XCTAssertTrue(waitUntil { self.session.organAnswered })

        // 3. A panel change in SysEx mode is announced, name first.
        organ.individualMode = .sysex
        let hornFast = setting(Address(0x42, 0, 0, 0, 0))
        organ.panelChange(hornFast, raw: 141)
        XCTAssertTrue(waitUntil { self.spoken.contains("Leslie horn fast speed: 340 rpm") }, "spoken: \(spoken)")

        // 4. A knob turned through many values: one announcement, the final value.
        spoken.removeAll()
        for v in organ.knobSweep(hornFast, to: 201, steps: 30) { organ.panelChange(hornFast, raw: v) }
        XCTAssertTrue(waitUntil { !self.spoken.isEmpty })
        RunLoop.main.run(until: Date().addingTimeInterval(0.6)); session.tick()
        XCTAssertEqual(spoken, ["Leslie horn fast speed: 400 rpm"])

        // 5. In NRPN mode (the template default), NRPN parameters are announced too...
        spoken.removeAll()
        organ.individualMode = .nrpn
        let percussion = setting(Address(0, 0, 0, 0x11, 0x01))
        organ.panelChange(percussion, raw: 1)
        XCTAssertTrue(waitUntil { self.spoken == ["Percussion harmonic: Third"] }, "spoken: \(spoken)")
        let tune = setting(Address(0, 0, 0, 0, 0))
        organ.panelChange(tune, raw: 442)
        XCTAssertTrue(waitUntil { self.spoken.last == "Master tune: 442 Hz" }, "two-byte NRPN; spoken: \(spoken)")
        // ...but SysEx-only parameters cannot travel as NRPN, so nothing arrives for them.
        spoken.removeAll()
        organ.panelChange(hornFast, raw: 50)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6)); session.tick()
        XCTAssertEqual(spoken, [])

        // 6. Drawbars and patches.
        organ.panelChange(setting(Address(0, 0, 1, 1, 2)), raw: 6)
        XCTAssertTrue(waitUntil { self.spoken.contains("Upper 8 foot: 6") }, "spoken: \(spoken)")
        organ.selectPatch(part: "Lower", bankMSB: 1, program: 15)
        XCTAssertTrue(waitUntil { self.spoken.contains("Lower: patch F15") }, "spoken: \(spoken)")

        // 7. Our own change coming straight back is not re-announced.
        spoken.removeAll()
        organ.individualMode = .sysex
        let reverb = setting(Address(0, 0, 0, 0x17, 0x07))
        session.set(reverb, raw: 5)
        organ.panelChange(reverb, raw: 5)     // the organ echoing it
        RunLoop.main.run(until: Date().addingTimeInterval(0.6)); session.tick()
        XCTAssertEqual(spoken, [])
        XCTAssertEqual(session.value(of: reverb), 5)

        // 8. Memory dump: 6 + 11 packets, checksums good, every packet acknowledged.
        session.requestDump(.temporary)
        XCTAssertTrue(waitUntil { (self.session.currentDump?.count ?? 0) == 17 })
        XCTAssertTrue(session.currentDump!.allChecksumsOK)
        XCTAssertTrue(waitUntil { self.organ.acknowledgements == 17 })
        let snap = session.finishDump()!
        XCTAssertEqual(snap.packets.filter { $0.type == 7 }.count, 6)
        XCTAssertEqual(snap.packets.filter { $0.type == 8 }.count, 11)
    }
}

final class LoopbackTests: SimulatorScenario {
    var link: LoopbackLink!

    override func setUp() {
        session = OrganSession(coalescer: AnnouncementCoalescer(settle: 0.25, maxWait: 3))
        session.onAnnouncement = { [unowned self] in self.spoken.append($0) }
        organ = SimulatedOrgan()
        link = LoopbackLink(session: session, organ: organ)
    }

    func testAppAndSimulatorInProcess() { runScenario() }

    func testDeviceIDMismatchIsIgnoredLikeTheOrgan() {
        organ.deviceID = 5
        session.addressing.deviceID = 0
        let s = setting(Address(0, 0, 0, 0x11, 0))
        session.set(s, raw: 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(organ.value(s), 0, "the organ ignores a Data Set for another device ID (p. 157)")
        // The identity request also goes out on all-call, so the app learns the real ID...
        session.requestIdentity()
        XCTAssertTrue(waitUntil { self.session.addressing.deviceID == 5 })
        // ...and from then on its changes land.
        session.set(s, raw: 1)
        XCTAssertTrue(waitUntil { self.organ.value(s) == 1 })
    }

    func testSetupForThisAppSwitchesTheOrganToSysEx() {
        let mode = setting(Address(0, 0, 0, 0x0C, 0x03))
        session.set(mode, raw: 2)
        XCTAssertTrue(waitUntil { self.organ.individualMode == .sysex })
        organ.panelChange(setting(Address(0x41, 0, 0, 0, 0)), raw: 4)
        XCTAssertTrue(waitUntil { self.spoken.contains("Leslie speaker: 122 Front") }, "spoken: \(spoken)")
    }
}

final class CoreMIDITests: SimulatorScenario {
    var ports: VirtualSimulatorPorts!
    var connection: CoreMIDIConnection!

    override func setUpWithError() throws {
        session = OrganSession(coalescer: AnnouncementCoalescer(settle: 0.25, maxWait: 3))
        session.onAnnouncement = { [unowned self] in self.spoken.append($0) }
        organ = SimulatedOrgan()
        do {
            ports = try VirtualSimulatorPorts(organ: organ, name: "XK-7D Simulator test \(UUID().uuidString.prefix(6))")
            connection = try CoreMIDIConnection(name: "XK-7D Companion tests")
        } catch {
            throw XCTSkip("CoreMIDI is not available here: \(error)")
        }
        // Connect only to the simulator's own ports, found by unique ID; never to any real device.
        // No pause here: the app connects the moment it creates the ports, and so must the test.
        let src = CoreMIDIConnection.sources().first { $0.uniqueID == ports.sourceID }
        let dst = CoreMIDIConnection.destinations().first { $0.uniqueID == ports.destinationID }
        guard let src, let dst else { throw XCTSkip("simulator ports did not appear") }
        try connection.connect(source: src, destination: dst)
        connection.onReceive = { [unowned self] in self.session.receive($0) }
        session.output = connection
    }

    override func tearDown() {
        connection?.disconnect()
        connection = nil
        ports = nil
    }

    func testAppAndSimulatorOverCoreMIDI() { runScenario() }

    func testLongSysExSurvivesCoreMIDI() {
        // A 139-byte dump packet is longer than one CoreMIDI packet chunk of this app (256 is fine,
        // but check reassembly anyway with several back to back).
        session.requestDump(.system)
        XCTAssertTrue(waitUntil { (self.session.currentDump?.count ?? 0) == 13 })
        XCTAssertTrue(session.currentDump!.allChecksumsOK)
    }
}
