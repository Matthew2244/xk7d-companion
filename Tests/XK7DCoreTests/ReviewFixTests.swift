import XCTest
@testable import XK7DCore

/// Tests for the 1.0.1 review: port choice, patch-recall floods, typed names, vibrato order.
final class PortPolicyTests: XCTestCase {
    func testLooksLikeOrgan() {
        XCTAssertTrue(PortPolicy.looksLikeOrgan("XK-7D"))
        XCTAssertTrue(PortPolicy.looksLikeOrgan("Hammond XK 7 USB MIDI"))
        XCTAssertTrue(PortPolicy.looksLikeOrgan("SUZUKI MIDI"))
        XCTAssertFalse(PortPolicy.looksLikeOrgan("IAC Driver Bus 1"))
    }

    func testRememberedPortWinsWhenPresent() {
        XCTAssertEqual(PortPolicy.launchChoice(remembered: "My Interface", devices: ["XK-7D", "My Interface"]),
                       .device("My Interface"))
    }

    func testAPluggedInOrganBeatsARememberedSimulator() {
        XCTAssertEqual(PortPolicy.launchChoice(remembered: "simulator", devices: ["IAC Driver Bus 1", "XK-7D"]),
                       .device("XK-7D"))
        XCTAssertEqual(PortPolicy.launchChoice(remembered: "simulator", devices: ["IAC Driver Bus 1"]), .simulator)
    }

    func testNothingToPick() {
        XCTAssertEqual(PortPolicy.launchChoice(remembered: nil, devices: []), .none)
        XCTAssertEqual(PortPolicy.launchChoice(remembered: "XK-7D", devices: ["IAC Driver Bus 1"]), .none)
    }

    func testUnplugIsReportedOnceAndReplugReconnects() {
        let lost = PortPolicy.afterPortsChanged(choice: .device("XK-7D"), missing: false, remembered: "XK-7D", devices: [])
        XCTAssertEqual(lost, .lost("XK-7D"))
        // Some other device comes or goes while the organ is still away: say nothing again.
        XCTAssertEqual(PortPolicy.afterPortsChanged(choice: .device("XK-7D"), missing: true, remembered: "XK-7D",
                                                    devices: ["IAC Driver Bus 1"]), .nothing)
        XCTAssertEqual(PortPolicy.afterPortsChanged(choice: .device("XK-7D"), missing: true, remembered: "XK-7D",
                                                    devices: ["XK-7D"]), .back("XK-7D"))
        XCTAssertEqual(PortPolicy.afterPortsChanged(choice: .device("XK-7D"), missing: false, remembered: "XK-7D",
                                                    devices: ["XK-7D"]), .nothing)
    }

    func testOrganPluggedInAfterLaunchIsFound() {
        XCTAssertEqual(PortPolicy.afterPortsChanged(choice: .none, missing: false, remembered: nil, devices: ["XK-7D"]),
                       .found("XK-7D"))
        XCTAssertEqual(PortPolicy.afterPortsChanged(choice: .none, missing: false, remembered: "My Interface",
                                                    devices: ["My Interface"]), .found("My Interface"))
    }

    func testDisconnectChosenByThePersonIsRespected() {
        XCTAssertEqual(PortPolicy.afterPortsChanged(choice: .none, missing: false, remembered: "none", devices: ["XK-7D"]),
                       .nothing)
        XCTAssertEqual(PortPolicy.afterPortsChanged(choice: .simulator, missing: false, remembered: "simulator",
                                                    devices: ["XK-7D"]), .nothing)
    }
}

final class BurstTests: XCTestCase {
    final class Capture: MIDIOutput {
        func send(_ bytes: [UInt8]) {}
    }

    func testAFewChangesAreSpokenSeparately() {
        let c = AnnouncementCoalescer(settle: 0.3, maxWait: 2)
        for i in 0..<3 { c.submit(key: "k\(i)", text: "t\(i)", at: 0) }
        XCTAssertEqual(c.due(at: 0.4), ["t0", "t1", "t2"])
    }

