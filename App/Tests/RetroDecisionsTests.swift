import XCTest
import MixlingsGenome
@testable import Mixlings

/// Retro 2026-10-24 app-side decisions: G4–G8, C2, C3, C5, H2, T2, T4.
final class RetroDecisionsTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    /// 2026-10-24 12:00:00 UTC.
    private let noon = Date(timeIntervalSince1970: 1_792_843_200)
    private let day: TimeInterval = 24 * 3600

    private func creature(_ id: String, genome: Genome? = nil, hatchedAgo days: Double = 10,
                          origin: CreatureOrigin = .bred, inSanctuary: Bool = false) -> Creature {
        let hatched = noon.addingTimeInterval(-days * day)
        return Creature(id: id, name: id, genome: genome ?? Array(repeating: [0, 0], count: 8), origin: origin,
                        bornAt: hatched.addingTimeInterval(-day), hatchedAt: hatched,
                        lastUpdated: noon, inSanctuary: inSanctuary)
    }

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).json")
    }

    // MARK: G4 teens breed from day 3

    func testTeensCanBreedFromDayThree() {
        let egg = Creature(id: "e", name: "E", genome: Array(repeating: [0, 0], count: 8),
                           origin: .hatched, bornAt: noon)
        XCTAssertFalse(CareEngine.canBreed(egg, at: noon))
        XCTAssertFalse(CareEngine.canBreed(egg, at: noon + 3 * day - 1))   // baby
        XCTAssertTrue(CareEngine.canBreed(egg, at: noon + 3 * day))        // teen, day 3
        XCTAssertEqual(CareEngine.stage(egg, at: noon + 3 * day), .teen)
        XCTAssertTrue(CareEngine.canBreed(egg, at: noon + 7 * day))        // adult
        XCTAssertEqual(CareEngine.breedingDate(egg), noon + 3 * day)
    }

    // MARK: G5 slots + sanctuary

    func testSlotLimits() {
        XCTAssertEqual(EconomyEngine.slotLimit(isClubMember: false), 8)
        XCTAssertEqual(EconomyEngine.slotLimit(isClubMember: true), 30)
    }

    func testAdmitOverflowsIntoSanctuaryAndNeverDeletes() {
        var save = SaveData(playerId: "p")
        for i in 0..<10 { EconomyEngine.admit(creature("c\(i)"), to: &save) }
        XCTAssertEqual(save.creatures.count, 10)
        XCTAssertEqual(save.activeSlotCreatures.count, 8)
        XCTAssertEqual(save.sanctuaryCreatures.map(\.id), ["c8", "c9"])
        XCTAssertFalse(EconomyEngine.hasFreeSlot(save))

        // Full: can't bring one back until a slot is freed.
        XCTAssertEqual(EconomyEngine.moveToActive(&save, creatureId: "c8").failureValue, .slotsFull)
        XCTAssertNil(EconomyEngine.moveToSanctuary(&save, creatureId: "c0").failureValue)
        XCTAssertNil(EconomyEngine.moveToActive(&save, creatureId: "c8").failureValue)
        XCTAssertEqual(save.creatures.count, 10, "moving never deletes")
        XCTAssertTrue(save.creature(id: "c0")?.inSanctuary ?? false)
        XCTAssertFalse(save.creature(id: "c8")?.inSanctuary ?? true)

        // Club: room for everyone.
        save.isClubMember = true
        XCTAssertNil(EconomyEngine.moveToActive(&save, creatureId: "c0").failureValue)
        XCTAssertNil(EconomyEngine.moveToActive(&save, creatureId: "c9").failureValue)
        XCTAssertTrue(save.sanctuaryCreatures.isEmpty)
    }

    func testLastActiveCreatureStaysAndActiveIdMoves() {
        var save = SaveData(playerId: "p")
        EconomyEngine.admit(creature("a"), to: &save)
        EconomyEngine.admit(creature("b"), to: &save)
        save.activeCreatureId = "a"
        XCTAssertNil(EconomyEngine.moveToSanctuary(&save, creatureId: "a").failureValue)
        XCTAssertEqual(save.activeCreatureId, "b")
        XCTAssertEqual(EconomyEngine.moveToSanctuary(&save, creatureId: "b").failureValue, .lastActive)
    }

    // MARK: G6 sinks

    func testHatchRushCostsSparksOncePerDayAndSkipsADay() throws {
        var save = SaveData(playerId: "p", sparks: 70)
        let baby = creature("b", hatchedAgo: 0.5) // baby; teen in 1.5 days
        save.replace(baby)
        let teenBefore = CareEngine.date(of: .teen, for: baby)

        XCTAssertNil(EconomyEngine.hatchRush(&save, creatureId: "b", now: noon, timeZone: utc).failureValue)
        XCTAssertEqual(save.sparks, 40)
        XCTAssertEqual(save.lastHatchRushDay, "2026-10-24")
        let rushed = try XCTUnwrap(save.creature(id: "b"))
        XCTAssertEqual(CareEngine.date(of: .teen, for: rushed), teenBefore - day)

        // Max 1 per day.
        XCTAssertEqual(EconomyEngine.hatchRush(&save, creatureId: "b", now: noon + 3600, timeZone: utc).failureValue,
                       .alreadyUsedToday)
        XCTAssertEqual(save.sparks, 40)
        // Next day OK; then out of sparks.
        XCTAssertNil(EconomyEngine.hatchRush(&save, creatureId: "b", now: noon + day, timeZone: utc).failureValue)
        XCTAssertEqual(save.sparks, 10)
        XCTAssertEqual(EconomyEngine.hatchRush(&save, creatureId: "b", now: noon + 2 * day, timeZone: utc).failureValue,
                       .notEnoughSparks)
    }

    func testHatchRushRefusedForAdults() {
        var save = SaveData(playerId: "p", sparks: 100)
        save.replace(creature("a", hatchedAgo: 30))
        XCTAssertEqual(EconomyEngine.hatchRush(&save, creatureId: "a", now: noon, timeZone: utc).failureValue, .notGrowing)
        XCTAssertEqual(save.sparks, 100)
    }

    func testHatchRushHatchesAnEggWithoutBackdatingDecay() throws {
        var save = SaveData(playerId: "p", sparks: 30)
        let egg = Creature(id: "e", name: "E", genome: Array(repeating: [0, 0], count: 8),
                           origin: .starter, bornAt: noon - 3600)
        save.replace(egg)
        XCTAssertNil(EconomyEngine.hatchRush(&save, creatureId: "e", now: noon, timeZone: utc).failureValue)
        let c = try XCTUnwrap(save.creature(id: "e"))
        XCTAssertEqual(CareEngine.stage(c, at: noon), .baby)
        XCTAssertEqual(CareEngine.decay(c, to: noon).hunger, egg.hunger, accuracy: 0.0001)
    }

    func testGeneHintChargedOnceAndShopBuys() {
        let season = Collecting.season1
        let entry = season.entries[0]
        var save = SaveData(playerId: "p", sparks: 25)
        XCTAssertNil(EconomyEngine.buyGeneHint(&save, season: season, entry: entry).failureValue)
        XCTAssertEqual(save.sparks, 5)
        XCTAssertNil(EconomyEngine.buyGeneHint(&save, season: season, entry: entry).failureValue, "re-open is free")
        XCTAssertEqual(save.sparks, 5)
        XCTAssertEqual(EconomyEngine.buyGeneHint(&save, season: season, entry: season.entries[1]).failureValue,
                       .notEnoughSparks)

        XCTAssertTrue(EconomyEngine.shopItems.allSatisfy { EconomyEngine.shopPriceRange.contains($0.price) })
        let item = EconomyEngine.shopItems[0]
        save.sparks = item.price
        XCTAssertNil(EconomyEngine.buy(item, save: &save).failureValue)
        XCTAssertEqual(save.sparks, 0)
        XCTAssertEqual(save.cosmetics, [item.id])
        XCTAssertEqual(EconomyEngine.buy(item, save: &save).failureValue, .notEnoughSparks)
    }

    func testGeneHintFindsPairsThatCanProduceEntry() {
        // Season entry: head catears (gene 2, variant 1). One parent carries it recessively.
        let entry = Collecting.SeasonEntry(gene: 2, variant: 1)
        var carrier = Array(repeating: [0, 0], count: 8)
        carrier[2] = [1, 0]
        let a = creature("a", genome: carrier)
        let b = creature("b")
        let baby = creature("c", genome: carrier, hatchedAgo: 0.5) // can't breed yet
        let hint = EconomyEngine.geneHint(entry: entry, creatures: [a, b, baby], now: noon)
        XCTAssertEqual(hint.pairs, [["a", "b"]])
    }

    // MARK: G7 pity hint

    func testPityCounterAndCarriers() {
        let season = Collecting.season1
        var save = SaveData(playerId: "p")
        var carrier = Array(repeating: [0, 0], count: 8)
        carrier[1] = [0, 3] // carries eyes "happy" recessively (dots wins), so happy stays missing
        save.replace(creature("carrier", genome: carrier))
        save.replace(creature("plain"))
        XCTAssertTrue(EconomyEngine.carrierIds(season: season, creatures: save.creatures).contains("carrier"))

        for i in 0..<15 {
            XCTAssertFalse(EconomyEngine.pityHintActive(save))
            EconomyEngine.recordBreed(&save, child: creature("dud\(i)"), season: season)
        }
        XCTAssertEqual(save.breedsWithoutNewEntry, 15)
        XCTAssertTrue(EconomyEngine.pityHintActive(save))

        var lucky = Array(repeating: [0, 0], count: 8)
        lucky[1] = [3, 3] // expresses eyes "happy" (a missing entry)
        EconomyEngine.recordBreed(&save, child: creature("lucky", genome: lucky), season: season)
        XCTAssertEqual(save.breedsWithoutNewEntry, 0)
    }

    // MARK: G8

    func testGenerationBadges() {
        XCTAssertEqual(EconomyEngine.genBadges(generation: 4), [])
        XCTAssertEqual(EconomyEngine.genBadges(generation: 5), [5])
        XCTAssertEqual(EconomyEngine.genBadges(generation: 12), [5, 10])
    }

    // MARK: C2 age band

    func testAgeBandsUseYoungestPossibleAge() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        XCTAssertEqual(AgeGate.band(birthYear: 2014, now: noon, calendar: cal), .under13)  // 11 or 12
        XCTAssertEqual(AgeGate.band(birthYear: 2013, now: noon, calendar: cal), .under13)  // 12 or 13 -> safe side
        XCTAssertEqual(AgeGate.band(birthYear: 2012, now: noon, calendar: cal), .teen13to17)
        XCTAssertEqual(AgeGate.band(birthYear: 2008, now: noon, calendar: cal), .teen13to17) // 17 or 18
        XCTAssertEqual(AgeGate.band(birthYear: 2007, now: noon, calendar: cal), .adult18plus)
        XCTAssertEqual(AgeGate.selectableYears(now: noon, calendar: cal).first, 2026)
    }

    func testSocialOffUntilAgeKnownAndForUnder13() {
        var save = SaveData(playerId: "p")
        XCTAssertFalse(save.socialAllowed)
        save.ageBand = .under13
        XCTAssertFalse(save.socialAllowed)
        save.ageBand = .teen13to17
        XCTAssertTrue(save.socialAllowed)
    }

    // MARK: C3 name filter

    func testNameFilterAcceptsNormalNames() {
        for n in ["Mixy", "Pip", "Зефір", "Пушинка", "Ёжик", "Dickens", "Cockatoo", "Mr. Bean", "Anna-Lu", "R2"] {
            XCTAssertEqual(NameFilter.check(n), .ok(n), n)
        }
        XCTAssertEqual(NameFilter.check("  Bo   Bo "), .ok("Bo Bo"))
    }

    func testNameFilterRejects() {
        XCTAssertEqual(NameFilter.check("   "), .empty)
        XCTAssertEqual(NameFilter.check(String(repeating: "a", count: 17)), .tooLong)
        XCTAssertEqual(NameFilter.check("hi<script>"), .invalidCharacters)
        XCTAssertEqual(NameFilter.check("me@mail.com"), .invalidCharacters) // '@' not allowed at all
        XCTAssertEqual(NameFilter.check("0671234567"), .contactInfo)
        XCTAssertEqual(NameFilter.check("call 067 12 34"), .contactInfo)
        XCTAssertEqual(NameFilter.check("tweggs.com"), .contactInfo)
        XCTAssertEqual(NameFilter.check("www shop"), .contactInfo)
        XCTAssertEqual(NameFilter.check("FuCk"), .blocked)
        XCTAssertEqual(NameFilter.check("sh1t"), .blocked)
        XCTAssertEqual(NameFilter.check("Сука"), .blocked)
        XCTAssertEqual(NameFilter.check("хуйло"), .blocked)
        XCTAssertEqual(NameFilter.check("підор"), .blocked)
        XCTAssertNil(NameFilter.clean("nazi"))
    }

    // MARK: C5 odds

    func testOddsMatchEngine() {
        XCTAssertEqual(Odds.surpriseSparksPercent, 80)
        XCTAssertEqual(Odds.surpriseCosmeticPercent, 20)
        XCTAssertEqual(Odds.sparksMin, 5)
        XCTAssertEqual(Odds.sparksMax, 25)
        XCTAssertEqual(Odds.mutationPercent, 15)
    }

    // MARK: H2 clip timeline

    func testHatchClipTimeline() {
        XCTAssertGreaterThanOrEqual(HatchClipTimeline.duration, 6)
        XCTAssertLessThanOrEqual(HatchClipTimeline.duration, 8)
        XCTAssertEqual(HatchClipTimeline.size.width / HatchClipTimeline.size.height, 9.0 / 16.0, accuracy: 0.001)
        XCTAssertEqual(HatchClipTimeline.size.width * HatchClipTimeline.scale, 1080)
        XCTAssertEqual(HatchClipTimeline.phase(at: 0), .wobble)
        XCTAssertEqual(HatchClipTimeline.phase(at: 1.5), .cracks)
        XCTAssertEqual(HatchClipTimeline.phase(at: 2.4), .flash)
        XCTAssertEqual(HatchClipTimeline.phase(at: 3.0), .drop)
        XCTAssertEqual(HatchClipTimeline.phase(at: 4.0), .reveal)
        XCTAssertEqual(HatchClipTimeline.phase(at: 6.5), .endCard)
    }

    // MARK: T2 persisted starters

    func testStarterGenomeIsPersistedAndNeverRederived() {
        var save = SaveData(playerId: "p1")
        let derived = try! Genetics.starter(playerId: "p1", slot: 2)
        XCTAssertEqual(save.starterGenome(slot: 2), derived)
        XCTAssertEqual(save.starterGenomes["2"], derived)

        // Simulate a future engine change: the stored genome wins.
        var stored = derived
        stored[0] = [3, 3]
        save.starterGenomes["2"] = stored
        let c = CreatureFactory.starter(save: &save, slot: 2, name: "Bo", origin: .starter,
                                        bornAt: noon, alreadyAdult: false, now: noon)
        XCTAssertEqual(c?.genome, stored)
        XCTAssertEqual(c?.id, CreatureFactory.starterId(playerId: "p1", slot: 2))
    }

    func testV2SaveMigratesToV3WithStarterGenomes() throws {
        let pid = "0b6f3c1e-7d2a-4b9e-9c51-2f8d7a6e1b00"
        let eggId = CreatureFactory.starterId(playerId: pid, slot: 0)
        let json = """
        {"version":2,"playerId":"\(pid)","onboardingComplete":true,"activeCreatureId":"\(eggId)",
         "sparks":42,"hatchCounter":2,"cosmetics":["bow_tie"],"seasonBadges":[],"tradeOffers":[],
         "discoveries":{"entries":{}},
         "creatures":[
          {"id":"\(eggId)","name":"Mixy","origin":"hatched","bornAt":783000000,"hatchedAt":783000120,
           "genome":[[0,1],[2,3],[1,1],[1,0],[0,1],[0,2],[0,0],[1,2]],"serial":1,"generation":0,"discoveredFirst":false},
          {"id":"legacy-pip","name":"Pip","origin":"starter","bornAt":782400000,"hatchedAt":782486400,
           "genome":[[1,1],[6,6],[5,5],[2,2],[4,4],[12,12],[1,1],[3,3]],"serial":2,"generation":0,"discoveredFirst":false}
         ]}
        """
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        let save = try d.decode(SaveData.self, from: Data(json.utf8))
        XCTAssertEqual(save.version, 3)
        XCTAssertEqual(save.sparks, 42)
        XCTAssertEqual(save.hatchCounter, 2, "v2 data is not re-migrated")
        XCTAssertEqual(save.creatures.map(\.serial), [1, 2])
        // By deterministic id (slot 0) and by origin fallback (slot 1).
        XCTAssertEqual(save.starterGenomes["0"], [[0, 1], [2, 3], [1, 1], [1, 0], [0, 1], [0, 2], [0, 0], [1, 2]])
        XCTAssertEqual(save.starterGenomes["1"], [[1, 1], [6, 6], [5, 5], [2, 2], [4, 4], [12, 12], [1, 1], [3, 3]])
        XCTAssertNil(save.starterGenomes["2"])
        // New v3 fields: defaults.
        XCTAssertNil(save.ageBand)
        XCTAssertFalse(save.isClubMember)
        XCTAssertEqual(save.breedsWithoutNewEntry, 0)
        XCTAssertFalse(save.creatures.contains { $0.inSanctuary })

        // Round trip stays v3 and equal.
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try d.decode(SaveData.self, from: e.encode(save)), save)
    }

    func testUnknownAgeBandDoesNotBreakSave() throws {
        let json = #"{"version":3,"playerId":"p","ageBand":"someFutureBand"}"#
        let save = try JSONDecoder().decode(SaveData.self, from: Data(json.utf8))
        XCTAssertNil(save.ageBand)
        XCTAssertEqual(save.playerId, "p")
    }

    // MARK: T4 split storage

    func testUpdateWritesWidgetSnapshot() throws {
        let url = tempURL("collection")
        let store = CreatureStore(fileURL: url)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: store.activeURL) }
        store.update { save in
            save.replace(self.creature("a"))
            save.replace(self.creature("b"))
            save.activeCreatureId = "b"
        }
        let snap = try XCTUnwrap(store.loadActive())
        XCTAssertEqual(snap.creature?.id, "b")
        XCTAssertNil(snap.eggHatchesAt)
        // The snapshot is small: it never contains the collection.
        let bytes = try Data(contentsOf: store.activeURL)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("\"a\""))
    }

    func testWidgetCareTouchesOnlyActiveFileAndAppMergesIt() throws {
        let url = tempURL("collection")
        let store = CreatureStore(fileURL: url)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: store.activeURL) }
        var a = creature("a")
        a.hunger = 20
        store.update { $0.replace(a); $0.activeCreatureId = "a" }
        let collectionBefore = try Data(contentsOf: url)

        let snap = try XCTUnwrap(store.applyToActive(.feed, at: noon + 3600))
        XCTAssertGreaterThan(snap.creature?.hunger ?? 0, 20)
        XCTAssertEqual(try Data(contentsOf: url), collectionBefore, "widget never writes collection.json")

        let loaded = store.load()
        XCTAssertEqual(loaded.creature(id: "a")?.hunger ?? 0, snap.creature?.hunger ?? -1, accuracy: 0.0001)
        XCTAssertEqual(loaded.creature(id: "a")?.lastUpdated, noon + 3600)
    }

    func testEggSnapshotHasTimer() throws {
        let url = tempURL("collection")
        let store = CreatureStore(fileURL: url)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: store.activeURL) }
        let egg = Creature(id: "e", name: "E", genome: Array(repeating: [0, 0], count: 8),
                           origin: .hatched, bornAt: noon)
        store.update(now: noon) { $0.replace(egg); $0.activeCreatureId = "e" }
        XCTAssertEqual(store.loadActive()?.eggHatchesAt, noon + day)
    }

    func testLegacySingleFileIsMovedToCollection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = dir.appendingPathComponent(CreatureStore.legacyFileName)
        try Data(#"{"version":2,"playerId":"old-player","creatures":[]}"#.utf8).write(to: legacy)
        let store = CreatureStore(fileURL: dir.appendingPathComponent(CreatureStore.collectionFileName),
                                  activeURL: dir.appendingPathComponent(CreatureStore.activeFileName),
                                  legacyURL: legacy)
        XCTAssertEqual(store.loadOrCreate().playerId, "old-player")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(store.load().version, 3)
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let e) = self { return e }
        return nil
    }
}
