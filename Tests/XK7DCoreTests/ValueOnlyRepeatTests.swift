import XCTest
@testable import XK7DCore

/// 1.3.0: when the same control speaks again, with nothing else said in between, only its value is
/// said. Ported one to one in windows/XK7DCore.Tests/ValueOnlyRepeatTests.cs.
final class ValueOnlyRepeatTests: XCTestCase {
    var session: OrganSession!
    var now: TimeInterval = 100
    var spoken: [String] = []

    override func setUp() {
        session = OrganSession(coalescer: AnnouncementCoalescer(settle: 0.3, maxWait: 2))
        session.clock = { [unowned self] in self.now }
        session.onAnnouncement = { [unowned self] in self.spoken.append($0) }
    }

    func advance(_ dt: TimeInterval) { now += dt; session.tick() }

    /// Upper 8 foot drawbar to a level, as the organ sends it.
    func drawbar(_ level: Int) {
        session.receive([0xB0, UInt8(DrawbarCC.controller(part: .upper, index: 2)), UInt8(DrawbarCC.value(forLevel: level))])
    }
    /// Organ Type by NRPN: 1 Mellow, 2 Vx.
    func organType(_ raw: UInt8) { session.receive([0xB0, 0x63, 0x10, 0x62, 0x04, 0x06, raw]) }

    func testFirstMoveIsFullAndTheNextIsTheValueOnly() {
        drawbar(6); advance(0.4)
        drawbar(4); advance(0.4)
        XCTAssertEqual(spoken, ["Upper 8 foot: 6", "4"])
        XCTAssertEqual(session.lastAnnouncement, "Upper 8 foot: 4", "the full line is kept for history and Repeat Last")
        organType(1); advance(0.4)
        organType(2); advance(0.4)
        XCTAssertEqual(spoken.suffix(2), ["Organ type: Mellow", "Vx."])
    }

    func testAnotherControlInBetweenBringsTheNameBack() {
        drawbar(6); advance(0.4)
        organType(1); advance(0.4)
        drawbar(5); advance(0.4)
        organType(2); advance(0.4)
        XCTAssertEqual(spoken, ["Upper 8 foot: 6", "Organ type: Mellow", "Upper 8 foot: 5", "Organ type: Vx."])
    }

    func testAStatusLineOrAnUrgentLineBringsTheNameBack() {
        drawbar(6); advance(0.4)
        session.speak("Organ connected again")
        drawbar(5); advance(0.4)
        session.receive([0xB0, 92, 127])   // Leslie fast, said at once
        drawbar(4); advance(0.4)
        XCTAssertEqual(spoken, ["Upper 8 foot: 6", "Organ connected again", "Upper 8 foot: 5", "Fast", "Upper 8 foot: 4"])
    }

    func testTheAppSayingSomethingBringsTheNameBack() {
        drawbar(6); advance(0.4)
        session.coalescer.breakRepeat()     // what the app does for its own confirmations
        drawbar(5); advance(0.4)
        XCTAssertEqual(spoken, ["Upper 8 foot: 6", "Upper 8 foot: 5"])
    }

    func testAQuietGapBringsTheNameBack() {
        drawbar(6); advance(0.4)
        advance(AnnouncementCoalescer.repeatQuietGap - 1)
        drawbar(5); advance(0.4)
        advance(AnnouncementCoalescer.repeatQuietGap + 0.1)
        drawbar(4); advance(0.4)
        XCTAssertEqual(spoken, ["Upper 8 foot: 6", "5", "Upper 8 foot: 4"])
        XCTAssertEqual(AnnouncementCoalescer.repeatQuietGap, 10)
    }

    func testALongSweepSaysTheNameOnceThenNumbers() {
        // One step every 0.1 s for 5 s: past maxWait twice, so two lines along the way and one at the end.
        for i in 0..<50 { drawbar(i / 6 % 9); advance(0.1) }
        advance(0.4)
        XCTAssertGreaterThanOrEqual(spoken.count, 3, "\(spoken)")
        XCTAssertTrue(spoken[0].hasPrefix("Upper 8 foot: "), "\(spoken)")
        for line in spoken.dropFirst() { XCTAssertNotNil(Int(line), "value only: \(spoken)") }
    }

    func testTurnedOffSaysTheNameEveryTime() {
        session.sayValueOnlyOnRepeat = false
        drawbar(6); advance(0.4)
        drawbar(4); advance(0.4)
        XCTAssertEqual(spoken, ["Upper 8 foot: 6", "Upper 8 foot: 4"])
        for i in 0..<30 { drawbar(i / 4 % 9); advance(0.1) }
        advance(0.4)
        XCTAssertTrue(spoken.allSatisfy { $0.hasPrefix("Upper 8 foot: ") }, "\(spoken)")
    }

    func testBurstsAndPatchChangesAreAlwaysFull() {
        drawbar(6); advance(0.4)
        // A patch recall sending ten settings at once: one summary line, and it resets the repeat.
        for i in 0..<9 { session.receive([0xB0, UInt8(DrawbarCC.controller(part: .upper, index: i)), 0x20]) }
        organType(2)
        advance(0.4)
        XCTAssertEqual(spoken.count, 2)
        XCTAssertTrue(spoken[1].hasSuffix("and 9 more settings changed"), spoken[1])
        drawbar(6); advance(0.4)
        XCTAssertEqual(spoken.last, "Upper 8 foot: 6")
        // A patch change twice in a row: full both times (it has no value-only form).
        session.receive([0xB0, 0x00, 0x01, 0xC0, 15]); advance(0.4)
        session.receive([0xB0, 0x00, 0x01, 0xC0, 16]); advance(0.4)
        XCTAssertTrue(spoken[spoken.count - 2].hasPrefix("Upper: "), "\(spoken)")
        XCTAssertTrue(spoken[spoken.count - 1].hasPrefix("Upper: "), "\(spoken)")
    }

    func testValueOnlyFormsAreBuiltNotCut() {
        let db = ParameterDatabase.shared
        let percussion = db.setting(at: Address(0, 0, 0, 0x11, 0x00))!
        XCTAssertEqual(OrganSession.line(percussion, raw: 1), "Percussion on")
        XCTAssertEqual(OrganSession.valueOnly(percussion, raw: 1), "on")
        let horn = db.setting(at: Address(0x42, 0, 0, 0, 0))!
        XCTAssertEqual(OrganSession.valueOnly(horn, raw: 141), "340 rpm")
        let tune = db.setting(at: Address(0, 0, 0, 0, 0))!
        XCTAssertEqual(OrganSession.valueOnly(tune, raw: 442), "442 Hz")
    }

    func testCoalescerAlone() {
        let c = AnnouncementCoalescer(settle: 0.3, maxWait: 2)
        c.submit(key: "a", text: "A: 1", valueOnly: "1", at: 0)
        XCTAssertEqual(c.dueLines(at: 0.4), [.init(text: "A: 1", fullText: "A: 1")])
        c.submit(key: "a", text: "A: 2", valueOnly: "2", at: 1)
        XCTAssertEqual(c.dueLines(at: 1.4), [.init(text: "2", fullText: "A: 2")])
        c.submit(key: "a", text: "A: 3", at: 2)   // no value-only form: full
        XCTAssertEqual(c.due(at: 2.4), ["A: 3"])
        c.submit(key: "a", text: "A: 4", valueOnly: "4", at: 3)
        XCTAssertEqual(c.flush(), ["A: 4"], "flush is always full")
        c.submit(key: "a", text: "A: 5", valueOnly: "5", at: 4)
        XCTAssertEqual(c.due(at: 4.4), ["A: 5"], "and resets")
    }
}
