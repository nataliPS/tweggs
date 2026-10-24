import Foundation
import WidgetKit

/// "While you were away" (§9): shown once when the app becomes active after a while.
struct AwayDiary: Identifiable, Equatable {
    let id = UUID()
    let lines: [String]
    let moreCount: Int
    let since: Date
}

/// Living-world actions on the app model. Every write goes through `commit` (one save path).
extension GameModel {
    var living: LivingState { save.living }

    var partner: Creature? { HousePair.partner(in: save, now: .now) }

    func activityContext(now: Date = .now) -> ActivityContext {
        var pairId: String?
        if let a = active, let b = HousePair.partner(in: save, now: now) { pairId = HousePair.pairId(a, b) }
        return ActivityContext(timeZone: .current, weather: save.living.weatherEnabled ? weather : nil,
                               device: device, pairId: pairId, calmUntil: save.wellbeing.calmUntil,
                               windDown: save.wellbeing.windDownEnabled)
    }

    func activity(at now: Date = .now) -> Activity {
        ActivityStateMachine.activity(at: now, context: activityContext(now: now))
    }

    /// The living-world look for the active creature at `now`.
    func look(for c: Creature, activity a: Activity, now: Date = .now) -> LivingLook {
        var item = LivingEngine.displayedItem(givenItems: save.living.givenItems, weather: a.weather, at: now)
        if a.alive == .lowPower { item = .blanket }
        return LivingLook(weather: a.weather, item: item, alive: a.alive)
    }

    // MARK: App lifecycle

    /// Called when the app becomes active: device state, weather refresh, diary, nudges.
    func livingDidBecomeActive(now: Date = .now) {
        DeviceStateMonitor.shared.start()
        device = DeviceStateMonitor.shared.current ?? device
        weather = LivingCache.shared.loadWeather()
        buildAwayDiary(now: now)
        commit { $0.living.lastActiveAt = now }
        Task { await refreshWeather() }
        Task { await NudgeScheduler.reschedule(enabled: save.living.nudgesEnabled, creature: active) }
        Task { await refreshAILine(now: now) }
    }

    func livingWillResignActive(now: Date = .now) {
        commit { $0.living.lastActiveAt = now }
    }

    func refreshWeather(force: Bool = false) async {
        weather = await LivingWeatherService.shared.refreshIfNeeded(settings: save.living, force: force)
    }

    private func buildAwayDiary(now: Date) {
        guard let since = save.living.lastActiveAt, let a = active,
              now.timeIntervalSince(since) >= LivingEngine.diaryMinAway else { return }
        let b = HousePair.partner(in: save, now: now)
        let d = LivingEngine.diary(from: since, to: now, a: a, b: b, context: activityContext(now: now))
        guard !d.entries.isEmpty else { return }
        let lines = d.entries.map { LineService.diaryLine($0, a: a, b: b) }
        awayDiary = AwayDiary(lines: lines, moreCount: d.moreCount, since: since)
    }

    private func refreshAILine(now: Date) async {
        guard LineService.aiAvailable, let c = active else { aiLine = nil; return }
        let a = activity(at: now)
        let fallback = LineService.homeLine(for: c, activity: a, now: now)
        let line = await LineService.generate(fallback.category, name: c.name,
                                              temperName: PhenotypeMapper.temperName(PhenotypeMapper.traits(for: c)),
                                              weather: a.weather, fallback: fallback)
        aiLine = line.byAI ? line : nil
    }

    // MARK: Care items (§1)

    @discardableResult
    func giveItem(_ item: CareItem, now: Date = .now) -> LivingEngine.ItemOutcome {
        guard let id = active?.id else { return .noCreature }
        let weatherNow = activity(at: now).weather
        var outcome: LivingEngine.ItemOutcome = .noCreature
        commit { outcome = LivingEngine.giveItem(item, to: id, weather: weatherNow, save: &$0, now: now) }
        return outcome
    }

    // MARK: Jump rope (§8)

    @discardableResult
    func finishJumpRope(score: Int, bestCombo: Int, now: Date = .now) -> LivingEngine.RopeResult {
        var result = LivingEngine.RopeResult(sparks: 0, newBest: false, best: save.living.jumpRopeBest, gotRope: false)
        guard let id = active?.id else { return result }
        commit { result = LivingEngine.finishJumpRope(&$0, creatureId: id, score: score, bestCombo: bestCombo, now: now) }
        return result
    }

    func ideaAvailable(now: Date = .now) -> Bool { LivingEngine.ideaAvailable(save, now: now) }

    func consumeIdea(now: Date = .now) {
        commit { LivingEngine.consumeIdea(&$0, now: now) }
    }

    // MARK: House (§9)

    func setHousePartner(_ c: Creature?) {
        commit { $0.living.housePartnerId = c?.id }
    }

    // MARK: Settings

    func setWeatherEnabled(_ on: Bool) {
        commit { $0.living.weatherEnabled = on }
        if !on { weather = nil; LivingCache.shared.saveWeather(nil); WidgetCenter.shared.reloadAllTimelines() }
        Task { await refreshWeather(force: on) }
    }

    func setUseLocation(_ on: Bool) async {
        if on {
            let granted = await LivingWeatherService.shared.requestLocationPermission()
            commit { $0.living.useLocation = granted }
        } else {
            commit { $0.living.useLocation = false }
        }
        await refreshWeather(force: true)
    }

    func setManualCity(_ city: ManualCity?) async {
        commit { $0.living.manualCity = city }
        await refreshWeather(force: true)
    }

    func setNudgesEnabled(_ on: Bool) async {
        var enabled = on
        if on { enabled = await NudgeScheduler.requestPermission() }
        commit { $0.living.nudgesEnabled = enabled }
        await NudgeScheduler.reschedule(enabled: enabled, creature: active)
    }
}
