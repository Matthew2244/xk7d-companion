import XCTest
@testable import XK7DCore

/// Patch changes are said by name: factory names from the manual's table, User patch and Favorite
/// names from the organ (a Name Data Set it sends, or a Temporary dump the app asks for).
final class PatchNameTests: XCTestCase {
    var session: OrganSession!
    var now: TimeInterval = 100
    var spoken: [String] = []
    var sent: [[UInt8]] = []
    var notes: [String] = []

    final class Capture: MIDIOutput {
        var onSend: ([UInt8]) -> Void = { _ in }
        func send(_ bytes: [UInt8]) { onSend(bytes) }
    }
    let out = Capture()

    override func setUp() {
        session = OrganSession(coalescer: AnnouncementCoalescer(settle: 0.3, maxWait: 2))
        session.clock = { [unowned self] in self.now }
        session.onAnnouncement = { [unowned self] in self.spoken.append($0) }
        session.onNameNote = { [unowned self] in self.notes.append($0) }
        out.onSend = { [unowned self] in self.sent.append($0) }
        session.output = out
    }

    func run(_ seconds: TimeInterval) {
        for _ in 0..<Int((seconds / 0.05).rounded()) { now += 0.05; session.tick() }
    }

    static let dumpRequest: [UInt8] = [0xF0, 0x55, 0x00, 0x10, 0x26, 0x12, 0x07, 0xF7]
    var dumpRequests: Int { sent.filter { $0 == Self.dumpRequest }.count }

    /// A Temporary dump (6 packets of type 07, then 11 of type 08) with the names at `offset`.
    static func dump(upper: String, lower: String, offset: Int = 40) -> [[UInt8]] {
        var stream = [UInt8](repeating: 0, count: 64 * 6)
        let names = TextCodec.encode(upper, length: 16) + TextCodec.encode(lower, length: 16)
        for (i, b) in names.enumerated() { stream[offset + i] = b }
        var out: [[UInt8]] = []
        for n in 0..<6 { out.append(XK7SysEx.dataPacket(device: 0, type: 0x07, packet: n, data64: Array(stream[n * 64..<(n + 1) * 64]))) }
        for n in 0..<11 { out.append(XK7SysEx.dataPacket(device: 0, type: 0x08, packet: n, data64: [UInt8](repeating: 0, count: 64))) }
        return out
    }

    func selectUser(_ program: UInt8, channel: UInt8 = 0) {
        session.receive([0xB0 | channel, 0x00, 0x00, 0xB0 | channel, 0x20, 0x00, 0xC0 | channel, program])
    }

    // MARK: Factory

    func testFactoryTableHasEveryPatch() {
        XCTAssertEqual(PatchNames.factoryUpper.count, 100)
        XCTAssertEqual(PatchNames.factoryLower.count, 100)
        XCTAssertEqual(PatchNames.factoryUpper[0], "Dr. L.S.")
        XCTAssertEqual(PatchNames.factoryUpper[15], "Kinda Brian")
        XCTAssertEqual(PatchNames.factoryLower[21], "Principal 4\u{B4} & 2\u{B4}")
        XCTAssertEqual(PatchNames.factoryUpper[99], "Full Swell")
        XCTAssertEqual(PatchNames.factoryLower[99], "Full Great with 16\u{B4}")
    }

    func testFactoryPatchSaidByNameAtOnceWithoutAsking() {
        session.receive([0xB1, 0x00, 0x01, 0xB1, 0x20, 0x00, 0xC1, 21])
        run(0.4)
        XCTAssertEqual(spoken, ["Lower: Principal 4 foot & 2 foot, F21"])
        XCTAssertEqual(dumpRequests, 0)
        // Pedal takes the Lower and Pedal column.
        session.receive([0xB2, 0x00, 0x01, 0xC2, 22])
        run(0.4)
        XCTAssertEqual(spoken.last, "Pedal: Flute Harmonique, F22")
    }

    // MARK: User patches

