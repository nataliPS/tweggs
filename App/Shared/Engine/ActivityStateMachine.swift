import Foundation
import MixlingsGenome

/// Scenes the creature (or the pair) can be in. Drawn by MixlingsArt's room renderer via
/// `ArtAdapter.artScene`; scenes the art doesn't have yet map to the closest one.
enum LifeScene: String, Codable, CaseIterable, Hashable, Sendable {
    // Pair life (§9)
    case chess, painting, chatting, pillowFort, napping, cooking, stargazing
    // Daily routine (§13)
    case breakfast, backpack, homework, dinner

    /// Daytime pair scenes, in the fixed order used by the seeded schedule. Never reorder
    /// (it would change every player's schedule); append only.
    static let dayPairScenes: [LifeScene] = [.chess, .painting, .chatting, .pillowFort, .napping, .cooking]

    var isPair: Bool {
        switch self {
        case .chess, .painting, .chatting, .pillowFort, .napping, .cooking, .stargazing: return true
        case .breakfast, .backpack, .homework, .dinner: return false
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .chess: return "Playing chess"
        case .painting: return "Painting"
        case .chatting: return "Chatting"
        case .pillowFort: return "Building a pillow fort"
        case .napping: return "Napping together"
        case .cooking: return "Cooking"
        case .stargazing: return "Stargazing"
        case .breakfast: return "Breakfast"
        case .backpack: return "Packing the backpack"
        case .homework: return "Homework"
        case .dinner: return "Dinner"
        }
    }

    var systemImage: String {
        switch self {
        case .chess: return "checkerboard.rectangle"
        case .painting: return "paintpalette.fill"
        case .chatting: return "bubble.left.and.bubble.right.fill"
        case .pillowFort: return "tent.fill"
        case .napping: return "zzz"
        case .cooking: return "frying.pan.fill"
        case .stargazing: return "sparkles"
        case .breakfast: return "cup.and.saucer.fill"
        case .backpack: return "backpack.fill"
        case .homework: return "pencil.and.ruler.fill"
        case .dinner: return "fork.knife"
        }
    }
}

/// §13 widget-alive frames. Raw values match `Phenotype.alive`.
enum AliveFrame: Int, Codable, Hashable, Sendable {
    case none = 0
    case charging = 1
    case lowPower = 2
    case morning = 3
}

/// What decided the current activity (priority order, §0).
enum ActivityKind: String, Codable, Hashable, Sendable {
    case focus, sleeping, weather, pairScene, routine, idle
}

struct Activity: Equatable, Hashable, Sendable {
    var kind: ActivityKind
    var scene: LifeScene?
    /// Weather layer to draw (`.night` while sleeping, `.none` if unknown / clear).
    var weather: WeatherKind
    var isNight: Bool
    var alive: AliveFrame
    var holiday: Holiday?
}

struct ScheduledActivity: Equatable, Sendable {
    var date: Date
    var activity: Activity
}

/// Inputs that are not the clock. Everything is cached / local; nothing here leaves the device.
struct ActivityContext: Sendable {
    var timeZone: TimeZone
    var weather: WeatherSnapshot?
    var device: DeviceSnapshot?
    /// `HousePair.pairId` when two creatures share the house; nil = the creature is alone.
    var pairId: String?
    /// Focus mode until this moment (Beta, §6). Nil in MVP.
    var focusUntil: Date?

    init(timeZone: TimeZone = .current, weather: WeatherSnapshot? = nil, device: DeviceSnapshot? = nil,
         pairId: String? = nil, focusUntil: Date? = nil) {
        self.timeZone = timeZone
        self.weather = weather
        self.device = device
        self.pairId = pairId
        self.focusUntil = focusUntil
    }
}

/// The ONE activity state machine (§0). Pure: no clocks, no I/O; the app, the widget timeline,
/// the diary and the tests all call the same functions.
///
/// Priority: focus → night → weather → pair scene → daily routine (→ idle).
/// Alive frames (§13) are an overlay: low power nap > morning stretch > charging snack.
enum ActivityStateMachine {
    /// Fallback night when no sunrise/sunset is cached: 21:00–07:00 local.
    static let fallbackNightStartHour = 21
    static let fallbackNightEndHour = 7
    /// Morning stretch shows for this long after the night ends.
    static let morningWindow: TimeInterval = 45 * 60
    /// Stargazing replaces sleeping in the first hours after sunset (pair, clear sky, before 22:00).
    static let stargazingWindow: TimeInterval = 2 * 3600
    static let stargazingLatestHour = 22
    /// Chance (percent) that the pair does something together in a given hour.
    static let pairChance = 60
    /// Lower inside routine windows so breakfast / homework / dinner still show up.
    static let pairChanceDuringRoutine = 25

