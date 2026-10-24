import Foundation

/// Pure care & growth rules. No I/O, no clocks: every function takes `now` explicitly,
/// so the app, the widget timeline and the tests all agree.
///
/// Design rules:
/// - Mixlings NEVER die. Stats decay gently and are floored at `floor` (a "sleepy / sad" state).
/// - Eggs don't decay and can't be fed or played with (petting an egg is allowed and just keeps it warm).
/// - Growth (from the design doc): egg -> baby on day 1, teen on day 3, adult on day 7.
///   The schedule is anchored on the hatch moment: natural hatch = bornAt + 1 day; if the egg is
///   hatched early (onboarding tap), the rest of the schedule moves with it.
enum CareEngine {
    // MARK: Tunables

    static let maxValue: Double = 100
    /// Lowest any stat can go. The creature looks sleepy/sad here, but is never gone.
    static let floor: Double = 10
    static let startValue: Double = 80

    /// Points lost per hour.
    static let hungerDecayPerHour: Double = 3.0
    static let joyDecayPerHour: Double = 2.5
    static let moodDecayPerHour: Double = 1.5

    static let feedHunger: Double = 35
    static let feedMood: Double = 5
    static let playJoy: Double = 30
    static let playHungerCost: Double = 5
    static let playMood: Double = 5
    static let petMood: Double = 20
    static let petJoy: Double = 5

    static let day: TimeInterval = 24 * 60 * 60
    /// Offsets from bornAt for a naturally hatched egg: baby day 1, teen day 3, adult day 7.
    static let hatchAfter: TimeInterval = 1 * day
    static let teenAfterHatch: TimeInterval = 2 * day   // day 3 of life
    static let adultAfterHatch: TimeInterval = 6 * day  // day 7 of life

    // MARK: Growth

    /// Moment the creature hatches (or hatched).
    static func hatchDate(_ c: Creature) -> Date {
        c.hatchedAt ?? c.bornAt.addingTimeInterval(hatchAfter)
    }

    static func stage(_ c: Creature, at now: Date) -> Stage {
        let hatch = hatchDate(c)
        if now < hatch { return .egg }
        let age = now.timeIntervalSince(hatch)
        if age >= adultAfterHatch { return .adult }
        if age >= teenAfterHatch { return .teen }
        return .baby
    }

    /// When the creature reaches `stage` (nil for egg, which is from birth).
    static func date(of stage: Stage, for c: Creature) -> Date {
        switch stage {
        case .egg: return c.bornAt
        case .baby: return hatchDate(c)
        case .teen: return hatchDate(c).addingTimeInterval(teenAfterHatch)
        case .adult: return hatchDate(c).addingTimeInterval(adultAfterHatch)
        }
    }

    /// Next stage-up moment after `now`, or nil if already adult.
    static func nextGrowth(_ c: Creature, at now: Date) -> (stage: Stage, date: Date)? {
        guard let next = stage(c, at: now).next else { return nil }
        return (next, date(of: next, for: c))
    }

    /// Hatch an egg right now (onboarding). No-op if already hatched.
    static func hatch(_ c: Creature, at now: Date) -> Creature {
        guard stage(c, at: now) == .egg else { return c }
        var out = decay(c, to: now)
        out.hatchedAt = now
        out.lastUpdated = now
        return out
    }

    // MARK: Decay

    /// Projects stats from `lastUpdated` to `now`. Time before hatching doesn't count.
    /// Going backwards in time (clock changes) is ignored.
    static func decay(_ c: Creature, to now: Date) -> Creature {
        var out = c
        let start = max(c.lastUpdated, hatchDate(c))
        let hours = max(0, now.timeIntervalSince(start)) / 3600
        if hours > 0 {
            out.hunger = drop(c.hunger, by: hungerDecayPerHour * hours)
            out.joy = drop(c.joy, by: joyDecayPerHour * hours)
            out.mood = drop(c.mood, by: moodDecayPerHour * hours)
        } else {
            out.hunger = clamp(c.hunger)
            out.joy = clamp(c.joy)
            out.mood = clamp(c.mood)
        }
        if now > c.lastUpdated { out.lastUpdated = now }
        return out
    }

    // MARK: Care actions (each first decays to `now`)

    static func feed(_ c: Creature, at now: Date) -> Creature {
        var out = decay(c, to: now)
        guard stage(out, at: now) != .egg else { return out }
        out.hunger = clamp(out.hunger + feedHunger)
        out.mood = clamp(out.mood + feedMood)
        return out
    }

    static func play(_ c: Creature, at now: Date) -> Creature {
        var out = decay(c, to: now)
        guard stage(out, at: now) != .egg else { return out }
        out.joy = clamp(out.joy + playJoy)
        out.hunger = clamp(out.hunger - playHungerCost)
        out.mood = clamp(out.mood + playMood)
        return out
    }

    static func pet(_ c: Creature, at now: Date) -> Creature {
        var out = decay(c, to: now)
        out.mood = clamp(out.mood + petMood)
        out.joy = clamp(out.joy + petJoy)
        return out
    }

    // MARK: Condition

    static func condition(_ c: Creature, at now: Date) -> Condition {
        let d = decay(c, to: now)
        let avg = (d.hunger + d.joy + d.mood) / 3
        if avg >= 60 { return .happy }
        if avg >= 30 { return .okay }
        return .sleepy
    }

    // MARK: Helpers

    static func clamp(_ v: Double) -> Double {
        guard v.isFinite else { return Self.floor }
        return min(maxValue, max(Self.floor, v))
    }

    private static func drop(_ v: Double, by amount: Double) -> Double {
        clamp(v - amount)
    }
}
