import Foundation
import MixlingsGenome

/// Builds creatures from MixlingsGenome. Pure; shared so tests can use it.
enum CreatureFactory {
    /// Stable starter id, derived from the same seed string as the genome (genome-spec §6),
    /// so re-running onboarding for one player always yields the same creature.
    static func starterId(playerId: String, slot: Int) -> String {
        "s_" + Hash.hex8(Hash.fnv1a32("starter|" + playerId + "|" + String(slot)))
    }

    /// Deterministic starter creature.
    /// - `alreadyAdult`: backdates birth so the creature is an adult at `now` (free starter adult).
    static func starter(
        playerId: String, slot: Int, name: String, origin: CreatureOrigin,
        bornAt: Date, alreadyAdult: Bool, now: Date
    ) -> Creature? {
        guard let genome = try? Genetics.starter(playerId: playerId, slot: slot) else { return nil }
        let id = starterId(playerId: playerId, slot: slot)
        if alreadyAdult {
            let born = now.addingTimeInterval(-(CareEngine.hatchAfter + CareEngine.adultAfterHatch))
            return Creature(id: id, name: name, genome: genome, origin: origin,
                            bornAt: born, hatchedAt: born.addingTimeInterval(CareEngine.hatchAfter),
                            lastUpdated: now)
        }
        return Creature(id: id, name: name, genome: genome, origin: origin, bornAt: bornAt)
    }
}
