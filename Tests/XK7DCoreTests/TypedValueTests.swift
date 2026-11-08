import XCTest
@testable import XK7DCore

/// What a user can type into a setting's "Type a value" field.
final class TypedValueTests: XCTestCase {
    let db = ParameterDatabase.shared
    func p(_ a: Address) -> Parameter { db.setting(at: a)!.parameter }

    func testNumbersInDisplayUnits() {
        let fast = p(Address(0x42, 0, 0, 0, 0))
        XCTAssertEqual(fast.rawValue(fromTyped: "340 rpm"), 141)
        XCTAssertEqual(fast.rawValue(fromTyped: "340"), 141)
        XCTAssertEqual(fast.rawValue(fromTyped: "0"), 0, "0 rpm is a named value, raw 0")
        XCTAssertNil(fast.rawValue(fromTyped: "150"), "below 200 rpm and not 0: not a value")
        XCTAssertNil(fast.rawValue(fromTyped: "600"))
        let tune = p(Address(0, 0, 0, 0, 0))
        XCTAssertEqual(tune.rawValue(fromTyped: "442 Hz"), 442)
        let level = p(Address(0x10, 0, 0, 0, 6))
        XCTAssertEqual(level.rawValue(fromTyped: "-12.1 dB"), 880)
        XCTAssertEqual(level.rawValue(fromTyped: "+4"), 1041)
        XCTAssertEqual(level.rawValue(fromTyped: "-inf"), 0)
        XCTAssertNil(level.rawValue(fromTyped: "-"), "a lone minus sign is not -inf")
        let oct = p(Address(0, 0, 0, 0x1A, 0))
        XCTAssertEqual(oct.rawValue(fromTyped: "+1"), 8193)
        XCTAssertEqual(oct.rawValue(fromTyped: "-2"), 8190)
        XCTAssertNil(oct.rawValue(fromTyped: "3"))
        let angle = p(Address(0x42, 0, 0, 0, 6))
        XCTAssertEqual(angle.rawValue(fromTyped: "random"), 360)
        XCTAssertEqual(angle.rawValue(fromTyped: "90"), 90)
        let chan = p(Address(0, 0, 0, 0x0D, 0))
        XCTAssertEqual(chan.rawValue(fromTyped: "3"), 2)
        XCTAssertEqual(chan.rawValue(fromTyped: "off"), 16)
        XCTAssertNil(chan.rawValue(fromTyped: "17"))
        let brake = p(Address(0, 0, 0, 0x18, 1))
        XCTAssertEqual(brake.rawValue(fromTyped: "2.5 sec"), 24)
        XCTAssertEqual(brake.display(24), "2.5 sec")
    }

    func testNotesBothWays() {
        let split = p(Address(0, 0, 0, 0x1A, 2))
        XCTAssertEqual(split.rawValue(fromTyped: "3C"), 60)
        XCTAssertEqual(split.rawValue(fromTyped: "C3"), 60)
        XCTAssertEqual(split.rawValue(fromTyped: "3C#"), 61)
        XCTAssertEqual(split.rawValue(fromTyped: "c sharp 3"), 61)
        XCTAssertEqual(split.rawValue(fromTyped: "-2C"), 0)
        XCTAssertEqual(split.rawValue(fromTyped: "72"), 72)
        XCTAssertNil(split.rawValue(fromTyped: "H3"))
    }

    func testBalanceAndSteps() {
        let pan = p(Address(0, 0, 0, 0x30, 0x0A))
        XCTAssertEqual(pan.rawValue(fromTyped: "center"), 64)
        XCTAssertEqual(pan.rawValue(fromTyped: "L10"), 54)
        XCTAssertEqual(pan.rawValue(fromTyped: "right 63"), 127)
        XCTAssertNil(pan.rawValue(fromTyped: "R64"))
        let mix = p(Address(0, 0, 0, 0x12, 0x04))
        XCTAssertEqual(mix.rawValue(fromTyped: "even"), 64)
        XCTAssertEqual(mix.rawValue(fromTyped: "D64"), 0)
        XCTAssertEqual(mix.rawValue(fromTyped: "63V"), 127)
        let rise = p(Address(0x42, 0, 0, 0, 2))
        XCTAssertEqual(rise.rawValue(fromTyped: "step 12"), 12)
        XCTAssertEqual(rise.rawValue(fromTyped: "12.5 sec"), 0x24)
        XCTAssertNil(rise.rawValue(fromTyped: "step 40"))
    }

    func testEveryDisplayedValueTypesBackToItself() {
        // Whatever the app shows, typing it back must give the same raw value.
        var checked = 0
        for p in db.parameters {
            switch p.kind {
            case .number, .note, .balance, .steps:
                let r = p.rawRange
                for raw in Set([r.lowerBound, r.upperBound, (r.lowerBound + r.upperBound) / 2]) {
                    XCTAssertEqual(p.rawValue(fromTyped: p.display(raw)), raw, "\(p.id): \(p.display(raw))")
                    checked += 1
                }
            default: break
            }
        }
        XCTAssertGreaterThan(checked, 500)
    }
}
