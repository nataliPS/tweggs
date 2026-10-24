import Foundation

/// "Breathe with me" timing (pure, tested). In 4 s, out 4 s or 6 s; 1 or 2 minutes.
enum BreathingRhythm: String, CaseIterable, Identifiable, Sendable {
    case fourFour = "4-4"
    case fourSix = "4-6"

    var id: String { rawValue }
    var inhale: TimeInterval { 4 }
    var exhale: TimeInterval { self == .fourFour ? 4 : 6 }
    var cycle: TimeInterval { inhale + exhale }
}

struct BreathingSession: Equatable, Sendable {
    static let allowedMinutes = [1, 2]

    var rhythm: BreathingRhythm
    var minutes: Int

    init(rhythm: BreathingRhythm = .fourSix, minutes: Int = 1) {
        self.rhythm = rhythm
        self.minutes = min(max(minutes, 1), 2)
    }

    var duration: TimeInterval { TimeInterval(minutes) * 60 }

    enum Phase: Equatable, Sendable { case breatheIn, breatheOut, done }

    struct State: Equatable, Sendable {
        var phase: Phase
        /// 0 = fully out (small), 1 = fully in (big). Eased.
        var fill: Double
        /// Increments every half-breath (drives the optional haptic).
        var step: Int
    }

    func state(elapsed: TimeInterval) -> State {
        guard elapsed < duration else { return State(phase: .done, fill: 0, step: -1) }
        let t = max(0, elapsed)
        let cycleIndex = Int(t / rhythm.cycle)
        let inCycle = t - Double(cycleIndex) * rhythm.cycle
        if inCycle < rhythm.inhale {
            return State(phase: .breatheIn, fill: Self.ease(inCycle / rhythm.inhale), step: cycleIndex * 2)
        }
        let out = (inCycle - rhythm.inhale) / rhythm.exhale
        return State(phase: .breatheOut, fill: 1 - Self.ease(out), step: cycleIndex * 2 + 1)
    }

    /// Smooth in/out (cosine), so the creature never "jumps".
    static func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return (1 - cos(c * .pi)) / 2
    }
}
