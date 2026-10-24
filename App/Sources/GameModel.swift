import Foundation
import Observation
import WidgetKit
import MixlingsGenome

/// App-side state holder. Owns the in-memory `SaveData`, writes through `CreatureStore`,
/// and pokes WidgetKit after every change.
@MainActor
@Observable
final class GameModel {
    private(set) var save: SaveData
    /// Deep-link offer waiting to be shown (from `https://mix.orizolabs.app/b/<offerId>`).
    var incomingOffer: IncomingOffer?

    private let store: CreatureStore

    init(store: CreatureStore = .shared) {
        self.store = store
        self.save = store.loadOrCreate()
    }

    var creatures: [Creature] { save.creatures }
    var active: Creature? { save.activeCreature }
    var needsOnboarding: Bool { !save.onboardingComplete || save.creatures.isEmpty }

    /// Re-read from disk (widget intents may have changed it while we were in background).
    func reload() {
        save = store.load()
    }

    func select(_ creature: Creature) {
        commit { $0.activeCreatureId = creature.id }
    }

    func care(_ action: CreatureStore.CareAction, now: Date = .now) {
        guard let id = active?.id else { return }
        save = store.apply(action, creatureId: id, at: now)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func rename(_ creature: Creature, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commit { save in
            guard var c = save.creature(id: creature.id) else { return }
            c.name = String(trimmed.prefix(16))
            save.replace(c)
        }
    }

    // MARK: Onboarding

    /// Creates the first egg (slot 0) if there isn't one yet. Persists the random playerId.
    func prepareFirstEgg(now: Date = .now) -> Creature? {
        if let egg = save.creatures.first { return egg }
        guard let egg = CreatureFactory.starter(playerId: save.playerId, slot: 0, name: "Mixy",
                                         origin: .hatched, bornAt: now, alreadyAdult: false, now: now)
        else { return nil }
        commit { save in
            save.replace(egg)
            save.activeCreatureId = egg.id
        }
        return egg
    }

    /// Step 2 of onboarding: hatch the first egg now, name it, and add the starter adult (slot 1).
    /// Onboarding stays open until `finishOnboarding()` so the gift screen can be shown.
    func completeOnboarding(babyName: String, now: Date = .now) {
        guard let egg = prepareFirstEgg(now: now) else { return }
        let adult = CreatureFactory.starter(playerId: save.playerId, slot: 1, name: "Pip",
                                     origin: .starter, bornAt: now, alreadyAdult: true, now: now)
        commit { save in
            var baby = CareEngine.hatch(egg, at: now)
            let trimmed = babyName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { baby.name = String(trimmed.prefix(16)) }
            save.replace(baby)
            if let adult, save.creature(id: adult.id) == nil { save.replace(adult) }
            save.activeCreatureId = baby.id
        }
    }

    /// The starter adult, once created (shown on the onboarding gift screen).
    var pendingStarter: Creature? {
        save.creatures.first(where: { $0.origin == .starter })
    }

    /// Step 3 of onboarding: enter the main game.
    func finishOnboarding() {
        commit { $0.onboardingComplete = true }
    }

    // MARK: Deep links

    struct IncomingOffer: Identifiable, Equatable {
        let id: String
    }

    /// Handles `https://mix.orizolabs.app/b/<offerId>` (universal link) and
    /// `mixlings://b/<offerId>` (custom scheme, handy for testing in Simulator).
    /// TODO(server): fetch the offer (friend's parent creature + server nonce) and run the real breed.
    func handle(url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        let isUniversal = url.host == "mix.orizolabs.app"
        let isScheme = url.scheme == "mixlings"
        if isUniversal, parts.count >= 2, parts[0] == "b" {
            incomingOffer = IncomingOffer(id: parts[1])
        } else if isScheme, url.host == "b", let first = parts.first {
            incomingOffer = IncomingOffer(id: first)
        }
        // `mixlings://home` (widget tap) and anything else: just open the app.
    }

    // MARK: Private

    private func commit(_ change: (inout SaveData) -> Void) {
        save = store.update(change)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
