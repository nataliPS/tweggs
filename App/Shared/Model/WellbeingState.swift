import Foundation

/// Wellbeing ("Хвилинка спокою", docs/wellbeing-spec.md) part of `SaveData`.
/// Additive field with a decode default (no version bump).
///
/// Privacy: stays on this device. Never sent to friends, Duo/Crew, the server or analytics.
/// The only metrics are anonymous on-device counts (opens / completions / "feel calmer?").
/// No sparks, items or any other reward is ever tied to these practices.
struct WellbeingState: Codable, Equatable, Sendable {
    /// Opt-in evening wind-down scene in the evening routine. Off by default.
    var windDownEnabled: Bool
    /// The creature shows a calm (meditating) pose until this moment after a breathing session.
    var calmUntil: Date?
    /// Anonymous counts by `WellbeingPractice.rawValue`.
    var opens: [String: Int]
    var completions: [String: Int]
    /// Optional one-tap "feel a bit calmer?" answers (aggregate only, no timestamps).
    var calmerYes: Int
    var calmerNo: Int

    init(windDownEnabled: Bool = false, calmUntil: Date? = nil, opens: [String: Int] = [:],
         completions: [String: Int] = [:], calmerYes: Int = 0, calmerNo: Int = 0) {
        self.windDownEnabled = windDownEnabled
        self.calmUntil = calmUntil
        self.opens = opens
        self.completions = completions
        self.calmerYes = calmerYes
        self.calmerNo = calmerNo
    }

    private enum CodingKeys: String, CodingKey {
        case windDownEnabled, calmUntil, opens, completions, calmerYes, calmerNo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windDownEnabled = try c.decodeIfPresent(Bool.self, forKey: .windDownEnabled) ?? false
        calmUntil = try c.decodeIfPresent(Date.self, forKey: .calmUntil)
        opens = (try? c.decodeIfPresent([String: Int].self, forKey: .opens)) ?? [:]
        completions = (try? c.decodeIfPresent([String: Int].self, forKey: .completions)) ?? [:]
        calmerYes = try c.decodeIfPresent(Int.self, forKey: .calmerYes) ?? 0
        calmerNo = try c.decodeIfPresent(Int.self, forKey: .calmerNo) ?? 0
    }
}

enum WellbeingPractice: String, CaseIterable, Codable, Sendable {
    case calmScreen, breathe, grounding, hardTime, helplines, windDown
}

/// Pure wellbeing rules. Nothing here touches sparks, items, the spark cap or the network.
enum WellbeingEngine {
    /// Spec: never tie rewards to wellbeing use (so nobody "farms" calm). Kept as a constant so
    /// the rule is visible and tested.
    static let sparksPerPractice = 0

    static func recordOpen(_ p: WellbeingPractice, save: inout SaveData) {
        save.wellbeing.opens[p.rawValue, default: 0] += 1
    }

    static func recordCompletion(_ p: WellbeingPractice, save: inout SaveData) {
        save.wellbeing.completions[p.rawValue, default: 0] += 1
    }

    /// After "Breathe with me": count it and show the calm pose for 30 min (widget + Home).
    static func finishBreathing(save: inout SaveData, now: Date) {
        recordCompletion(.breathe, save: &save)
        save.wellbeing.calmUntil = now.addingTimeInterval(ActivityStateMachine.calmDuration)
    }

    static func recordCalmer(_ yes: Bool, save: inout SaveData) {
        if yes { save.wellbeing.calmerYes += 1 } else { save.wellbeing.calmerNo += 1 }
    }

    /// Wipes the on-device counts (the user can delete everything).
    static func resetStats(save: inout SaveData) {
        let windDown = save.wellbeing.windDownEnabled
        save.wellbeing = WellbeingState(windDownEnabled: windDown)
    }
}
