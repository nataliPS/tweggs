import Foundation

/// Wellbeing actions (docs/wellbeing-spec.md). Everything stays in the local save; no sparks,
/// items or spark-cap changes; no network; no analytics beyond the anonymous on-device counts.
extension GameModel {
    var wellbeing: WellbeingState { save.wellbeing }

    func recordWellbeingOpen(_ p: WellbeingPractice) {
        commit { WellbeingEngine.recordOpen(p, save: &$0) }
    }

    func recordWellbeingCompletion(_ p: WellbeingPractice) {
        commit { WellbeingEngine.recordCompletion(p, save: &$0) }
    }

    /// Breathing finished: the creature meditates for 30 min (Home + widget, via `active.json`).
    func finishBreathing(now: Date = .now) {
        commit { WellbeingEngine.finishBreathing(save: &$0, now: now) }
    }

    func recordCalmer(_ yes: Bool) {
        commit { WellbeingEngine.recordCalmer(yes, save: &$0) }
    }

    func setWindDownEnabled(_ on: Bool) {
        commit { $0.wellbeing.windDownEnabled = on }
    }

    func resetWellbeingStats() {
        commit { WellbeingEngine.resetStats(save: &$0) }
    }
}
