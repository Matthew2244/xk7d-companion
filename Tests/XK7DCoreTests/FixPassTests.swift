import XCTest
@testable import XK7DCore

/// Tests for the second review pass: pacing, holding until answered, spoken index labels,
/// and values settled from the manual's menu pages.
final class SendPacingTests: XCTestCase {
    final class Capture: MIDIOutput {
        var sent: [[UInt8]] = []
        func send(_ bytes: [UInt8]) { sent.append(bytes) }
    }

    var now: TimeInterval = 0
    var session: OrganSession!
    let out = Capture()

    override func setUp() {
        session = OrganSession()
        session.clock = { [unowned self] in self.now }
        session.output = out
    }

    func testFastSweepIsMergedLatestValueWins() {
        let s = session.database.setting(at: Address(0x42, 0, 0, 0, 0))!
        for raw in 100...140 { session.set(s, raw: raw); now += 0.001 }
        XCTAssertEqual(out.sent.count, 1, "only the first goes out at once")
        now += 0.05
        session.tick()
        XCTAssertEqual(out.sent.count, 2)
        XCTAssertEqual(Array(out.sent.last![11...12]), XK7SysEx.valueBytes(140, length: 2), "the latest value wins")
        XCTAssertEqual(session.value(of: s), 140)
    }

    func testDifferentSettingsAreAllSentInOrder() {
        let a = session.database.setting(at: Address(0, 0, 0, 0x0C, 0x03))!
        let b = session.database.setting(at: Address(0, 0, 0, 0x0C, 0x04))!
        let c = session.database.setting(at: Address(0, 0, 0, 0x0C, 0x05))!
        session.set(a, raw: 2); session.set(b, raw: 1); session.set(c, raw: 1)
        now += 0.05
        session.tick()
        XCTAssertEqual(out.sent.map { $0[10] }, [0x03, 0x04, 0x05])
        XCTAssertEqual(session.pacedCount, 0)
    }

    func testSlowChangesGoOutImmediately() {
        let s = session.database.setting(at: Address(0, 0, 0, 0x11, 0))!
        session.set(s, raw: 1); now += 0.1
        session.set(s, raw: 0)
        XCTAssertEqual(out.sent.count, 2)
    }
}

final class HoldUntilAnsweredTests: XCTestCase {
    func testMessagesWaitForTheIdentityReplyThenGoWithTheLearnedID() {
        var now: TimeInterval = 0
        let session = OrganSession()
        session.clock = { now }
        let out = SendPacingTests.Capture()
        session.output = out
        session.holdUntilAnswered = true
        session.requestIdentity()
        let s = session.database.setting(at: Address(0, 0, 0, 0x10, 0x04))!
        session.set(s, raw: 5)
        XCTAssertEqual(out.sent.count, 2, "only the two identity requests so far")
        XCTAssertEqual(session.heldCount, 1)
        session.receive(XK7SysEx.identityReply(device: 0x09))
        XCTAssertEqual(session.heldCount, 0)
        XCTAssertEqual(out.sent.last, XK7SysEx.dataSet(device: 0x09, setting: s, raw: 5))
        _ = now
    }

    func testAsksAgainThenGivesUpRatherThanHoldingForever() {
        var now: TimeInterval = 0
        let session = OrganSession()
        session.clock = { now }
        let out = SendPacingTests.Capture()
        session.output = out
        session.holdUntilAnswered = true
        session.requestIdentity()
        session.set(session.database.setting(at: Address(0, 0, 0, 0x11, 0))!, raw: 1)
        for _ in 0..<40 { now += 0.1; session.tick() }
        XCTAssertEqual(session.heldCount, 0, "released after the retries")
        XCTAssertEqual(out.sent.last?[5], 0x13, "the held Data Set went out last")
        XCTAssertGreaterThan(out.sent.filter { $0[1] == 0x7E }.count, 4, "identity was asked again")
    }

