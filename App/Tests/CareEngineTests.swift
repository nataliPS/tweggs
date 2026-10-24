import XCTest
@testable import Mixlings

final class CareEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 24 * 3600

    private func egg(bornAt: Date? = nil) -> Creature {
        Creature(id: "test-1", name: "T", genome: Array(repeating: [0, 0], count: 8),
                 origin: .hatched, bornAt: bornAt ?? t0)
    }

    // MARK: Growth

    func testNaturalGrowthSchedule() {
        let c = egg()
        XCTAssertEqual(CareEngine.stage(c, at: t0), .egg)
        XCTAssertEqual(CareEngine.stage(c, at: t0 + day - 1), .egg)
        XCTAssertEqual(CareEngine.stage(c, at: t0 + day), .baby)       // day 1
        XCTAssertEqual(CareEngine.stage(c, at: t0 + 3 * day - 1), .baby)
        XCTAssertEqual(CareEngine.stage(c, at: t0 + 3 * day), .teen)   // day 3
        XCTAssertEqual(CareEngine.stage(c, at: t0 + 7 * day - 1), .teen)
        XCTAssertEqual(CareEngine.stage(c, at: t0 + 7 * day), .adult)  // day 7
        XCTAssertEqual(CareEngine.stage(c, at: t0 + 365 * day), .adult)
    }

    func testEarlyHatchShiftsSchedule() {
        let hatchAt = t0 + 2 * hour
        let c = CareEngine.hatch(egg(), at: hatchAt)
        XCTAssertEqual(c.hatchedAt, hatchAt)
        XCTAssertEqual(CareEngine.stage(c, at: hatchAt), .baby)
        XCTAssertEqual(CareEngine.date(of: .teen, for: c), hatchAt + 2 * day)
        XCTAssertEqual(CareEngine.date(of: .adult, for: c), hatchAt + 6 * day)
    }

    func testNextGrowth() {
        let c = egg()
        XCTAssertEqual(CareEngine.nextGrowth(c, at: t0)?.stage, Stage.baby)
        XCTAssertEqual(CareEngine.nextGrowth(c, at: t0 + day)?.stage, Stage.teen)
        XCTAssertEqual(CareEngine.nextGrowth(c, at: t0 + 4 * day)?.date, t0 + 7 * day)
        XCTAssertNil(CareEngine.nextGrowth(c, at: t0 + 7 * day))
    }

    func testHatchIsNoOpWhenAlreadyHatched() {
        let c = egg()
        let later = CareEngine.hatch(c, at: t0 + 2 * day)
        XCTAssertNil(later.hatchedAt) // naturally hatched already; nothing to change
    }

    // MARK: Decay

    func testEggDoesNotDecay() {
        let c = egg()
        let d = CareEngine.decay(c, to: t0 + day - 1)
        XCTAssertEqual(d.hunger, c.hunger)
        XCTAssertEqual(d.joy, c.joy)
        XCTAssertEqual(d.mood, c.mood)
    }

    func testGentleDecayAfterHatch() {
        let c = CareEngine.hatch(egg(), at: t0)
        let d = CareEngine.decay(c, to: t0 + 2 * hour)
        XCTAssertEqual(d.hunger, CareEngine.startValue - 2 * CareEngine.hungerDecayPerHour, accuracy: 0.0001)
        XCTAssertEqual(d.joy, CareEngine.startValue - 2 * CareEngine.joyDecayPerHour, accuracy: 0.0001)
        XCTAssertEqual(d.mood, CareEngine.startValue - 2 * CareEngine.moodDecayPerHour, accuracy: 0.0001)
        XCTAssertEqual(d.lastUpdated, t0 + 2 * hour)
    }

    func testDecayIsComposable() {
        let c = CareEngine.hatch(egg(), at: t0)
        let once = CareEngine.decay(c, to: t0 + 6 * hour)
        let twice = CareEngine.decay(CareEngine.decay(c, to: t0 + 3 * hour), to: t0 + 6 * hour)
        XCTAssertEqual(once.hunger, twice.hunger, accuracy: 0.0001)
        XCTAssertEqual(once.mood, twice.mood, accuracy: 0.0001)
    }

    func testDecayFloorsAndNeverDies() {
        let c = CareEngine.hatch(egg(), at: t0)
        for days in [7.0, 30, 365, 10_000] {
            let d = CareEngine.decay(c, to: t0 + days * day)
            XCTAssertEqual(d.hunger, CareEngine.floor)
            XCTAssertEqual(d.joy, CareEngine.floor)
            XCTAssertEqual(d.mood, CareEngine.floor)
            XCTAssertGreaterThan(d.hunger, 0)
            XCTAssertEqual(CareEngine.condition(c, at: t0 + days * day), .sleepy)
        }
        // Still grows and can be cared for after long neglect.
        let neglected = CareEngine.decay(c, to: t0 + 100 * day)
        XCTAssertEqual(CareEngine.stage(neglected, at: t0 + 100 * day), .adult)
        let fed = CareEngine.feed(neglected, at: t0 + 100 * day)
        XCTAssertGreaterThan(fed.hunger, CareEngine.floor)
    }

    func testClockGoingBackwardsIsIgnored() {
        let c = CareEngine.decay(CareEngine.hatch(egg(), at: t0), to: t0 + 5 * hour)
        let back = CareEngine.decay(c, to: t0 + 1 * hour)
        XCTAssertEqual(back.hunger, c.hunger)
        XCTAssertEqual(back.lastUpdated, c.lastUpdated)
    }

    // MARK: Care

    func testFeedPlayPetClampToMax() {
        var c = CareEngine.hatch(egg(), at: t0)
        for _ in 0..<10 {
            c = CareEngine.feed(c, at: t0)
            c = CareEngine.play(c, at: t0)
            c = CareEngine.pet(c, at: t0)
        }
        XCTAssertLessThanOrEqual(c.hunger, CareEngine.maxValue)
        XCTAssertEqual(c.joy, CareEngine.maxValue)
        XCTAssertEqual(c.mood, CareEngine.maxValue)
        XCTAssertEqual(CareEngine.condition(c, at: t0), .happy)
    }

    func testEggCannotBeFedButCanBePetted() {
        let c = egg()
        XCTAssertEqual(CareEngine.feed(c, at: t0).hunger, c.hunger)
        XCTAssertEqual(CareEngine.play(c, at: t0).joy, c.joy)
        XCTAssertGreaterThan(CareEngine.pet(c, at: t0).mood, c.mood)
    }

    func testFeedRaisesHunger() {
        let c = CareEngine.decay(CareEngine.hatch(egg(), at: t0), to: t0 + 10 * hour)
        let fed = CareEngine.feed(c, at: t0 + 10 * hour)
        XCTAssertEqual(fed.hunger, min(100, c.hunger + CareEngine.feedHunger), accuracy: 0.0001)
    }

    // MARK: Starters / persistence

    func testStarterIsDeterministicAndAdult() {
        let now = t0
        let a = CreatureFactory.starter(playerId: "p1", slot: 1, name: "Pip", origin: .starter,
                                        bornAt: now, alreadyAdult: true, now: now)
        let b = CreatureFactory.starter(playerId: "p1", slot: 1, name: "Pip", origin: .starter,
                                        bornAt: now, alreadyAdult: true, now: now)
        XCTAssertNotNil(a)
        XCTAssertEqual(a?.genome, b?.genome)
        XCTAssertEqual(a?.id, b?.id)
        XCTAssertEqual(a.map { CareEngine.stage($0, at: now) }, Stage.adult)
        XCTAssertEqual(a?.genome.count, 8)
        XCTAssertTrue(a?.genome.allSatisfy { $0.count == 2 } ?? false)
    }

    func testStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mixlings-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CreatureStore(fileURL: url)
        let first = store.loadOrCreate()
        XCTAssertEqual(store.load().playerId, first.playerId, "playerId must persist")

        store.update { $0.replace(self.egg()); $0.activeCreatureId = "test-1" }
        let saved = store.apply(.pet, at: t0)
        XCTAssertEqual(saved.creatures.count, 1)
        XCTAssertEqual(store.load(), saved)
    }
}
