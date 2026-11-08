import XCTest
@testable import XK7DCore

/// Values settled by the manual's menu screenshots (see docs/PARAMETER-REVIEW.md, "Picture pass").
final class PicturePassTests: XCTestCase {
    let db = ParameterDatabase.shared
    func s(_ a: UInt8, _ b: UInt8) -> Setting { db.setting(at: Address(0, 0, 0, a, b))! }

    func testEQBassFrequencyIsTwelveHertzSteps() {
        for setting in [s(0x16, 0x00), s(0x01, 0x03)] {     // patch EQ, master EQ
            let p = setting.parameter
            XCTAssertEqual(p.display(0), "20 Hz")
            XCTAssertEqual(p.display(7), "104 Hz", "the value shown on pp. 99 and 127")
            XCTAssertEqual(p.display(0x18), "308 Hz")
        }
    }

    func testPatchEQMidFrequency() {
        let p = s(0x16, 0x01).parameter
        XCTAssertEqual(p.display(0), "250 Hz")
        XCTAssertEqual(p.display(5), "1.2 kHz", "the value shown on p. 99")
        XCTAssertEqual(p.display(0x0F), "3.1 kHz")
    }

    func testMasterEQMidIsThirdOctaves() {
        let p = s(0x01, 0x04).parameter
        XCTAssertEqual(p.allRawValues.map { p.display($0) },
                       ["125 Hz", "160 Hz", "200 Hz", "250 Hz", "315 Hz", "400 Hz", "500 Hz", "630 Hz", "800 Hz",
                        "1 kHz", "1.25 kHz", "1.6 kHz", "2 kHz", "2.5 kHz", "3.15 kHz", "4 kHz"])
    }

    func testTrebleFrequencyIsStillOnlyEndPoints() {
        XCTAssertEqual(s(0x16, 0x02).parameter.display(3), "step 3 of 19")
    }

    func testPreampOutputLevelIsCentred() {
        let p = s(0x14, 0x02).parameter
        XCTAssertEqual(p.display(0), "-64")
        XCTAssertEqual(p.display(64), "0")
        XCTAssertEqual(p.display(127), "+63")
    }

    func testPedalContactHasThreeLeaves() {
        let pedal = db.setting(at: Address(0x21, 0x03, 0x00, 0x00, 0x18))!.parameter
        XCTAssertEqual(pedal.rawRange, 0...2)
        XCTAssertEqual(pedal.display(2), "3")
        XCTAssertEqual(db.setting(at: Address(0x21, 0x00, 0x00, 0x00, 0x18))!.parameter.rawRange, 0...5)
    }

    func testKnobControlNumberGapIsCC66To69() {
        let p = s(0x19, 0x09).parameter
        XCTAssertTrue(p.display(0x1B).hasPrefix("CC 65"))
        XCTAssertTrue(p.display(0x1C).hasPrefix("CC 66"))
        XCTAssertTrue(p.display(0x1F).hasPrefix("CC 69"))
        XCTAssertTrue(p.display(0x20).hasPrefix("CC 70"))
    }

    func testOctaveButtonModesAreXK7Only() {
        for b: UInt8 in 1...3 { XCTAssertTrue(s(0x06, b).parameter.xk7Only) }
    }

    func testPatchLoadDrawbarIsTheOrganSettings() {
        let p = db.setting(at: Address(0, 0, 0, 0x40, 0x01))!.parameter
        XCTAssertTrue(p.name.contains("organ settings"), p.name)
    }
}
