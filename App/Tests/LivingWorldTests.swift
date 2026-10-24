import XCTest
import MixlingsGenome
@testable import Mixlings

/// Living world MVP (docs/living-world-spec.md §0–§2, §4, §8, §9, §13).
final class LivingWorldTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    /// 2026-10-24 12:00:00 UTC (Saturday).
    private let noon = Date(timeIntervalSince1970: 1_792_843_200)
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 24 * 3600

    private func creature(_ id: String, genome: Genome? = nil, joy: Double = 50) -> Creature {
        let hatched = noon.addingTimeInterval(-10 * day)
        return Creature(id: id, name: id, genome: genome ?? Array(repeating: [0, 0], count: 8), origin: .starter,
                        bornAt: hatched.addingTimeInterval(-day), hatchedAt: hatched,
                        mood: 50, hunger: 50, joy: joy, lastUpdated: noon)
    }

    private func save(with creatures: [Creature]) -> SaveData {
        var s = SaveData(playerId: "player-1")
        for c in creatures { s.replace(c) }
        s.activeCreatureId = creatures.first?.id
        return s
    }

    /// Weather of one kind for the whole local day, sunrise 06:30, sunset 17:00 (UTC).
    private func weather(_ kind: WeatherKind) -> WeatherSnapshot {
        let start = noon.addingTimeInterval(-12 * hour)
        let hours = (0..<36).map { WeatherSnapshot.Hour(date: start.addingTimeInterval(Double($0) * hour),
                                                         kind: kind, temperatureC: 10) }
        let sun = [WeatherSnapshot.Sun(day: "2026-10-24", sunrise: start.addingTimeInterval(6.5 * hour),
                                       sunset: start.addingTimeInterval(17 * hour)),
                   WeatherSnapshot.Sun(day: "2026-10-25", sunrise: start.addingTimeInterval(30.5 * hour),
                                       sunset: start.addingTimeInterval(41 * hour))]
        return WeatherSnapshot(fetchedAt: noon, current: kind, currentTemperatureC: 10, hourly: hours,
                               sun: sun, timeZoneId: "GMT", placeName: nil)
    }

    private func at(_ h: Double) -> Date { noon.addingTimeInterval((h - 12) * hour) }

    // MARK: State machine priority

    func testFocusBeatsNight() {
        let ctx = ActivityContext(timeZone: utc, weather: weather(.rain), focusUntil: at(23))
        XCTAssertEqual(ActivityStateMachine.activity(at: at(22), context: ctx).kind, .focus)
    }

    func testNightBeatsWeatherUsingCachedSunset() {
        let ctx = ActivityContext(timeZone: utc, weather: weather(.rain), pairId: "a+b")
        let evening = ActivityStateMachine.activity(at: at(18), context: ctx)
        XCTAssertEqual(evening.kind, .sleeping)          // after 17:00 sunset, before 21:00 fallback
        XCTAssertEqual(evening.weather, .night)
        XCTAssertTrue(evening.isNight)
        XCTAssertEqual(ActivityStateMachine.activity(at: at(14), context: ctx).kind, .weather)
    }

    func testFallbackNightWithoutWeather() {
        let ctx = ActivityContext(timeZone: utc)
        XCTAssertTrue(ActivityStateMachine.isNight(at: at(21), context: ctx))
        XCTAssertTrue(ActivityStateMachine.isNight(at: at(6.9), context: ctx))
        XCTAssertFalse(ActivityStateMachine.isNight(at: at(7), context: ctx))
        XCTAssertFalse(ActivityStateMachine.isNight(at: at(20.9), context: ctx))
    }

    func testWeatherBeatsPairScene() {
        let ctx = ActivityContext(timeZone: utc, weather: weather(.snow), pairId: "a+b")
        for h in 8..<17 {
            let a = ActivityStateMachine.activity(at: at(Double(h)), context: ctx)
            XCTAssertEqual(a.kind, .weather, "hour \(h)")
            XCTAssertEqual(a.weather, .snow)
        }
    }

    func testPairSceneBeatsRoutineAndRoutineFillsGaps() {
        let ctx = ActivityContext(timeZone: utc, pairId: "a+b")
        let monday = noon.addingTimeInterval(2 * day) // 2026-10-26
        var sawPair = false
        for h in 7..<21 {
            let date = monday.addingTimeInterval(Double(h - 12) * hour)
            let routine = ActivityStateMachine.routineScene(at: date, timeZone: utc)
            let pair = ActivityStateMachine.pairScene(pairId: "a+b", at: date, timeZone: utc, inRoutine: routine != nil)
            let a = ActivityStateMachine.activity(at: date, context: ctx)
            if let pair {
                sawPair = true
                XCTAssertEqual(a.kind, .pairScene, "hour \(h)")
                XCTAssertEqual(a.scene, pair)
            } else if let routine {
                XCTAssertEqual(a.kind, .routine, "hour \(h)")
                XCTAssertEqual(a.scene, routine)
            } else {
                XCTAssertEqual(a.kind, .idle, "hour \(h)")
            }
        }
        XCTAssertTrue(sawPair)
    }

    func testAloneUsesRoutine() {
        let ctx = ActivityContext(timeZone: utc)
        let a = ActivityStateMachine.activity(at: at(7.5), context: ctx)
        XCTAssertEqual(a.kind, .routine)
        XCTAssertEqual(a.scene, .breakfast)
    }

    // MARK: Determinism

    func testPairSeedIsFnvOfPairIdAndDay() {
        XCTAssertEqual(ActivityStateMachine.pairSeed(pairId: "a+b", day: "2026-10-24"), Hash.fnv1a32("a+b|2026-10-24"))
    }

    func testPairScheduleIsDeterministicAndOrderIndependent() {
        let a = creature("a"), b = creature("b")
        XCTAssertEqual(HousePair.pairId(a, b), HousePair.pairId(b, a))
        let ctx = ActivityContext(timeZone: utc, pairId: HousePair.pairId(a, b))
        let s1 = ActivityStateMachine.schedule(from: at(8), context: ctx)
        let s2 = ActivityStateMachine.schedule(from: at(8), context: ctx)
        XCTAssertEqual(s1, s2)
        let other = ActivityStateMachine.schedule(from: at(8), context: ActivityContext(timeZone: utc, pairId: "x+y"))
        XCTAssertNotEqual(s1.map(\.activity.scene), other.map(\.activity.scene))
    }

    func testScheduleCoversTwelveHoursAndMarksMorning() {
        let ctx = ActivityContext(timeZone: utc)
        let s = ActivityStateMachine.schedule(from: at(1), context: ctx, step: 30 * 60, horizon: 12 * hour)
        XCTAssertEqual(s.count, 25)
        XCTAssertEqual(s.last?.date, at(13))
        // 07:00 is the first non-night entry after the night: morning stretch.
        let seven = try? XCTUnwrap(s.first { $0.date == at(7) })
        XCTAssertEqual(seven?.activity.alive, .morning)
        XCTAssertEqual(s.first { $0.date == at(6.5) }?.activity.isNight, true)
        XCTAssertEqual(s.filter { $0.activity.alive == .morning && $0.date > at(8) }.count, 0)
    }

    func testLowPowerNapAndChargingSnack() {
        let lp = DeviceSnapshot(charging: true, lowPower: true, updatedAt: at(14))
        let ctx = ActivityContext(timeZone: utc, device: lp)
        XCTAssertEqual(ActivityStateMachine.activity(at: at(14.5), context: ctx).alive, .lowPower)
        let ch = DeviceSnapshot(charging: true, lowPower: false, updatedAt: at(14))
        XCTAssertEqual(ActivityStateMachine.activity(at: at(14.5), context: ActivityContext(timeZone: utc, device: ch)).alive,
                       .charging)
        // Stale cache is ignored by the widget.
        XCTAssertEqual(ActivityStateMachine.activity(at: at(16), context: ActivityContext(timeZone: utc, device: ch)).alive,
                       AliveFrame.none)
    }

    // MARK: Spark cap

    func testDailySparkCapAcrossSources() {
        var s = save(with: [creature("a")])
        s.sparks = 10
        XCTAssertEqual(EconomyEngine.grantCappedSparks(&s, amount: 40, source: .jumpRope, now: noon, timeZone: utc), 40)
        XCTAssertEqual(EconomyEngine.grantCappedSparks(&s, amount: 40, source: .weatherItem, now: noon, timeZone: utc), 20)
        XCTAssertEqual(EconomyEngine.grantCappedSparks(&s, amount: 5, source: .souvenir, now: noon, timeZone: utc), 0)
        XCTAssertEqual(s.sparks, 10 + EconomyEngine.dailySparkCap)
        XCTAssertEqual(EconomyEngine.sparkCapRemaining(s, now: noon, timeZone: utc), 0)
        // Next local day: the cap resets.
        XCTAssertEqual(EconomyEngine.grantCappedSparks(&s, amount: 5, source: .jumpRope, now: noon + day, timeZone: utc), 5)
        XCTAssertEqual(EconomyEngine.grantCappedSparks(&s, amount: -3, source: .jumpRope, now: noon + day, timeZone: utc), 0)
    }

    func testDailySurpriseIsNotCapped() {
        var s = save(with: [creature("a")])
        EconomyEngine.grantCappedSparks(&s, amount: 999, source: .jumpRope, now: noon, timeZone: utc)
        let before = s.sparks
        let souvenir = CollectingEngine.openSurprise(&s, now: noon, timeZone: utc)
        if case .sparks(let n)? = souvenir { XCTAssertEqual(s.sparks, before + n) }
    }

    // MARK: Weather items (once per event, never a penalty)

    func testRightItemRewardsOncePerWeatherEvent() {
        var s = save(with: [creature("a", joy: 40)])
        let first = LivingEngine.giveItem(.umbrella, to: "a", weather: .rain, save: &s, now: noon, timeZone: utc)
        XCTAssertEqual(first, .rewarded(sparks: LivingEngine.itemSparks))
        XCTAssertEqual(s.sparks, LivingEngine.itemSparks)
        XCTAssertGreaterThan(s.creature(id: "a")!.joy, 40)
        XCTAssertTrue(s.living.owns(.umbrella))
        XCTAssertEqual(LivingEngine.displayedItem(givenItems: s.living.givenItems, weather: .rain, at: noon, timeZone: utc),
                       .umbrella)

        let joyAfter = s.creature(id: "a")!.joy
        let again = LivingEngine.giveItem(.umbrella, to: "a", weather: .rain, save: &s, now: noon + hour, timeZone: utc)
        XCTAssertEqual(again, .alreadyRewarded)
        XCTAssertEqual(s.sparks, LivingEngine.itemSparks)
        XCTAssertGreaterThanOrEqual(s.creature(id: "a")!.joy, CareEngine.decay(creature("a", joy: joyAfter), to: noon + hour).joy - 0.001)

        // A different weather the same day is a new event.
        XCTAssertEqual(LivingEngine.giveItem(.scarf, to: "a", weather: .snow, save: &s, now: noon + 2 * hour, timeZone: utc),
                       .rewarded(sparks: LivingEngine.itemSparks))
        // Rain again tomorrow: new event.
        XCTAssertEqual(LivingEngine.giveItem(.umbrella, to: "a", weather: .rain, save: &s, now: noon + day, timeZone: utc),
                       .rewarded(sparks: LivingEngine.itemSparks))
    }

    func testWrongItemNeverPenalises() {
        var s = save(with: [creature("a", joy: 40)])
        let before = s.creature(id: "a")!
        XCTAssertEqual(LivingEngine.giveItem(.fan, to: "a", weather: .rain, save: &s, now: noon, timeZone: utc), .notNeeded)
        let after = s.creature(id: "a")!
        XCTAssertEqual(s.sparks, 0)
        XCTAssertGreaterThanOrEqual(after.joy, before.joy)
        XCTAssertGreaterThanOrEqual(after.mood, before.mood)
        XCTAssertGreaterThanOrEqual(after.hunger, before.hunger)
        // Wind has no right item at all.
        XCTAssertTrue(LivingEngine.suggestedItems(for: .wind).isEmpty)
    }

    func testItemRewardRespectsCap() {
        var s = save(with: [creature("a")])
        EconomyEngine.grantCappedSparks(&s, amount: EconomyEngine.dailySparkCap, source: .jumpRope, now: noon, timeZone: utc)
        XCTAssertEqual(LivingEngine.giveItem(.umbrella, to: "a", weather: .rain, save: &s, now: noon, timeZone: utc),
                       .rewarded(sparks: 0))
    }

    // MARK: Diary

    func testDiaryIsCappedAndChronological() {
        let a = creature("a"), b = creature("b")
        let ctx = ActivityContext(timeZone: utc)
        let d = LivingEngine.diary(from: noon - 3 * day, to: noon, a: a, b: b, context: ctx)
        XCTAssertEqual(d.entries.count, LivingEngine.diaryMaxEntries)
        XCTAssertGreaterThan(d.moreCount, 0)
        XCTAssertEqual(d.entries.map(\.date), d.entries.map(\.date).sorted())
        XCTAssertTrue(d.entries.allSatisfy { $0.date < noon })
        XCTAssertEqual(d, LivingEngine.diary(from: noon - 3 * day, to: noon, a: a, b: b, context: ctx))
        for e in d.entries {
            if case .scene(.chess) = e.kind { XCTAssertNotNil(e.winnerId) }
            let line = LineService.diaryLine(e, a: a, b: b, language: .en)
            XCTAssertFalse(line.isEmpty)
            XCTAssertLessThanOrEqual(line.count, LineGuard.maxLength)
        }
    }

    func testShortAbsenceHasNoDiary() {
        let d = LivingEngine.diary(from: noon, to: noon + 30 * 60, a: creature("a"), b: nil,
                                   context: ActivityContext(timeZone: utc))
        XCTAssertTrue(d.entries.isEmpty)
        XCTAssertEqual(d.moreCount, 0)
    }

    func testDiaryCollapsesRepeats() {
        let ctx = ActivityContext(timeZone: utc, weather: weather(.rain))
        let d = LivingEngine.diary(from: at(8), to: at(16), a: creature("a"), b: nil, context: ctx)
        XCTAssertEqual(d.entries.count, 1)
        XCTAssertEqual(d.entries.first?.kind, .weather(.rain))
    }

    // MARK: Likes

    func testLikesAreDeterministicFromGenome() {
        let g: Genome = [[0, 4], [7, 0], [2, 1], [5, 3], [0, 0], [12, 15], [2, 1], [8, 9]]
        let l1 = Likes.derive(for: creature("a", genome: g))
        let l2 = Likes.derive(for: creature("totally-different-id", genome: g))
        XCTAssertEqual(l1, l2)
        XCTAssertEqual(l1, Likes.derive(genome: g))
        XCTAssertEqual(l1.feeling(about: l1.likes), .loves)
        XCTAssertEqual(l1.feeling(about: l1.dislikes), .dislikes)
    }

    func testLikesNeverEqualDislikesAndVary() {
        var seen = Set<WeatherKind>()
        for i in 0..<60 {
            let g: Genome = (0..<8).map { [($0 + i) % 4, (i / 4 + $0) % 3] }
            let l = Likes.derive(genome: g)
            XCTAssertNotEqual(l.likes, l.dislikes)
            XCTAssertTrue(Likes.weatherPool.contains(l.likes))
            XCTAssertTrue(Likes.weatherPool.contains(l.dislikes))
            seen.insert(l.likes)
        }
        XCTAssertGreaterThan(seen.count, 2)
    }

    // MARK: Lines & guardrails

    func testAllTemplatesPassGuardrails() {
        let longName = "Abcdefghijklmnop" // NameFilter.maxLength letters
        for lang in [LineLanguage.en, .uk] {
            for cat in LineCategory.allCases where cat != .chat {
                for temper in 0..<10 {
                    for w in WeatherKind.allCases {
                        for scene in [nil] + LifeScene.allCases.map(Optional.some) {
                            for t in LineTemplates.pool(cat, language: lang, temper: temper, weather: w, scene: scene) {
                                let text = t.replacingOccurrences(of: "{name}", with: longName)
                                    .replacingOccurrences(of: "{other}", with: longName)
                                    .replacingOccurrences(of: "{winner}", with: longName)
                                XCTAssertNotNil(LineGuard.filter(text), "\(lang) \(cat): \(t)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testGuardRejectsUnsafeLines() {
        XCTAssertNil(LineGuard.filter("I'm sad you left me"))
        XCTAssertNil(LineGuard.filter("Try this diet today!"))
        XCTAssertNil(LineGuard.filter("Ask your doctor about it"))
        XCTAssertNil(LineGuard.filter("Visit www.example.com"))
        XCTAssertNil(LineGuard.filter(String(repeating: "a", count: 81)))
        XCTAssertEqual(LineGuard.filter("  \"Puddles! Splash time!\"  "), "Puddles! Splash time!")
    }

    func testTemplateIsDeterministicAndTemplateLinesAreNotAI() {
        let l1 = LineService.template(.weather, seed: "s", language: .en, name: "Pip", weather: .rain)
        let l2 = LineService.template(.weather, seed: "s", language: .en, name: "Pip", weather: .rain)
        XCTAssertEqual(l1, l2)
        XCTAssertFalse(l1.byAI)
    }

    func testAtMostTwoNudgesPerDay() {
        let dates = NudgePlanner.plannedDates(from: at(0), days: 3, timeZone: utc)
        let perDay = Dictionary(grouping: dates) { CollectingEngine.dayKey($0, timeZone: utc) }
        XCTAssertTrue(perDay.values.allSatisfy { $0.count <= NudgePlanner.maxPerDay })
        XCTAssertTrue(dates.allSatisfy { !ActivityStateMachine.isNight(at: $0, context: ActivityContext(timeZone: utc)) })
    }

    // MARK: Jump rope & ideas

    func testJumpRopeTiming() {
        var g = JumpRopeGame(startedAt: noon)
        XCTAssertEqual(g.tap(at: noon + 0.1), .miss)              // rope overhead
        XCTAssertEqual(g.tap(at: noon + 0.5), .jump)              // under the feet
        XCTAssertEqual(g.tap(at: noon + 0.52), .miss)             // one jump per turn
        XCTAssertEqual(g.combo, 0)
        XCTAssertEqual(g.bestCombo, 1)
        XCTAssertEqual(g.tap(at: noon + JumpRopeGame.duration + 1), .ignored)
        XCTAssertTrue((20...40).contains(Int(JumpRopeGame.duration)))
    }

    func testJumpRopeRewardsAreCappedAndBestKept() {
        var s = save(with: [creature("a")])
        let r1 = LivingEngine.finishJumpRope(&s, creatureId: "a", score: 30, bestCombo: 500, now: noon, timeZone: utc)
        XCTAssertEqual(r1.sparks, LivingEngine.ropeSparksPerGameMax)
        XCTAssertTrue(r1.newBest)
        XCTAssertTrue(r1.gotRope)
        let r2 = LivingEngine.finishJumpRope(&s, creatureId: "a", score: 10, bestCombo: 10, now: noon, timeZone: utc)
        XCTAssertFalse(r2.newBest)
        XCTAssertFalse(r2.gotRope)
        XCTAssertEqual(s.living.jumpRopeBest, 30)
        for _ in 0..<10 { LivingEngine.finishJumpRope(&s, creatureId: "a", score: 1, bestCombo: 100, now: noon, timeZone: utc) }
        XCTAssertLessThanOrEqual(s.living.sparkCapEarned, EconomyEngine.dailySparkCap)
    }

    func testIdeasMaxTwoPerDay() {
        var s = save(with: [creature("a")])
        let late = at(20)
        XCTAssertTrue(LivingEngine.ideaAvailable(s, now: late, timeZone: utc))
        LivingEngine.consumeIdea(&s, now: late, timeZone: utc)
        XCTAssertTrue(LivingEngine.ideaAvailable(s, now: late, timeZone: utc))
        LivingEngine.consumeIdea(&s, now: late, timeZone: utc)
        XCTAssertFalse(LivingEngine.ideaAvailable(s, now: late, timeZone: utc))
        XCTAssertFalse(LivingEngine.ideaAvailable(save(with: [creature("a")]), now: at(9), timeZone: utc))
    }

    // MARK: Holidays, weather classification, persistence

    func testHolidays() {
        func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
            return cal.date(from: DateComponents(year: y, month: m, day: day, hour: 12))!
        }
        XCTAssertEqual(HolidayCalendar.holiday(on: d(2026, 8, 24), timeZone: utc), .independenceDay)
        XCTAssertEqual(HolidayCalendar.holiday(on: d(2026, 10, 31), timeZone: utc), .halloween)
        XCTAssertEqual(HolidayCalendar.holiday(on: d(2026, 12, 31), timeZone: utc), .winter)
        XCTAssertEqual(HolidayCalendar.holiday(on: d(2027, 1, 3), timeZone: utc), .winter)
        XCTAssertEqual(HolidayCalendar.holiday(on: d(2027, 2, 14), timeZone: utc), .valentines)
        XCTAssertEqual(HolidayCalendar.holiday(on: d(2027, 3, 1), timeZone: utc), .spring)
        XCTAssertNil(HolidayCalendar.holiday(on: d(2026, 6, 10), timeZone: utc))
        XCTAssertTrue(Holiday.independenceDay.decorations.contains(.vyshyvanka))
    }

    func testWeatherClassification() {
        XCTAssertEqual(WeatherClassifier.classify(condition: "drizzle", temperatureC: 15, windKmh: 5, uvIndex: 1), .rain)
        XCTAssertEqual(WeatherClassifier.classify(condition: "flurries", temperatureC: 2, windKmh: 5, uvIndex: 1), .snow)
        XCTAssertEqual(WeatherClassifier.classify(condition: "clear", temperatureC: -3, windKmh: 5, uvIndex: 1), .snow)
        XCTAssertEqual(WeatherClassifier.classify(condition: "clear", temperatureC: 29, windKmh: 5, uvIndex: 3), .heat)
        XCTAssertEqual(WeatherClassifier.classify(condition: "clear", temperatureC: 20, windKmh: 5, uvIndex: 9), .heat)
        XCTAssertEqual(WeatherClassifier.classify(condition: "cloudy", temperatureC: 12, windKmh: 35, uvIndex: 1), .wind)
        XCTAssertEqual(WeatherClassifier.classify(condition: "cloudy", temperatureC: 12, windKmh: 10, uvIndex: 1), WeatherKind.none)
    }

    func testWeatherCacheRefreshAndStaleness() {
        let w = weather(.rain)
        XCTAssertFalse(w.needsRefresh(now: noon + 2 * hour))
        XCTAssertTrue(w.needsRefresh(now: noon + 3 * hour))
        var noHours = w
        noHours.hourly = []
        XCTAssertEqual(noHours.kind(at: noon + hour), .rain)
        XCTAssertEqual(noHours.kind(at: noon + 7 * hour), WeatherKind.none) // stale -> neutral
    }

    func testOldSaveWithoutLivingStillLoads() throws {
        let json = #"{"version":3,"playerId":"p","creatures":[]}"#
        let s = try JSONDecoder().decode(SaveData.self, from: Data(json.utf8))
        XCTAssertEqual(s.living, LivingState())
        XCTAssertFalse(s.living.weatherEnabled) // opt-in
        var s2 = s
        s2.living.ownedItems = [1, 8]
        let round = try JSONDecoder().decode(SaveData.self, from: JSONEncoder().encode(s2))
        XCTAssertEqual(round.living.owned, [.umbrella, .jumpRope])
    }

    func testWidgetPokeIsMergedOnce() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let store = CreatureStore(fileURL: url)
        store.save(save(with: [creature("a", joy: 40)]))
        XCTAssertNotNil(store.applyToActive(.poke, at: noon + 60))
        let merged = store.load()
        XCTAssertGreaterThan(merged.creature(id: "a")!.joy, CareEngine.decay(creature("a", joy: 40), to: noon + 60).joy)
        let again = store.update { _ in }
        XCTAssertEqual(again.appliedCareEventIds.count, 1)
    }

    func testSnapshotCarriesPartnerForWidget() {
        let s = save(with: [creature("a"), creature("b")])
        let snap = ActiveSnapshot(save: s, now: noon)
        XCTAssertEqual(snap.partner?.id, "b")
    }
}