    // MARK: Now

    static func activity(at date: Date, context: ActivityContext) -> Activity {
        let holiday = HolidayCalendar.holiday(on: date, timeZone: context.timeZone)
        let night = isNight(at: date, context: context)
        let weatherNow: WeatherKind = context.weather?.kind(at: date) ?? WeatherKind.none

        // 1. Focus
        if let f = context.focusUntil, date < f {
            return Activity(kind: .focus, scene: .homework, weather: night ? .night : weatherNow,
                            isNight: night, alive: .none, holiday: holiday)
        }
        let alive = aliveFrame(at: date, context: context, night: night)
        // 2. Night
        if night {
            var scene: LifeScene? = nil
            if context.pairId != nil, weatherNow == .none || weatherNow == .wind,
               let start = nightStart(containing: date, context: context),
               date.timeIntervalSince(start) < stargazingWindow,
               localHour(date, context.timeZone) < stargazingLatestHour,
               localHour(date, context.timeZone) >= 12 {
                scene = .stargazing
            }
            return Activity(kind: .sleeping, scene: scene, weather: .night, isNight: true,
                            alive: alive == .lowPower ? .lowPower : .none, holiday: holiday)
        }
        // 3. Weather
        if weatherNow != .none {
            return Activity(kind: .weather, scene: nil, weather: weatherNow, isNight: false,
                            alive: alive, holiday: holiday)
        }
        let routine = routineScene(at: date, timeZone: context.timeZone)
        // 4. Pair scene
        if let pairId = context.pairId,
           let scene = pairScene(pairId: pairId, at: date, timeZone: context.timeZone, inRoutine: routine != nil) {
            return Activity(kind: .pairScene, scene: scene, weather: .none, isNight: false,
                            alive: alive, holiday: holiday)
        }
        // 5. Daily routine
        if let routine {
            return Activity(kind: .routine, scene: routine, weather: .none, isNight: false,
                            alive: alive, holiday: holiday)
        }
        return Activity(kind: .idle, scene: nil, weather: .none, isNight: false, alive: alive, holiday: holiday)
    }

    // MARK: Widget timeline

    /// Entries every `step` for `horizon` (inclusive of `start`). The first non-night entry that
    /// follows a night entry gets the morning stretch (first unlock of the day, §13).
    static func schedule(from start: Date, context: ActivityContext,
                         step: TimeInterval = 30 * 60, horizon: TimeInterval = 12 * 3600) -> [ScheduledActivity] {
        let s = max(60, step)
        let count = Int(horizon / s)
        var out: [ScheduledActivity] = []
        var previousNight = false
        for i in 0...count {
            let date = start.addingTimeInterval(Double(i) * s)
            var a = activity(at: date, context: context)
            if previousNight, !a.isNight, a.kind != .focus, a.alive != .lowPower {
                a.alive = .morning
            }
            previousNight = a.isNight
            out.append(ScheduledActivity(date: date, activity: a))
        }
        return out
    }

    // MARK: Night

    static func isNight(at date: Date, context: ActivityContext) -> Bool {
        if let s = sun(for: date, context: context) {
            return date < s.rise || date >= s.set
        }
        let h = localHour(date, context.timeZone)
        return h >= fallbackNightStartHour || h < fallbackNightEndHour
    }

    /// Sunrise/sunset for the local day of `date`, if both are cached (polar days fall back).
    static func sun(for date: Date, context: ActivityContext) -> (rise: Date, set: Date)? {
        guard let w = context.weather else { return nil }
        let tz = TimeZone(identifier: w.timeZoneId) ?? context.timeZone
        let day = CollectingEngine.dayKey(date, timeZone: tz)
        guard let s = w.sun(forDay: day), let rise = s.sunrise, let set = s.sunset, rise < set else { return nil }
        return (rise: rise, set: set)
    }