    func testUserPatchNameFromTheDump() {
        selectUser(5)
        run(0.2)
        XCTAssertEqual(dumpRequests, 1, "asks once, after a short pause")
        XCTAssertEqual(spoken, [])
        for p in Self.dump(upper: "Jazz Lead", lower: "Walking Bass") { session.receive(p) }
        run(0.5)
        XCTAssertEqual(spoken, ["Upper: Jazz Lead, U05"])
        XCTAssertEqual(session.nameDumpState, .works)
        // Every packet of our own request is acknowledged, and none starts a "Read from Organ" snapshot.
        XCTAssertEqual(sent.filter { $0.count > 5 && $0[5] == 0x14 }.count, 17)
        XCTAssertNil(session.currentDump)
        XCTAssertEqual(session.patchNameCache["Upper|patch U05"], "Jazz Lead")
    }

    func testLowerTakesTheLowerName() {
        selectUser(9, channel: 1)
        run(0.2)
        for p in Self.dump(upper: "Jazz Lead", lower: "Walking Bass") { session.receive(p) }
        run(0.5)
        XCTAssertEqual(spoken, ["Lower: Walking Bass, U09"])
    }

    func testNameSentByTheOrganIsUsedAndNotSaidTwice() {
        selectUser(5)
        run(0.05)
        // Patch name, upper, as a Data Set: "Gospel".
        let s = session.database.setting(at: Address(0, 0, 0x10, 0, 0))!
        session.receive(XK7SysEx.dataSet(device: 0, setting: s, text: "Gospel"))
        run(0.6)
        XCTAssertEqual(spoken, ["Upper: Gospel, U05"])
        XCTAssertEqual(dumpRequests, 0, "no need to ask")
    }

    func testOrganThatDoesNotAnswerFallsBackThenStopsAsking() {
        selectUser(5)
        run(1.0)
        XCTAssertEqual(spoken, ["Upper: patch U05"])
        selectUser(6)
        run(1.0)
        XCTAssertEqual(spoken.last, "Upper: patch U06")
        XCTAssertEqual(session.nameDumpState, .gaveUp)
        XCTAssertEqual(dumpRequests, 2)
        // From now on it's said after the short wait, without asking.
        selectUser(7)
        run(0.4)
        XCTAssertEqual(spoken.last, "Upper: patch U07")
        XCTAssertEqual(dumpRequests, 2)
        XCTAssertTrue(notes.contains { $0.contains("Stopped asking") })
    }

    func testDumpWithoutNamesFallsBack() {
        selectUser(5)
        run(0.2)
        for p in Self.dump(upper: "", lower: "") { session.receive(p) }
        run(0.4)
        XCTAssertEqual(spoken, ["Upper: patch U05"])
    }

    func testNameLearnedEarlierIsUsedWhenTheOrganIsQuiet() {
        session.askOrganForPatchNames = false
        selectUser(5)
        let s = session.database.setting(at: Address(0, 0, 0x10, 0, 0))!
        session.receive(XK7SysEx.dataSet(device: 0, setting: s, text: "Gospel"))
        run(0.5)
        selectUser(6)
        run(0.5)
        selectUser(5)
        run(0.5)
        XCTAssertEqual(spoken, ["Upper: Gospel, U05", "Upper: patch U06", "Upper: Gospel, U05"])
        XCTAssertEqual(dumpRequests, 0)
    }

    func testRenamingTheCurrentPatchUpdatesWhatIsRemembered() {
        session.askOrganForPatchNames = false
        selectUser(5)
        run(0.5)
        let s = session.database.setting(at: Address(0, 0, 0x10, 0, 0))!
        session.set(s, text: "Sunday")
        selectUser(6)
        run(0.5)
        selectUser(5)
        run(0.5)
        XCTAssertEqual(spoken.last, "Upper: Sunday, U05")
    }

