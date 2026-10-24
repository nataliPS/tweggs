import XCTest
import MixlingsGenome
@testable import Mixlings

/// Dev mode weather provider, age bands 2026-10-24 (under13 / 13to15 / 16to17 / 18plus),
/// wellbeing MVP (docs/wellbeing-spec.md) and the calm activity.
final class WellbeingAndDevModeTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    /// 2026-10-24 12:00:00 UTC (Saturday).
    private let noon = Date(timeIntervalSince1970: 1_792_843_200)
    private let hour: TimeInterval = 3600
    private func at(_ h: Double) -> Date { noon.addingTimeInterval((h - 12) * hour) }

    // MARK: Weather provider selection

    func testProviderSelectionNeverUsesWeatherKitWithoutFlag() {
        XCTAssertEqual(WeatherProviders.kind(weatherKitCompiled: false), .simulated)
        XCTAssertEqual(WeatherProviders.kind(weatherKitCompiled: true), .apple)
        #if TWEGGS_WEATHERKIT
        XCTAssertEqual(WeatherProviders.make().kind, .apple)
        #else
        XCTAssertFalse(WeatherProviders.weatherKitCompiled)
        XCTAssertEqual(WeatherProviders.currentKind, .simulated)
        XCTAssertEqual(WeatherProviders.make().kind, .simulated)
        XCTAssertFalse(WeatherProviders.make().needsPlace, "simulated weather needs no location")
        #endif
    }

    func testSimulatedWeatherIsDeterministicPerDay() {
        let a = SimulatedWeatherProvider.snapshot(now: noon, timeZone: utc)
        let b = SimulatedWeatherProvider.snapshot(now: noon, timeZone: utc)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hourly.count, 26)
        XCTAssertEqual(a.sun.first?.day, "2026-10-24")
        XCTAssertFalse(a.needsRefresh(now: noon))
        // Never produces .night (that is the state machine's job) and varies across a month.
        var kinds = Set<WeatherKind>()
        for d in 0..<60 {
            for h in [9.0, 12, 15] {
                let k = SimulatedWeatherProvider.simulatedKind(at: at(h).addingTimeInterval(Double(d) * 86_400), timeZone: utc)
                XCTAssertNotEqual(k, .night)
                kinds.insert(k)
            }
        }
        XCTAssertGreaterThan(kinds.count, 2)
    }

    func testSimulatedWeatherForcedKinds() {
        XCTAssertEqual(SimulatedWeatherProvider.snapshot(now: noon, timeZone: utc, forced: .rain).kind(at: noon), .rain)
        XCTAssertEqual(SimulatedWeatherProvider.snapshot(now: noon, timeZone: utc, forced: .heat).kind(at: noon), .heat)
        XCTAssertEqual(SimulatedWeatherProvider.snapshot(now: noon, timeZone: utc, forced: .snow).kind(at: noon), .snow)
        XCTAssertEqual(SimulatedWeatherProvider.snapshot(now: noon, timeZone: utc, forced: .wind).kind(at: noon), .wind)
        XCTAssertEqual(SimulatedWeatherProvider.snapshot(now: noon, timeZone: utc, forced: .clear).kind(at: noon), .none)
        let night = SimulatedWeatherProvider.snapshot(now: noon, timeZone: utc, forced: .night)
        let ctx = ActivityContext(timeZone: utc, weather: night)
        XCTAssertEqual(ActivityStateMachine.activity(at: noon, context: ctx).kind, .sleeping)
        // Normal days: sunrise 07:00, sunset 19:00 local.
        let normal = ActivityContext(timeZone: utc, weather: SimulatedWeatherProvider.snapshot(now: noon, timeZone: utc))
        XCTAssertFalse(ActivityStateMachine.isNight(at: noon, context: normal))
        XCTAssertTrue(ActivityStateMachine.isNight(at: at(19.5), context: normal))
    }

    // MARK: Age bands

    func testAgeBandRawValuesMatchServer() {
        XCTAssertEqual(AgeBand.allCases.map(\.rawValue), ["under13", "13to15", "16to17", "18plus"])
        XCTAssertTrue(AgeBand.under13 < .teen13to15 && .teen13to15 < .teen16to17 && .teen16to17 < .adult18plus)
    }

    func testLegacyAgeBandsMigrateToYoungerBand() throws {
        for legacy in ["13to17", "teen13to17"] {
            let json = #"{"version":3,"playerId":"p","ageBand":"\#(legacy)"}"#
            let save = try JSONDecoder().decode(SaveData.self, from: Data(json.utf8))
            XCTAssertEqual(save.ageBand, .teen13to15, legacy)
            XCTAssertTrue(save.socialAllowed)
            // Re-encoded with the new raw value.
            let out = String(decoding: try JSONEncoder().encode(save), as: UTF8.self)
            XCTAssertTrue(out.contains(#""ageBand":"13to15""#), out)
        }
        let old18 = try JSONDecoder().decode(SaveData.self, from: Data(#"{"playerId":"p","version":3,"ageBand":"adult18plus"}"#.utf8))
        XCTAssertEqual(old18.ageBand, .adult18plus)
        let kid = try JSONDecoder().decode(SaveData.self, from: Data(#"{"playerId":"p","version":3,"ageBand":"under13"}"#.utf8))
        XCTAssertEqual(kid.ageBand, .under13)
        XCTAssertFalse(kid.socialAllowed, "under13 stays offline")
    }

    func testDuoFramingIsBestFriendsUnder16() {
        XCTAssertEqual(AgeGate.duoFraming(for: .teen13to15), .bestFriends)
        XCTAssertEqual(AgeGate.duoFraming(for: .teen13to15, wanted: .duo), .bestFriends)
        XCTAssertEqual(AgeGate.duoFraming(for: .under13), .bestFriends)
        XCTAssertEqual(AgeGate.duoFraming(for: nil), .bestFriends, "unknown age fails closed")
        XCTAssertEqual(AgeGate.duoFraming(for: .teen16to17), .duo)
        XCTAssertEqual(AgeGate.duoFraming(for: .adult18plus, wanted: .bestFriends), .bestFriends)
        XCTAssertEqual(AgeGate.duoFraming(for: [.adult18plus, .teen16to17]), .duo)
        XCTAssertEqual(AgeGate.duoFraming(for: [.adult18plus, .teen13to15]), .bestFriends)
        XCTAssertEqual(AgeGate.duoFraming(for: [AgeBand?]()), .bestFriends)
        XCTAssertFalse(AgeBand.under13.duoAllowed)
        XCTAssertTrue(AgeBand.teen13to15.duoAllowed)
    }

    // MARK: Helplines & content JSON

    func testBundledHelplinesDecodeAndCoverCountries() throws {
        let dir = try XCTUnwrap(HelplineDirectory.load(bundle: Bundle(for: GameModel.self)) ?? HelplineDirectory.load(bundle: .main),
                                "Helplines.json missing from the app bundle")
        XCTAssertEqual(Set(dir.countries.map(\.code)), ["UA", "EE", "LV", "LT", "PL", "DE", "GB", "US", "CA", "AU"])
        XCTAssertEqual(dir.fallback.url, URL(string: "https://findahelpline.com"))
        XCTAssertFalse(dir.verified, "flip only after Щит verifies the table")
        XCTAssertEqual(dir.country("UK")?.code, "GB")
        XCTAssertEqual(dir.country("us")?.lines.first?.number, "988")
        XCTAssertEqual(dir.country("UA")?.lines.first { $0.id == "ua.lifeline" }?.number, "7333")
        XCTAssertEqual(dir.country("GB")?.lines.first { $0.id == "gb.samaritans" }?.number, "116123")
        for c in dir.countries {
            XCTAssertFalse(c.lines.isEmpty, c.code)
            for l in c.lines {
                XCTAssertFalse(l.name.isEmpty)
                XCTAssertTrue(l.number.allSatisfy(\.isNumber), "\(l.id): digits only or empty")
                XCTAssertEqual(l.hasNumber, l.telURL != nil)
            }
        }
        let split = dir.ordered(region: "PL")
        XCTAssertEqual(split.local?.code, "PL")
        XCTAssertFalse(split.others.contains { $0.code == "PL" })
        XCTAssertNil(dir.ordered(region: "FR").local, "unknown region -> fallback link + list")
    }

    func testHelplineWithEmptyNumberDecodes() throws {
        let json = #"""
        {"version":1,"verified":false,"fallback":{"name":"F","website":"https://findahelpline.com"},
         "countries":[{"code":"XX","emergency":null,"lines":[{"id":"x","name":"Line","number":"","website":null,"kind":"youth"}]}]}
        """#
        let dir = try HelplineDirectory.decode(Data(json.utf8))
        let line = try XCTUnwrap(dir.countries.first?.lines.first)
        XCTAssertFalse(line.hasNumber)
        XCTAssertNil(line.telURL)
        XCTAssertNil(line.websiteURL)
    }

    func testWellbeingContentHasEnUkAndIsPendingReview() throws {
        let content = try XCTUnwrap(WellbeingContent.load(bundle: Bundle(for: GameModel.self)) ?? WellbeingContent.load(bundle: .main),
                                    "WellbeingContent.json missing from the app bundle")
        XCTAssertEqual(Set(content.items.map(\.id)).count, content.items.count, "ids are unique")
        for id in ["calm.title", "breathe.in", "breathe.out", "grounding.see", "grounding.taste",
                   "hardtime.button", "helplines.find", "winddown.yawn", "review.pending"] {
            XCTAssertNotNil(content.item(id), id)
        }
        for i in content.items {
            XCTAssertFalse(i.text_en.isEmpty, i.id)
            XCTAssertFalse(i.text_uk.isEmpty, i.id)
        }
        XCTAssertTrue(content.pendingReview, "nothing is signed off yet")
        XCTAssertEqual(content.text("calm.title", language: .uk), "Хвилинка спокою")
        XCTAssertGreaterThanOrEqual(content.windDownThoughtIds.count, 3)
        XCTAssertEqual(content.windDownThought(now: noon, timeZone: utc), content.windDownThought(now: noon, timeZone: utc))
        // Kind thoughts follow the same guardrails as creature lines.
        for id in content.windDownThoughtIds {
            XCTAssertNotNil(LineGuard.filter(content.text(id, language: .en)), id)
            XCTAssertNotNil(LineGuard.filter(content.text(id, language: .uk)), id)
        }
    }

    // MARK: No-reward rule

    func testWellbeingNeverGrantsSparksOrItems() {
        var save = SaveData(playerId: "p")
        save.sparks = 17
        let before = save
        XCTAssertEqual(WellbeingEngine.sparksPerPractice, 0)
        for p in WellbeingPractice.allCases {
            WellbeingEngine.recordOpen(p, save: &save)
            WellbeingEngine.recordCompletion(p, save: &save)
        }
        WellbeingEngine.finishBreathing(save: &save, now: noon)
        WellbeingEngine.recordCalmer(true, save: &save)
        XCTAssertEqual(save.sparks, before.sparks)
        XCTAssertEqual(save.living, before.living, "no spark cap use, no items")
        XCTAssertEqual(save.cosmetics, before.cosmetics)
        XCTAssertEqual(save.creatures, before.creatures)
        XCTAssertEqual(save.wellbeing.opens["breathe"], 1)
        XCTAssertEqual(save.wellbeing.completions["breathe"], 2)
        XCTAssertEqual(save.wellbeing.calmerYes, 1)

        WellbeingEngine.resetStats(save: &save)
        XCTAssertTrue(save.wellbeing.opens.isEmpty)
        XCTAssertNil(save.wellbeing.calmUntil)
    }

    func testOldSaveWithoutWellbeingLoads() throws {
        let save = try JSONDecoder().decode(SaveData.self, from: Data(#"{"version":3,"playerId":"p"}"#.utf8))
        XCTAssertEqual(save.wellbeing, WellbeingState())
        XCTAssertFalse(save.wellbeing.windDownEnabled, "wind-down is opt-in")
    }

    // MARK: Calm activity

    func testCalmActivityLastsThirtyMinutesAfterBreathing() {
        var save = SaveData(playerId: "p")
        WellbeingEngine.finishBreathing(save: &save, now: at(14))
        let ctx = ActivityContext(timeZone: utc, calmUntil: save.wellbeing.calmUntil)
        let a = ActivityStateMachine.activity(at: at(14.25), context: ctx)
        XCTAssertEqual(a.kind, .calm)
        XCTAssertEqual(a.scene, .meditating)
        XCTAssertNotEqual(ActivityStateMachine.activity(at: at(14.5), context: ctx).kind, .calm)
        // Night still wins (breathing at bedtime -> the creature falls asleep).
        let late = ActivityContext(timeZone: utc, calmUntil: at(22.4))
        XCTAssertEqual(ActivityStateMachine.activity(at: at(22.1), context: late).kind, .sleeping)
        // The widget timeline sees it too (via active.json).
        let snap = ActiveSnapshot(save: save, now: at(14))
        XCTAssertEqual(snap.calmUntil, save.wellbeing.calmUntil)
        let schedule = ActivityStateMachine.schedule(from: at(14), context: ctx, step: 15 * 60, horizon: hour)
        XCTAssertEqual(schedule.filter { $0.activity.kind == .calm }.map(\.date), [at(14), at(14.25)])
    }

    func testCalmBeatsWeatherButNotFocus() {
        let rain = SimulatedWeatherProvider.snapshot(now: noon, timeZone: utc, forced: .rain)
        let ctx = ActivityContext(timeZone: utc, weather: rain, calmUntil: at(12.4))
        XCTAssertEqual(ActivityStateMachine.activity(at: noon, context: ctx).kind, .calm)
        let focus = ActivityContext(timeZone: utc, weather: rain, focusUntil: at(13), calmUntil: at(12.4))
        XCTAssertEqual(ActivityStateMachine.activity(at: noon, context: focus).kind, .focus)
    }

    func testWindDownIsOptIn() {
        let off = ActivityContext(timeZone: utc)
        let on = ActivityContext(timeZone: utc, windDown: true)
        // Fallback night starts at 21:00, so 20:xx is a daytime routine slot.
        XCTAssertNil(ActivityStateMachine.routineScene(at: at(20.5), timeZone: utc))
        XCTAssertEqual(ActivityStateMachine.activity(at: at(20.5), context: off).kind, .idle)
        XCTAssertEqual(ActivityStateMachine.activity(at: at(20.5), context: on).scene, .windDown)
        // With an earlier sunset (cached weather), wind-down is the first night scene at 20:xx.
        let sim = SimulatedWeatherProvider.snapshot(now: noon, timeZone: utc)
        let nightOn = ActivityContext(timeZone: utc, weather: sim, windDown: true)
        let a = ActivityStateMachine.activity(at: at(20.5), context: nightOn)
        XCTAssertEqual(a.kind, .sleeping)
        XCTAssertEqual(a.scene, .windDown)
    }

    func testBreathingTiming() {
        let s = BreathingSession(rhythm: .fourSix, minutes: 1)
        XCTAssertEqual(s.duration, 60)
        XCTAssertEqual(s.state(elapsed: 0).phase, .breatheIn)
        XCTAssertEqual(s.state(elapsed: 0).fill, 0, accuracy: 0.001)
        XCTAssertEqual(s.state(elapsed: 4).phase, .breatheOut)
        XCTAssertEqual(s.state(elapsed: 4).fill, 1, accuracy: 0.001)
        XCTAssertEqual(s.state(elapsed: 10).phase, .breatheIn)        // 4 + 6
        XCTAssertEqual(s.state(elapsed: 60).phase, .done)
        let fast = BreathingSession(rhythm: .fourFour, minutes: 2)
        XCTAssertEqual(fast.duration, 120)
        XCTAssertEqual(fast.state(elapsed: 8).phase, .breatheIn)
        XCTAssertEqual(BreathingSession(minutes: 9).minutes, 2, "1–2 min only")
        XCTAssertEqual(BreathingSession(minutes: 0).minutes, 1)
    }

    func testGroundingIsFiveToOne() {
        XCTAssertEqual(GroundingStep.ordered.map(\.count), [5, 4, 3, 2, 1])
    }
}
