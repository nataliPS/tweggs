import Foundation
import MixlingsGenome

/// Pure living-world rules on top of `SaveData`: weather care items (§1), gene-based likes
/// (§13), "While you were away" diary (§9), jump-rope rewards and idea bubbles (§8).
/// Nothing here ever lowers a stat or takes sparks: the living world never punishes.
enum LivingEngine {
    // MARK: Weather care items (§1)

    static let itemJoy: Double = 15
    static let itemMood: Double = 5
    /// Extra joy when the weather is one the creature dislikes (it's extra grateful).
    static let itemDislikeBonusJoy: Double = 5
    static let itemSparks = 5

    /// One weather "event" = one weather kind on one local day. Rain in the morning and again
    /// in the evening is the same event (one reward); rain then snow are two.
    static func weatherEventId(kind: WeatherKind, at date: Date, timeZone: TimeZone = .current) -> String {
        "\(CollectingEngine.dayKey(date, timeZone: timeZone))|\(kind.rawValue)"
    }

    enum ItemOutcome: Equatable, Sendable {
        /// Right item for this weather, first time this event: joy + capped sparks.
        case rewarded(sparks: Int)
        /// Right item, already rewarded for this event: the creature still enjoys it (no sparks).
        case alreadyRewarded
        /// Not the item for this weather: a happy "thanks" only, no penalty.
        case notNeeded
        case noCreature
    }

    /// Gives `item` to creature `creatureId` in the current weather. The item joins the
    /// collection (cosmetic, free), is drawn on the creature for the rest of the event, and
    /// the right item earns joy + sparks once per weather event (sparks under the daily cap).
    @discardableResult
    static func giveItem(_ item: CareItem, to creatureId: String, weather: WeatherKind,
                         save: inout SaveData, now: Date, timeZone: TimeZone = .current) -> ItemOutcome {
        guard var c = save.creature(id: creatureId), CareEngine.stage(c, at: now) != .egg else { return .noCreature }
        if !save.living.ownedItems.contains(item.rawValue) { save.living.ownedItems.append(item.rawValue) }
        guard item.suits.contains(weather) else {
            c = CareEngine.pet(c, at: now) // a friendly pat: same as petting, never a penalty
            save.replace(c)
            return .notNeeded
        }
        let event = weatherEventId(kind: weather, at: now, timeZone: timeZone)
        save.living.givenItems[event] = item.rawValue
        trimGivenItems(&save)
        c = CareEngine.decay(c, to: now)
        guard !save.living.rewardedWeatherEvents.contains(event) else {
            save.replace(c)
            return .alreadyRewarded
        }
        let likes = Likes.derive(genome: c.genome)
        let bonus = likes.dislikes == weather ? itemDislikeBonusJoy : 0
        c.joy = CareEngine.clamp(c.joy + itemJoy + bonus)
        c.mood = CareEngine.clamp(c.mood + itemMood)
        save.replace(c)
        save.living.rewardedWeatherEvents.append(event)
        let overflow = save.living.rewardedWeatherEvents.count - LivingState.rewardedEventLimit
        if overflow > 0 { save.living.rewardedWeatherEvents.removeFirst(overflow) }
        let sparks = EconomyEngine.grantCappedSparks(&save, amount: itemSparks, source: .weatherItem,
                                                     now: now, timeZone: timeZone)
        return .rewarded(sparks: sparks)
    }

    /// Item drawn on the creature right now (given during the current weather event).
    static func displayedItem(givenItems: [String: Int], weather: WeatherKind, at date: Date,
                              timeZone: TimeZone = .current) -> CareItem? {
        guard weather != .none else { return nil }
        let event = weatherEventId(kind: weather, at: date, timeZone: timeZone)
        return givenItems[event].flatMap(CareItem.init(rawValue:))
    }

    /// Items that are "right" for `weather`, for the care tray.
    static func suggestedItems(for weather: WeatherKind) -> [CareItem] {
        CareItem.giveable.filter { $0.suits.contains(weather) }
    }