    func testQuickChangesAskOnceAndSayTheLast() {
        for p: UInt8 in 1...5 { selectUser(p); run(0.05) }
        run(0.15)
        XCTAssertEqual(dumpRequests, 1)
        for p in Self.dump(upper: "Five", lower: "x") { session.receive(p) }
        run(0.5)
        XCTAssertEqual(spoken, ["Upper: Five, U05"])
    }

    func testAnswerForAnOlderPatchIsNotUsed() {
        selectUser(5)
        run(0.2)
        XCTAssertEqual(dumpRequests, 1)
        selectUser(6)                     // before the dump for U05 arrives
        for p in Self.dump(upper: "Old Name", lower: "x") { session.receive(p) }
        run(0.25)
        XCTAssertEqual(dumpRequests, 2, "asks again for the new patch")
        for p in Self.dump(upper: "New Name", lower: "x") { session.receive(p) }
        run(0.5)
        XCTAssertEqual(spoken, ["Upper: New Name, U06"])
    }

    func testFavoriteIsLookedUpAndAdjustIsNot() {
        session.receive([0xB0, 0x00, 0x65, 0xC0, 0x69])
        run(0.2)
        XCTAssertEqual(dumpRequests, 1)
        for p in Self.dump(upper: "Ballad", lower: "x") { session.receive(p) }
        run(0.5)
        XCTAssertEqual(spoken, ["Upper: Ballad, Favorite C sharp-F"])
        session.receive([0xC0, 0x7F])
        run(0.4)
        XCTAssertEqual(spoken.last, "Upper: Adjust B")
        XCTAssertEqual(dumpRequests, 1)
    }

    func testReadFromOrganStillGetsItsOwnDump() {
        selectUser(5)
        run(0.2)
        session.requestDump(.temporary)
        for p in Self.dump(upper: "Jazz Lead", lower: "x") { session.receive(p) }
        XCTAssertEqual(session.currentDump?.count, 17)
        run(1.2)
        XCTAssertEqual(spoken, ["Upper: patch U05"])
    }

    // MARK: Reading names out of a dump

    func testFromTemporaryDump() {
        func stream(_ bytes: [UInt8], at offset: Int) -> [UInt8] {
            var s = [UInt8](repeating: 0, count: 200)
            for (i, b) in bytes.enumerated() { s[offset + i] = b }
            return s
        }
        let names = TextCodec.encode("Dr. L.S.       U") + TextCodec.encode("Dr. L.S.       L")
        let found = PatchNames.fromTemporaryDump(stream(names, at: 17))
        XCTAssertEqual(found?.upper, "Dr. L.S.")
        XCTAssertEqual(found?.lower, "Dr. L.S.")
        // Values that happen to be printable, but are not 32 in a row of words, are not names.
        XCTAssertNil(PatchNames.fromTemporaryDump(stream(Array(repeating: 0x40, count: 40), at: 0)))
        XCTAssertNil(PatchNames.fromTemporaryDump(stream(TextCodec.encode("Jazz"), at: 0)))
        XCTAssertNil(PatchNames.fromTemporaryDump([]))
    }

    func testSpokenNames() {
        XCTAssertEqual(PatchNames.spoken("Stopped Flute 16\u{B4} & 8\u{B4}"), "Stopped Flute 16 foot & 8 foot")
        XCTAssertEqual(PatchNames.spoken("DB 8\u{B4} 4\u{B4} 2\u{2154}\u{B4}"), "DB 8 foot 4 foot 2\u{2154} foot")
        XCTAssertEqual(PatchNames.spoken("Tibia 8' & 4'"), "Tibia 8 foot & 4 foot")
        XCTAssertEqual(PatchNames.spoken("Joe's M-3"), "Joe's M-3")
        XCTAssertEqual(PatchNames.announcement(part: "Upper", description: "patch U05", name: nil), "Upper: patch U05")
        XCTAssertEqual(PatchNames.announcement(part: "Upper", description: "patch U05", name: ""), "Upper: patch U05")
        XCTAssertEqual(PatchNames.clean("  Jazz    Lead  "), "Jazz Lead")
    }
}