    func testAFloodIsSpokenOnceWithACount() {
        let c = AnnouncementCoalescer(settle: 0.3, maxWait: 2)
        for i in 0..<40 { c.submit(key: "k\(i)", text: "t\(i)", at: Double(i) * 0.005) }
        XCTAssertEqual(c.due(at: 0.3), [], "waits until the whole burst is quiet")
        XCTAssertEqual(c.due(at: 0.6), ["t0, and 39 more settings changed"])
        XCTAssertTrue(c.isEmpty)
    }

    func testALongFloodStillSpeaksAfterMaxWait() {
        let c = AnnouncementCoalescer(settle: 0.3, maxWait: 2)
        var t = 0.0
        var out: [String] = []
        for i in 0..<300 {
            c.submit(key: "k\(i % 20)", text: "t\(i)", at: t)
            t += 0.01
            out += c.due(at: t)
        }
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].hasSuffix("and 19 more settings changed"))
    }

    /// If recalling a patch makes the organ send every parameter, the player hears the patch
    /// and a count, not a hundred lines.
    func testPatchRecallFloodThroughTheSession() {
        var now: TimeInterval = 0
        let session = OrganSession(coalescer: AnnouncementCoalescer(settle: 0.3, maxWait: 2))
        session.clock = { now }
        var spoken: [String] = []
        session.onAnnouncement = { spoken.append($0) }
        session.receive([0xB0, 0x00, 0x00, 0xC0, 0x05])
        let settings = session.database.parameters.filter { $0.section == .patch && !$0.hasIndices && !$0.isText }.prefix(30)
        for p in settings {
            let s = Setting(p)
            session.receive(XK7SysEx.dataSet(device: 0, setting: s, raw: p.rawRange.lowerBound))
            now += 0.002
        }
        for _ in 0..<20 { now += 0.05; session.tick() }
        XCTAssertEqual(spoken, ["Upper: patch U05, and 30 more settings changed"])
    }
}

final class TypedNameTests: XCTestCase {
    func testTypographicQuotesBecomePlain() {
        XCTAssertEqual(TextCodec.decode(TextCodec.encode("Jimmy\u{2019}s \u{201C}Ballad\u{201D}")), "Jimmy's \"Ballad\"")
        XCTAssertEqual(TextCodec.decode(TextCodec.encode("Gospel \u{2013} Slow")), "Gospel - Slow")
        XCTAssertEqual(TextCodec.decode(TextCodec.encode("Caf\u{E9}")), "Caf?", "other non-ASCII is still marked")
    }
}

final class VibratoOrderTests: XCTestCase {
    func testKnobOrder() {
        let s = ParameterDatabase.shared.setting(at: Address(0, 0, 0, 0x12, 0x01))!
        XCTAssertEqual(s.parameter.allRawValues.map { s.parameter.display($0) }, ["V-1", "C-1", "V-2", "C-2", "V-3", "C-3"])
    }
}

final class ChannelMismatchTests: XCTestCase {
    func testControlsOnTheWrongChannelAreReportedOncePerConnection() {
        let session = OrganSession()
        var reported: [Int] = []
        session.onChannelMismatch = { reported.append($0) }
        // Organ sends NRPN on channel 4 (index 3); the app listens on channel 1.
        session.receive([0xB3, 0x63, 0x10, 0x62, 0x04, 0x06, 0x01])
        session.receive([0xB3, 0x63, 0x11, 0x62, 0x00, 0x06, 0x01])
        session.receive([0xB3, 0x0E, 0x40])                       // a drawbar, same channel
        XCTAssertEqual(reported, [3])
        session.resetConnection()
        session.receive([0xB3, 0x0E, 0x50])
        XCTAssertEqual(reported, [3, 3], "said again after reconnecting")
    }

    func testRightChannelAndOtherTrafficSayNothing() {
        let session = OrganSession()
        var reported: [Int] = []
        session.onChannelMismatch = { reported.append($0) }
        session.receive([0xB0, 0x63, 0x10, 0x62, 0x04, 0x06, 0x01])   // Upper channel: fine
        session.receive([0xB1, 0x07, 0x64, 0xB2, 0x0B, 0x40])         // volume, expression on Lower and Pedal
        session.receive([0x91, 0x3C, 0x40, 0xC1, 0x05])               // notes and program change
        XCTAssertEqual(reported, [])
    }
}