    func testOffByDefaultForTheRealOrgan() {
        let session = OrganSession()
        let out = SendPacingTests.Capture()
        session.output = out
        session.requestIdentity()
        session.set(session.database.setting(at: Address(0, 0, 0, 0x11, 0))!, raw: 1)
        XCTAssertEqual(out.sent.count, 3, "an organ that never answers still gets its changes")
    }
}

final class SpokenLabelTests: XCTestCase {
    let db = ParameterDatabase.shared

    func testIndexLabelsReadNaturally() {
        XCTAssertEqual(IndexDimension.spoken("8'"), "8 foot")
        XCTAssertEqual(IndexDimension.spoken("5 1/3'"), "5 and a third foot")
        XCTAssertEqual(IndexDimension.spoken("16'-1 1/3'"), "16 foot-1 and a third foot")
        XCTAssertEqual(IndexDimension.spoken("#13"), "number 13")
        XCTAssertEqual(IndexDimension.spoken("#F92"), "F92")
        XCTAssertEqual(IndexDimension.spoken("3C# "), "3C sharp ")
        XCTAssertEqual(IndexDimension.spoken("E-C#"), "E-C sharp")
    }

    func testSpokenNamesDropRedundantWords() {
        let matrix = db.setting(at: Address(0x13, 0x01, 0x03, 0x00, 0x18))!
        XCTAssertEqual(matrix.spokenName, "Lower matrix level, 4 foot, 3C (middle C)")
        let leak = db.setting(at: Address(0x11, 0x00, 0x02, 0x0C, 0x0D))!
        XCTAssertEqual(leak.spokenName, "Upper leak level, 8 foot, tone wheel number 13, leaking wheel number 14")
        let sub = db.setting(at: Address(0x31, 0, 0, 1, 2))!
        XCTAssertEqual(sub.spokenName, "Pedal sub drawbar level, main footage 8 foot, sub footage 8 foot")
        let fav = db.setting(at: Address(0, 0, 0, 0x50, 0x29))!
        XCTAssertEqual(fav.spokenName, "Favorite, Upper, E-C sharp")
    }
}

final class MenuSettledValueTests: XCTestCase {
    let db = ParameterDatabase.shared
    func p(_ a: Address) -> Parameter { db.setting(at: a)!.parameter }

    func testFoldBackKeysAreKeysLikeTheMenu() {
        XCTAssertEqual(p(Address(0x10, 0, 0, 0, 3)).display(0), "1C")
        XCTAssertEqual(p(Address(0x10, 0, 0, 0, 3)).display(0x0C), "2C")      // p. 109: 1C - 2C
        XCTAssertEqual(p(Address(0x10, 0, 0, 0, 4)).display(0), "4G")
        XCTAssertEqual(p(Address(0x10, 0, 0, 0, 4)).display(5), "5C")         // p. 109: 4G - 5C
    }

    func testPercussionDecayIsOneToTwentyFourThenCont() {
        let d = p(Address(0, 0, 0, 0x11, 0x06))
        XCTAssertEqual(d.display(0), "1")
        XCTAssertEqual(d.display(0x17), "24")
        XCTAssertEqual(d.display(0x18), "Cont")                              // p. 85: 1 - 24, Cont
    }

    func testOtherMenuNames() {
        XCTAssertEqual(p(Address(0, 0, 0, 0x30, 0x04)).display(0), "1")      // p. 103: program 1 - 128
        XCTAssertEqual(p(Address(0, 0, 0, 0x30, 0x04)).display(127), "128")
        XCTAssertEqual(p(Address(0, 0, 0, 0x09, 0x01)).display(7), "Velocity")
        XCTAssertEqual(p(Address(0x51, 0, 0, 0, 5)).display(2), "Mid")       // p. 123 chiff
        XCTAssertEqual(p(Address(0x43, 0, 0, 0, 4)).display(0x1E), "0 cm")  // p. 121 distance 0 - 170
        XCTAssertEqual(p(Address(0x43, 0, 0, 0, 4)).display(200), "170 cm")
        XCTAssertEqual(p(Address(0x43, 0, 0, 0, 2)).display(100), "100", "mic width: raw number, units unknown")
    }
}