    private static func trimGivenItems(_ save: inout SaveData) {
        let keys = save.living.givenItems.keys.sorted()
        if keys.count > LivingState.givenItemLimit {
            for k in keys.prefix(keys.count - LivingState.givenItemLimit) { save.living.givenItems[k] = nil }
        }
    }

    // MARK: Jump rope (§8)

    static let ropeJoy: Double = 20
    /// Sparks per game: 1 per 5 combo, at most 15 per game; all under the daily cap.
    static let ropeSparksPerCombo = 5
    static let ropeSparksPerGameMax = 15

    struct RopeResult: Equatable, Sendable {
        var sparks: Int
        var newBest: Bool
        var best: Int
        var gotRope: Bool
    }

    static func ropeSparks(bestCombo: Int) -> Int {
        min(ropeSparksPerGameMax, max(0, bestCombo) / ropeSparksPerCombo)
    }

    @discardableResult
    static func finishJumpRope(_ save: inout SaveData, creatureId: String, score: Int, bestCombo: Int,
                               now: Date, timeZone: TimeZone = .current) -> RopeResult {
        if var c = save.creature(id: creatureId) {
            c = CareEngine.decay(c, to: now)
            c.joy = CareEngine.clamp(c.joy + ropeJoy)
            save.replace(c)
        }
        let s = max(0, score)
        let newBest = s > save.living.jumpRopeBest
        if newBest { save.living.jumpRopeBest = s }
        save.living.jumpRopeGames += 1
        let gotRope = !save.living.owns(.jumpRope)
        if gotRope { save.living.ownedItems.append(CareItem.jumpRope.rawValue) }
        let sparks = EconomyEngine.grantCappedSparks(&save, amount: ropeSparks(bestCombo: bestCombo),
                                                     source: .jumpRope, now: now, timeZone: timeZone)
        return RopeResult(sparks: sparks, newBest: newBest, best: save.living.jumpRopeBest, gotRope: gotRope)
    }

    // MARK: "I have an idea!" (§8): random moments, max 2 per day, never a penalty

    static let ideasPerDay = 2

    /// The two local hours (10...19) today when an idea pops up; deterministic per player & day.
    static func ideaHours(playerId: String, day: String) -> [Int] {
        var rng = Mulberry32(seed: Hash.fnv1a32("idea|\(playerId)|\(day)"))
        let first = 10 + rng.int(5)        // 10...14
        let second = 15 + rng.int(5)       // 15...19
        return [first, second]
    }

    /// True when an idea bubble should be showing: an idea hour has passed today and fewer than
    /// that many ideas were used / dismissed today.
    static func ideaAvailable(_ save: SaveData, now: Date, timeZone: TimeZone = .current) -> Bool {
        let day = CollectingEngine.dayKey(now, timeZone: timeZone)
        let used = save.living.ideaDay == day ? save.living.ideasUsed : 0
        guard used < ideasPerDay else { return false }
        let hour = ActivityStateMachine.localHour(now, timeZone)
        let due = ideaHours(playerId: save.playerId, day: day).filter { $0 <= hour }.count
        return used < due
    }

    /// Marks one idea as used (played or dismissed).
    static func consumeIdea(_ save: inout SaveData, now: Date, timeZone: TimeZone = .current) {
        let day = CollectingEngine.dayKey(now, timeZone: timeZone)
        if save.living.ideaDay != day {
            save.living.ideaDay = day
            save.living.ideasUsed = 0
        }
        save.living.ideasUsed = min(ideasPerDay, save.living.ideasUsed + 1)
    }

    // MARK: "While you were away" diary (§9)

    static let diaryMaxEntries = 6
    /// Shorter absences don't produce a diary.
    static let diaryMinAway: TimeInterval = 45 * 60
    /// Absences longer than this only look at the most recent part.
    static let diaryMaxSpan: TimeInterval = 3 * CareEngine.day

