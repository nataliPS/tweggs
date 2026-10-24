import Foundation
import MixlingsGenome

/// Builds creatures from MixlingsGenome. Pure; shared so tests can use it.
enum CreatureFactory {
    /// Stable starter id, derived from the same seed string as the genome (genome-spec §6),
    /// so re-running onboarding for one player always yields the same creature.
    static func starterId(playerId: String, slot: Int) -> String {
        "s_" + Hash.hex8(Hash.fnv1a32("starter|" + playerId + "|" + String(slot)))
    }

    /// Onboarding egg (slot 0), gift adult (slot 1), day-2 gift baby (slot 2, retro G4).
    enum Slot {
        static let firstEgg = 0
        static let giftAdult = 1
        static let dayTwoBaby = 2
    }

    /// Deterministic starter creature, derived from `Genetics.starter`.
    /// Prefer `starter(save:...)`, which persists the genome in the save (T2).
    /// - `alreadyAdult`: backdates birth so the creature is an adult at `now` (free starter adult).
    static func starter(
        playerId: String, slot: Int, name: String, origin: CreatureOrigin,
        bornAt: Date, alreadyAdult: Bool, now: Date
    ) -> Creature? {
        guard let genome = try? Genetics.starter(playerId: playerId, slot: slot) else { return nil }
        return starter(genome: genome, playerId: playerId, slot: slot, name: name, origin: origin,
                       bornAt: bornAt, alreadyAdult: alreadyAdult, now: now)
    }

    /// T2: starter built from the genome persisted in `save` (stored on first use, never re-derived).
    static func starter(
        save: inout SaveData, slot: Int, name: String, origin: CreatureOrigin,
        bornAt: Date, alreadyAdult: Bool, now: Date
    ) -> Creature? {
        guard let genome = save.starterGenome(slot: slot) else { return nil }
        return starter(genome: genome, playerId: save.playerId, slot: slot, name: name, origin: origin,
                       bornAt: bornAt, alreadyAdult: alreadyAdult, now: now)
    }

    static func starter(
        genome: Genome, playerId: String, slot: Int, name: String, origin: CreatureOrigin,
        bornAt: Date, alreadyAdult: Bool, now: Date
    ) -> Creature? {
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
