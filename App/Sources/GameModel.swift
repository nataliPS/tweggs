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
        grantDayTwoGiftIfDue()
    }

    var creatures: [Creature] { save.creatures }
    var active: Creature? { save.activeCreature }
    var needsOnboarding: Bool { !save.onboardingComplete || save.creatures.isEmpty }
    /// C2: breeding links, trading and sharing (13+ only; unknown age = off).
    var socialAllowed: Bool { save.socialAllowed }
    /// C2: players from before the age screen existed are asked once.
    var needsAgeCheck: Bool { save.ageBand == nil }
    /// G4: the day-2 gift baby that was just added (shown once as a sheet).
    var newGift: Creature? = nil

    /// Re-read from disk (widget intents may have changed it while we were in background).
    func reload() {
        // Re-read from disk, but never replace state with a fresh, unsaved SaveData
        // (an unreadable file must not mint a new playerId).
        save = store.loadOrCreate()
        grantDayTwoGiftIfDue()
    }

    func select(_ creature: Creature) {
        commit { $0.activeCreatureId = creature.id }
    }

    func care(_ action: CreatureStore.CareAction, now: Date = .now) {
        guard let id = active?.id else { return }
        save = store.apply(action, creatureId: id, at: now)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Renames through the C3 name filter. Returns the verdict so the UI can explain a refusal.
    @discardableResult
    func rename(_ creature: Creature, to name: String) -> NameFilter.Verdict {
        let verdict = NameFilter.check(name)
        guard case .ok(let clean) = verdict else { return verdict }
        commit { save in
            guard var c = save.creature(id: creature.id) else { return }
            c.name = clean
            save.replace(c)
        }
        return verdict
    }

    // MARK: Age (C2)

    func setAgeBand(_ band: AgeBand) {
        commit { $0.ageBand = band }
    }

    // MARK: Onboarding

    /// Creates the first egg (slot 0) if there isn't one yet. Persists the random playerId and
    /// the starter genome (T2).
    func prepareFirstEgg(now: Date = .now) -> Creature? {
        if let egg = save.creatures.first { return egg }
        var egg: Creature?
        commit { save in
            guard let e = CreatureFactory.starter(save: &save, slot: CreatureFactory.Slot.firstEgg, name: "Mixy",
                                                  origin: .hatched, bornAt: now, alreadyAdult: false, now: now)
            else { return }
            save.replace(e)
            save.activeCreatureId = e.id
            egg = e
        }
        return egg
    }

    /// Step 2 of onboarding: hatch the first egg now, name it, and add the starter adult (slot 1).
    /// Onboarding stays open until `finishOnboarding()` so the gift screen can be shown.
    /// The name must already have passed `NameFilter` (the view checks); a rejected or empty
    /// name keeps the default.
    func completeOnboarding(babyName: String, now: Date = .now) {
        guard let egg = prepareFirstEgg(now: now) else { return }
        commit { save in
            var baby = CareEngine.hatch(egg, at: now)
            if let clean = NameFilter.clean(babyName) { baby.name = clean }
            save.replace(baby)
            if let adult = CreatureFactory.starter(save: &save, slot: CreatureFactory.Slot.giftAdult, name: "Pip",
                                                   origin: .starter, bornAt: now, alreadyAdult: true, now: now),
               save.creature(id: adult.id) == nil {
                save.replace(adult)
            }
            save.activeCreatureId = baby.id
        }
    }

    /// The first (onboarding) creature.
    var firstHatched: Creature? {
        save.creature(id: CreatureFactory.starterId(playerId: save.playerId, slot: CreatureFactory.Slot.firstEgg))
            ?? save.creatures.first(where: { $0.origin == .hatched })
    }

    /// G4: on day 2 (one day after the first hatch) a second starter baby arrives, so the player
    /// soon has two teens of their own. Idempotent: the slot-2 id is deterministic.
    /// Returns the new baby once; nil if not due yet or already given.
    @discardableResult
    func grantDayTwoGiftIfDue(now: Date = .now) -> Creature? {
        guard save.onboardingComplete, let first = firstHatched,
              now >= CareEngine.hatchDate(first).addingTimeInterval(CareEngine.day) else { return nil }
        let id = CreatureFactory.starterId(playerId: save.playerId, slot: CreatureFactory.Slot.dayTwoBaby)
        guard save.creature(id: id) == nil else { return nil }
        var gift: Creature?
        commit { save in
            guard let egg = CreatureFactory.starter(save: &save, slot: CreatureFactory.Slot.dayTwoBaby, name: "Bo",
                                                    origin: .starter, bornAt: now, alreadyAdult: false, now: now)
            else { return }
            let baby = CareEngine.hatch(egg, at: now)
            EconomyEngine.admit(baby, to: &save)
            gift = save.creature(id: baby.id)
        }
        newGift = gift
        return gift
    }

    /// The starter adult, once created (shown on the onboarding gift screen).
    var pendingStarter: Creature? {
        save.creature(id: CreatureFactory.starterId(playerId: save.playerId, slot: CreatureFactory.Slot.giftAdult))
            ?? save.creatures.first(where: { $0.origin == .starter })
    }

    /// Step 3 of onboarding: enter the main game.
    func finishOnboarding() {
        commit { $0.onboardingComplete = true }
    }

    /// U1/H3: the first-share prompt is shown once, right after the onboarding hatch.
    func markFirstSharePromptShown() {
        commit { $0.firstSharePromptShown = true }
    }

    // MARK: Slots & sanctuary (G5)

    var slotLimit: Int { EconomyEngine.slotLimit(save) }

    @discardableResult
    func moveToSanctuary(_ creature: Creature) -> Result<Void, EconomyEngine.SlotError> {
        var result: Result<Void, EconomyEngine.SlotError> = .failure(.notFound)
        commit { result = EconomyEngine.moveToSanctuary(&$0, creatureId: creature.id) }
        return result
    }

    @discardableResult
    func moveToActive(_ creature: Creature) -> Result<Void, EconomyEngine.SlotError> {
        var result: Result<Void, EconomyEngine.SlotError> = .failure(.notFound)
        commit { result = EconomyEngine.moveToActive(&$0, creatureId: creature.id) }
        return result
    }

    // MARK: Spark sinks (G6) — sparks are earned only, never sold

    @discardableResult
    func hatchRush(_ creature: Creature, now: Date = .now) -> Result<Void, EconomyEngine.SinkError> {
        var result: Result<Void, EconomyEngine.SinkError> = .failure(.notFound)
        commit { result = EconomyEngine.hatchRush(&$0, creatureId: creature.id, now: now) }
        return result
    }

    @discardableResult
    func buyGeneHint(season: Collecting.Season, entry: Collecting.SeasonEntry) -> Result<Void, EconomyEngine.SinkError> {
        var result: Result<Void, EconomyEngine.SinkError> = .failure(.notFound)
        commit { result = EconomyEngine.buyGeneHint(&$0, season: season, entry: entry) }
        return result
    }

    func hasGeneHint(season: Collecting.Season, entry: Collecting.SeasonEntry) -> Bool {
        save.geneHintKeys.contains(EconomyEngine.geneHintKey(season: season, entry: entry))
    }

    @discardableResult
    func buy(_ item: EconomyEngine.ShopItem) -> Result<Void, EconomyEngine.SinkError> {
        var result: Result<Void, EconomyEngine.SinkError> = .failure(.notFound)
        commit { result = EconomyEngine.buy(item, save: &$0) }
        return result
    }

    // MARK: Club (C7)

    /// TODO(storekit): set from `Transaction.currentEntitlements`, never from UI. DEBUG toggle only.
    func setClubMember(_ on: Bool) {
        commit { $0.isClubMember = on }
    }

    // MARK: Safety (C3)

    /// Stub: hides offers from this sender locally. TODO(server): block on the server too.
    func block(offer: IncomingOffer) {
        commit { save in
            if !save.blockedSenders.contains(offer.id) { save.blockedSenders.append(offer.id) }
        }
        incomingOffer = nil
    }

    /// Stub: records the report locally. TODO(server): POST /reports with offer id + reason.
    func report(offer: IncomingOffer) {
        commit { save in
            if !save.reportedOffers.contains(offer.id) { save.reportedOffers.append(offer.id) }
        }
    }

    // MARK: Collecting

    /// Free daily surprise: available once per local day. No purchase or re-roll path exists.
    func canOpenSurprise(now: Date = .now) -> Bool {
        CollectingEngine.canOpenSurprise(save, now: now)
    }

    /// Opens today's surprise; nil if it was already opened today.
    @discardableResult
    func openDailySurprise(now: Date = .now) -> Collecting.Souvenir? {
        var result: Collecting.Souvenir?
        commit { save in
            result = CollectingEngine.openSurprise(&save, now: now)
        }
        return result
    }

    /// Creates a local trade offer for one of the player's creatures.
    /// TODO(server): POST the offer; the server escrows the creature and returns the real id/link.
    /// Free swap only: no tokens, no fees, no money.
    func createTradeOffer(for creature: Creature, now: Date = .now) -> TradeOffer {
        if let existing = save.tradeOffers.first(where: { $0.creatureId == creature.id && $0.status == .draft }) {
            return existing
        }
        let offer = TradeOffer(creatureId: creature.id, createdAt: now)
        commit { $0.tradeOffers.append(offer) }
        return offer
    }

    func cancelTradeOffer(_ offer: TradeOffer) {
        commit { save in
            guard let i = save.tradeOffers.firstIndex(where: { $0.id == offer.id }) else { return }
            save.tradeOffers[i].status = .cancelled
        }
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
        var offerId: String?
        if isUniversal, parts.count >= 2, parts[0] == "b" {
            offerId = parts[1]
        } else if isScheme, url.host == "b", let first = parts.first {
            offerId = first
        }
        // Blocked senders are dropped silently. TODO(server): block by sender account, not offer id.
        if let offerId, !save.blockedSenders.contains(offerId) {
            incomingOffer = IncomingOffer(id: offerId)
        }
        // `mixlings://home` (widget tap) and anything else: just open the app.
    }

    // MARK: Private

    private func commit(_ change: (inout SaveData) -> Void) {
        save = store.update { save in
            change(&save)
            CollectingEngine.awardSeasonBadges(&save, now: .now)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