    struct DiaryEntry: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case scene(LifeScene)
            case weather(WeatherKind)
            case slept
        }
        var date: Date
        var kind: Kind
        /// Chess: who won (creature id). Deterministic from the pair's seed.
        var winnerId: String?
    }

    struct Diary: Equatable, Sendable {
        var entries: [DiaryEntry]
        /// Entries not shown ("…and more").
        var moreCount: Int
    }

    /// Diary for the time between `from` and `to`, sampled hourly with the same state machine
    /// the widget used, so it tells what the player could have seen on the Lock Screen.
    /// Consecutive identical activities collapse into one entry.
    static func diary(from: Date, to: Date, a: Creature, b: Creature?, context: ActivityContext) -> Diary {
        guard to.timeIntervalSince(from) >= diaryMinAway else { return Diary(entries: [], moreCount: 0) }
        let start = max(from, to.addingTimeInterval(-diaryMaxSpan))
        var ctx = context
        if let b { ctx.pairId = HousePair.pairId(a, b) } else { ctx.pairId = nil }
        var all: [DiaryEntry] = []
        var last: DiaryEntry.Kind?
        var t = start
        while t < to {
            let act = ActivityStateMachine.activity(at: t, context: ctx)
            let kind: DiaryEntry.Kind?
            switch act.kind {
            case .sleeping: kind = act.scene.map { DiaryEntry.Kind.scene($0) } ?? DiaryEntry.Kind.slept
            case .weather: kind = .weather(act.weather)
            case .pairScene, .routine, .focus, .calm: kind = act.scene.map { DiaryEntry.Kind.scene($0) }
            case .idle: kind = nil
            }
            if let kind, kind != last {
                var entry = DiaryEntry(date: t, kind: kind, winnerId: nil)
                if case .scene(.chess) = kind, let b {
                    entry.winnerId = chessWinner(pairId: HousePair.pairId(a, b), at: t, a: a, b: b,
                                                 timeZone: ctx.timeZone)
                }
                all.append(entry)
            }
            if kind != nil { last = kind }
            t = t.addingTimeInterval(3600)
        }
        let shown = Array(all.suffix(diaryMaxEntries))
        return Diary(entries: shown, moreCount: all.count - shown.count)
    }

    static func chessWinner(pairId: String, at date: Date, a: Creature, b: Creature, timeZone: TimeZone) -> String {
        let day = CollectingEngine.dayKey(date, timeZone: timeZone)
        let h = ActivityStateMachine.localHour(date, timeZone)
        let ids = [a.id, b.id].sorted()
        return ids[Int(Hash.fnv1a32("chess|\(pairId)|\(day)|\(h)") % 2)]
    }
}

// MARK: - Likes & dislikes from genes (§13)

/// Deterministic tastes from the genome (alleles, not the id): twins and trades keep them.
/// Shown on the card and used in reactions. Purely flavour: a disliked thing never hurts.
struct Likes: Equatable, Sendable {
    var likes: WeatherKind
    var dislikes: WeatherKind
    var favoriteScene: LifeScene

    static let weatherPool: [WeatherKind] = [.rain, .snow, .heat, .wind, .night]

    static func derive(genome: Genome) -> Likes {
        let flat = genome.map { $0.map(String.init).joined(separator: ",") }.joined(separator: ";")
        var rng = Mulberry32(seed: Hash.fnv1a32("likes|" + flat))
        let likeIdx = rng.int(weatherPool.count)
        // Dislike is a different weather (pool minus the liked one).
        let rest = weatherPool.enumerated().filter { $0.offset != likeIdx }.map(\.element)
        let dislike = rest[rng.int(rest.count)]
        let scene = LifeScene.dayPairScenes[rng.int(LifeScene.dayPairScenes.count)]
        return Likes(likes: weatherPool[likeIdx], dislikes: dislike, favoriteScene: scene)
    }

    static func derive(for c: Creature) -> Likes { derive(genome: c.genome) }

    enum Feeling: Equatable, Sendable { case loves, dislikes, neutral }

    func feeling(about weather: WeatherKind) -> Feeling {
        if weather == likes { return .loves }
        if weather == dislikes { return .dislikes }
        return .neutral
    }
}
