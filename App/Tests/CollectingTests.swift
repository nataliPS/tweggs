import XCTest
import MixlingsGenome
@testable import Mixlings

final class CollectingTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    /// Fixed +3 h offset (no DST) so day-boundary tests don't depend on the host zone.
    private let plus3 = TimeZone(secondsFromGMT: 3 * 3600)!
    /// 2026-10-24 12:00:00 UTC.
    private let noon = Date(timeIntervalSince1970: 1_792_843_200)
    private let day: TimeInterval = 24 * 3600

    private func creature(_ id: String, genome: Genome, origin: CreatureOrigin = .bred,
                          generation: Int = 0) -> Creature {
        Creature(id: id, name: id, genome: genome, origin: origin,
                 bornAt: noon, hatchedAt: noon, generation: generation)
    }

    private func homozygous(_ variants: [Int]) -> Genome { variants.map { [$0, $0] } }

    // MARK: Generation

    func testGenerationOfStartersAndHybrids() {
        XCTAssertEqual(CollectingEngine.generation(parents: []), 0)
        let a = creature("a", genome: homozygous([0, 0, 0, 0, 0, 0, 0, 0]), generation: 0)
        let b = creature("b", genome: homozygous([1, 1, 1, 1, 1, 1, 1, 1]), generation: 2)
        XCTAssertEqual(CollectingEngine.generation(parents: [a, a]), 1)
        XCTAssertEqual(CollectingEngine.generation(parents: [a, b]), 3)
        let child = CollectingEngine.withLineage(creature("c", genome: a.genome), parents: [a, b])
        XCTAssertEqual(child.generation, 3)
        XCTAssertEqual(child.parentIds, ["a", "b"])
    }

    func testStarterIsGenerationZero() {
        let s = CreatureFactory.starter(playerId: "p1", slot: 0, name: "M", origin: .hatched,
                                        bornAt: noon, alreadyAdult: false, now: noon)
        XCTAssertEqual(s?.generation, 0)
        XCTAssertNil(s?.parentIds)
    }

    // MARK: Combo key

    func testComboKeyIsStableAndIgnoresTemperIdAndShift() {
        let genome: Genome = [[0, 4], [7, 0], [2, 1], [5, 3], [0, 0], [12, 15], [2, 1], [8, 9]]
        let a = Creature(id: "a", name: "A", genome: genome, origin: .bred, paletteShift: 0, bornAt: noon)
        var otherTemper = genome
        otherTemper[7] = [0, 0]
        let b = Creature(id: "zzz", name: "B", genome: otherTemper, origin: .bred, paletteShift: 1, bornAt: noon)
        XCTAssertEqual(a.comboKey, "4-7-1-3-0-15-1")
        XCTAssertEqual(a.comboKey, b.comboKey)
        // Allele order does not matter, only what is expressed.
        let swapped = genome.map { [$0[1], $0[0]] }
        XCTAssertEqual(try Collecting.comboKey(genome: swapped), a.comboKey)
        XCTAssertNil(Creature(id: "bad", name: "x", genome: [[99, 99]], origin: .bred, bornAt: noon).comboKey)
    }

    // MARK: Discovery log

    func testDiscoveryLogFlagsFirstBredLookOnly() {
        var save = SaveData(playerId: "p")
        let look = homozygous([1, 2, 3, 1, 2, 3, 1, 0])
        save.replace(creature("c1", genome: look))
        save.replace(creature("c2", genome: look))
        save.replace(creature("s1", genome: homozygous([0, 0, 0, 0, 0, 0, 0, 0]), origin: .starter))
        XCTAssertEqual(save.creature(id: "c1")?.discoveredFirst, true)
        XCTAssertEqual(save.creature(id: "c2")?.discoveredFirst, false)
        XCTAssertEqual(save.creature(id: "s1")?.discoveredFirst, false, "starters are gifts, not discoveries")
        XCTAssertEqual(save.discoveries.count, 2)
        XCTAssertEqual(save.discoveries.entries["1-2-3-1-2-3-1"]?.creatureId, "c1")
        // Serial = local hatch counter, assigned once.
        XCTAssertEqual(save.creatures.map(\.serial), [1, 2, 3])
        var c1 = save.creature(id: "c1")!
        c1.name = "Renamed"
        save.replace(c1)
        XCTAssertEqual(save.creature(id: "c1")?.serial, 1)
        XCTAssertEqual(save.hatchCounter, 3)
    }

    func testGroupedSerial() {
        XCTAssertEqual(CollectingEngine.groupedSerial(7), "7")
        XCTAssertEqual(CollectingEngine.groupedSerial(1287), "1\u{00A0}287")
        XCTAssertEqual(CollectingEngine.groupedSerial(1_000_000), "1\u{00A0}000\u{00A0}000")
    }

    // MARK: Seasons

    func testSeasonOneShape() {
        let s = Collecting.season1
        XCTAssertEqual(s.entries.count, 12)
        XCTAssertEqual(Set(s.entries).count, 12)
        var byRarity = [0, 0, 0, 0]
        for e in s.entries {
            let v = Catalog.genes[e.gene].variants[e.variant]
            XCTAssertFalse(v.mutationOnly)
            byRarity[v.rarity] += 1
        }
        XCTAssertEqual(byRarity, [5, 4, 3, 0])
        XCTAssertEqual(CollectingEngine.currentSeason(now: noon, timeZone: utc)?.id, "s1")
    }

    func testSeasonProgressCountsExpressedVariants() {
        // catears + belly + happy eyes + puff tail (4 entries), expressed via dominance.
        let a = creature("a", genome: [[0, 1], [2, 3], [1, 1], [1, 0], [0, 1], [0, 2], [0, 0], [1, 2]])
        // leaf, spots, sparkle, flame, star eyes, night (6 entries), homozygous.
        let b = creature("b", genome: homozygous([1, 6, 5, 2, 4, 12, 1, 3]))
        // Carried but NOT expressed: mint palette recessive to sky -> must not count.
        let c = creature("c", genome: [[0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 2], [0, 0], [0, 0]])
        let s = Collecting.season1
        XCTAssertEqual(CollectingEngine.foundCount(s, creatures: []), 0)
        XCTAssertEqual(CollectingEngine.foundCount(s, creatures: [a]), 4)
        XCTAssertEqual(CollectingEngine.foundCount(s, creatures: [a, b]), 10)
        XCTAssertEqual(CollectingEngine.foundCount(s, creatures: [a, b, c]), 10)
        XCTAssertFalse(CollectingEngine.isComplete(s, creatures: [a, b]))

        // Mint palette + horns completes it.
        let d = creature("d", genome: homozygous([0, 0, 3, 0, 0, 0, 0, 0]))
        XCTAssertTrue(CollectingEngine.isComplete(s, creatures: [a, b, d]))
        XCTAssertEqual(CollectingEngine.owner(of: Collecting.SeasonEntry(gene: 2, variant: 3), in: [a, b, d])?.id, "d")

        var save = SaveData(playerId: "p", creatures: [a, b])
        CollectingEngine.awardSeasonBadges(&save, now: noon, timeZone: utc)
        XCTAssertTrue(save.seasonBadges.isEmpty)
        save.creatures.append(d)
        CollectingEngine.awardSeasonBadges(&save, now: noon, timeZone: utc)
        CollectingEngine.awardSeasonBadges(&save, now: noon, timeZone: utc)
        XCTAssertEqual(save.seasonBadges, ["s1"])
        save.creatures.removeAll()
        CollectingEngine.awardSeasonBadges(&save, now: noon, timeZone: utc)
        XCTAssertEqual(save.seasonBadges, ["s1"], "badges are never taken away")
    }

    func testSeasonSampleCreatureExpressesEntry() throws {
        for e in Collecting.season1.entries {
            let c = CollectingEngine.sampleCreature(for: e)
            XCTAssertEqual(try Genetics.express(c.genome)[e.gene], e.variant)
        }
    }

    // MARK: Daily surprise

    func testDayKeyUsesLocalCalendarDay() {
        let late = Date(timeIntervalSince1970: 1_792_884_600) // 2026-10-24 23:30 UTC
        XCTAssertEqual(CollectingEngine.dayKey(late, timeZone: utc), "2026-10-24")
        XCTAssertEqual(CollectingEngine.dayKey(late, timeZone: plus3), "2026-10-25")
        XCTAssertEqual(CollectingEngine.dayKey(Date(timeIntervalSince1970: 0), timeZone: utc), "1970-01-01")
    }

    func testDailySurpriseMatchesEngineGoldenValues() {
        // Same values as engine-ts golden vectors (collecting.surprises).
        XCTAssertEqual(Collecting.dailySurprise(playerId: "", day: "2026-10-24"), .sparks(15))
        XCTAssertEqual(Collecting.dailySurprise(playerId: "p1", day: "2026-10-24"), .cosmetic("tiny_scarf"))
    }

    func testDailySurpriseIsDeterministicAndInRange() {
        let save = SaveData(playerId: "player-x")
        let a = CollectingEngine.surprise(for: save, now: noon, timeZone: utc)
        let b = CollectingEngine.surprise(for: save, now: noon.addingTimeInterval(3600), timeZone: utc)
        XCTAssertEqual(a, b, "same local day -> same souvenir")
        for i in 0..<120 {
            let s = CollectingEngine.surprise(for: save, now: noon.addingTimeInterval(Double(i) * day), timeZone: utc)
            switch s {
            case .sparks(let n): XCTAssertTrue((5...25).contains(n))
            case .cosmetic(let id): XCTAssertTrue(Collecting.surpriseCosmetics.contains(id))
            }
        }
    }

    func testDailySurpriseOncePerDay() {
        var save = SaveData(playerId: "p1")
        XCTAssertTrue(CollectingEngine.canOpenSurprise(save, now: noon, timeZone: utc))
        let first = CollectingEngine.openSurprise(&save, now: noon, timeZone: utc)
        XCTAssertNotNil(first)
        XCTAssertEqual(save.lastSurpriseDay, "2026-10-24")
        let sparksAfterFirst = save.sparks
        let cosmeticsAfterFirst = save.cosmetics

        // Same day, later: refused, nothing changes.
        XCTAssertFalse(CollectingEngine.canOpenSurprise(save, now: noon.addingTimeInterval(11 * 3600), timeZone: utc))
        XCTAssertNil(CollectingEngine.openSurprise(&save, now: noon.addingTimeInterval(11 * 3600), timeZone: utc))
        XCTAssertEqual(save.sparks, sparksAfterFirst)
        XCTAssertEqual(save.cosmetics, cosmeticsAfterFirst)

        // Next local day: available again, reward applied.
        let tomorrow = noon.addingTimeInterval(day)
        let second = CollectingEngine.openSurprise(&save, now: tomorrow, timeZone: utc)
        XCTAssertNotNil(second)
        XCTAssertEqual(save.lastSurpriseDay, "2026-10-25")
        switch second {
        case .sparks(let n)?: XCTAssertEqual(save.sparks, sparksAfterFirst + n)
        case .cosmetic(let id)?: XCTAssertEqual(save.cosmetics.last, id)
        case nil: XCTFail("expected a souvenir")
        }
        // Rewards follow the documented first-day value for "p1" (cosmetic tiny_scarf).
        XCTAssertEqual(first, .cosmetic("tiny_scarf"))
        XCTAssertTrue(cosmeticsAfterFirst.contains("tiny_scarf"))
    }

    // MARK: Trade stub

    func testTradeOfferRoundTripsAndHasPlaceholderLink() throws {
        let offer = TradeOffer(id: "abc123", creatureId: "c1", createdAt: noon)
        XCTAssertEqual(offer.status, .draft)
        XCTAssertEqual(offer.url.absoluteString, "https://mix.orizolabs.app/t/abc123")
        let data = try JSONEncoder().encode(offer)
        XCTAssertEqual(try JSONDecoder().decode(TradeOffer.self, from: data), offer)
    }
}

extension CollectingTests {
    func testReplaceKeepsSerialFromStaleCopy() {
        var save = SaveData(playerId: "p")
        let fresh = creature("e", genome: homozygous([0, 0, 0, 0, 0, 0, 0, 0]), origin: .hatched)
        save.replace(fresh)               // registered: serial 1
        var stale = fresh                 // copy taken before registration (serial nil)
        stale.name = "Baby"
        save.replace(stale)
        XCTAssertEqual(save.creature(id: "e")?.serial, 1)
        XCTAssertEqual(save.creature(id: "e")?.name, "Baby")
        XCTAssertEqual(save.hatchCounter, 1)
    }
}
