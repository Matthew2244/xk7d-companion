import XCTest
@testable import XK7DCore

/// Tests for the 1.1.1 review: what an editor may step from, and when a change can really be sent.
final class HoldsTests: XCTestCase {
    let db = ParameterDatabase.shared

    func testChoicesHoldOnlyTheirOwnValues() {
        let organType = db.setting(at: Address(0, 0, 0, 0x10, 0x04))!.parameter
        XCTAssertTrue((0...5).allSatisfy { organType.holds($0) })
        XCTAssertFalse(organType.holds(6))
        XCTAssertFalse(organType.holds(-1))
    }

    func testNumbersHoldTheirRange() {
        let fast = db.setting(at: Address(0x42, 0, 0, 0, 0))!.parameter
        XCTAssertTrue(fast.holds(fast.rawRange.lowerBound))
        XCTAssertTrue(fast.holds(fast.rawRange.upperBound))
        XCTAssertFalse(fast.holds(fast.rawRange.lowerBound - 1))
        XCTAssertFalse(fast.holds(fast.rawRange.upperBound + 1))
    }

    func testEveryListedValueIsHeld() {
        for p in db.parameters where !p.isText {
            XCTAssertTrue(p.allRawValues.allSatisfy { p.holds($0) }, p.id)
        }
    }
}

final class CannotSendTests: XCTestCase {
    func testWhenAChangeCanBeSent() {
        XCTAssertNil(PortPolicy.cannotSend(choice: .device("XK-7D"), hasOutput: true, missing: false, canSend: true))
        XCTAssertNil(PortPolicy.cannotSend(choice: .simulator, hasOutput: true, missing: false, canSend: true))
    }

    func testNothingChosenOrNothingOpen() {
        XCTAssertEqual(PortPolicy.cannotSend(choice: .none, hasOutput: false, missing: false, canSend: true),
                       "Not connected. Choose the organ or the simulator first.")
        // A port that wouldn't open (another program had it) leaves nothing to send to.
        XCTAssertEqual(PortPolicy.cannotSend(choice: .device("XK-7D"), hasOutput: false, missing: false, canSend: true),
                       "Not connected. Choose the organ or the simulator first.")
    }

    func testUnpluggedSaysSo() {
        XCTAssertEqual(PortPolicy.cannotSend(choice: .device("XK-7D"), hasOutput: true, missing: true, canSend: true),
                       "The organ is disconnected, so nothing was sent. Check the USB cable and that the organ is on.")
    }

    /// Listening only: before 1.1.1 the app said "sent" while the change went nowhere.
    func testAListenOnlyPortCantClaimASend() {
        let why = PortPolicy.cannotSend(choice: .device("XK-7D"), hasOutput: true, missing: false, canSend: false)
        XCTAssertEqual(why, "The app can listen to this MIDI port but can't send to it, so nothing was sent. Choose the organ again, or check that no other program is using it.")
    }
}