    /// When the night that contains `date` ends (sunrise, or 07:00 fallback).
    static func nightEnd(after date: Date, context: ActivityContext) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = context.timeZone
        let today = date
        let tomorrow = cal.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(CareEngine.day)
        for d in [today, tomorrow] {
            let end: Date?
            if let s = sun(for: d, context: context) {
                end = s.rise
            } else {
                end = cal.date(bySettingHour: fallbackNightEndHour, minute: 0, second: 0, of: d)
            }
            if let end, end > date { return end }
        }
        return nil
    }

    /// When the evening part of the night containing `date` started (sunset, or 21:00 fallback).
    static func nightStart(containing date: Date, context: ActivityContext) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = context.timeZone
        let yesterday = cal.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-CareEngine.day)
        for d in [date, yesterday] {
            let start: Date?
            if let s = sun(for: d, context: context) {
                start = s.set
            } else {
                start = cal.date(bySettingHour: fallbackNightStartHour, minute: 0, second: 0, of: d)
            }
            if let start, start <= date { return start }
        }
        return nil
    }

    // MARK: Alive overlay

    static func aliveFrame(at date: Date, context: ActivityContext, night: Bool) -> AliveFrame {
        if let d = context.device, d.isValid(at: date), d.lowPower { return .lowPower }
        if !night, let start = morningStart(before: date, context: context),
           date.timeIntervalSince(start) < morningWindow {
            return .morning
        }
        if let d = context.device, d.isValid(at: date), d.charging { return .charging }
        return .none
    }

    /// Most recent night end at or before `date` (same local day).
    private static func morningStart(before date: Date, context: ActivityContext) -> Date? {
        if let s = sun(for: date, context: context) { return s.rise <= date ? s.rise : nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = context.timeZone
        guard let end = cal.date(bySettingHour: fallbackNightEndHour, minute: 0, second: 0, of: date) else { return nil }
        return end <= date ? end : nil
    }

    // MARK: Pair scenes (§9)

    /// `fnv1a32("\(pairId)|\(localDay)")` — the seed of one pair's day.
    static func pairSeed(pairId: String, day: String) -> UInt32 {
        Hash.fnv1a32("\(pairId)|\(day)")
    }

    /// One (roll, pick) per local hour, drawn in hour order from the day's seed.
    static func pairDayTable(pairId: String, day: String) -> [(roll: Int, pick: Int)] {
        var rng = Mulberry32(seed: pairSeed(pairId: pairId, day: day))
        var out: [(roll: Int, pick: Int)] = []
        out.reserveCapacity(24)
        for _ in 0..<24 {
            let roll = rng.int(100)
            let pick = rng.int(LifeScene.dayPairScenes.count)
            out.append((roll: roll, pick: pick))
        }
        return out
    }

    /// The pair's daytime scene at `date`, or nil if they're doing their own thing this hour.
    static func pairScene(pairId: String, at date: Date, timeZone: TimeZone, inRoutine: Bool = false) -> LifeScene? {
        let day = CollectingEngine.dayKey(date, timeZone: timeZone)
        let table = pairDayTable(pairId: pairId, day: day)
        let h = localHour(date, timeZone)
        guard table.indices.contains(h) else { return nil }
        let slot = table[h]
        let chance = inRoutine ? pairChanceDuringRoutine : pairChance
        guard slot.roll < chance else { return nil }
        return LifeScene.dayPairScenes[slot.pick]
    }

    // MARK: Daily routine (§13)

    /// Breakfast 07–08 (weekends 07–09), backpack 08–09 on weekdays, homework 15–17 on weekdays,
    /// dinner 18–20. Local time.
    static func routineScene(at date: Date, timeZone: TimeZone) -> LifeScene? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let h = cal.component(.hour, from: date)
        let weekday = cal.component(.weekday, from: date) // 1 Sun ... 7 Sat
        let weekend = weekday == 1 || weekday == 7
        switch h {
        case 7: return .breakfast
        case 8: return weekend ? .breakfast : .backpack
        case 15, 16: return weekend ? nil : .homework
        case 18, 19: return .dinner
        default: return nil
        }
    }

    // MARK: Helpers

    static func localHour(_ date: Date, _ tz: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.component(.hour, from: date)
    }
}

/// The two creatures sharing the house (§9): both the player's own in MVP.
enum HousePair {
    /// Order-independent pair id ("a+b", ids sorted), so swapping who is "active" keeps the schedule.
    static func pairId(_ a: Creature, _ b: Creature) -> String {
        [a.id, b.id].sorted().joined(separator: "+")
    }

    /// The active creature's housemate: the chosen partner if still valid, else the first other
    /// hatched creature in an active slot. Nil if there is none.
    static func partner(in save: SaveData, now: Date) -> Creature? {
        guard let active = save.activeCreature else { return nil }
        let ok: (Creature) -> Bool = { $0.id != active.id && CareEngine.stage($0, at: now) != .egg }
        if let id = save.living.housePartnerId, let c = save.creature(id: id), ok(c) { return c }
        return save.activeSlotCreatures.first(where: ok) ?? save.creatures.first(where: ok)
    }
}
