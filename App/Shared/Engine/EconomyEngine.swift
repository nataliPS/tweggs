import Foundation
import MixlingsGenome

/// App-side rules for slots (G5), spark sinks (G6), pity hint (G7) and generation badges (G8).
/// Pure: every function takes `now` / `timeZone` explicitly.
///
/// Founder rules: sparks are EARNED only (daily surprise). Nothing here sells sparks, and no
/// sink buys randomness: hatch-rush buys time, a gene hint buys information, the shop sells looks.
enum EconomyEngine {
    // MARK: Adapters to MixlingsGenome.Economy
    // Kept in one place so a rename in MixlingsKit is a one-line fix.

    static var freeSlots: Int { Economy.freeSlots }
    static var clubSlots: Int { Economy.clubSlots }
    static var hatchRushCost: Int { Economy.hatchRushCost }
    static var hatchRushDailyMax: Int { Economy.hatchRushDailyMax }
    static var geneHintCost: Int { Economy.geneHintCost }
    static var pityThreshold: Int { Economy.pityThreshold }
    static var shopPriceRange: ClosedRange<Int> { Economy.shopPriceMin...Economy.shopPriceMax }

    static func genBadges(generation: Int) -> [Int] {
        Economy.genBadges(generation: generation)
    }

    static func pairingCanProduce(_ a: Genome, _ b: Genome, entry: Collecting.SeasonEntry) -> Bool {
        guard (try? Genetics.validateGenome(a)) != nil, (try? Genetics.validateGenome(b)) != nil else { return false }
        return Economy.pairingCanProduce(a, b, gene: entry.gene, variant: entry.variant)
    }

    /// Indices into `genomes` of creatures carrying the entry's allele. Invalid genomes are skipped.
    static func carrierIndices(_ genomes: [Genome], entry: Collecting.SeasonEntry) -> [Int] {
        let blank: Genome = Array(repeating: [0, 0], count: Catalog.geneCount)
        var valid: [Bool] = []
        var safe: [Genome] = []
        for g in genomes {
            let ok = (try? Genetics.validateGenome(g)) != nil
            valid.append(ok)
            safe.append(ok ? g : blank)
        }
        return Economy.carrierHint(safe, entry: entry).filter { valid[$0] }
    }

    // MARK: Slots (G5)

    static func slotLimit(isClubMember: Bool) -> Int {
        isClubMember ? clubSlots : freeSlots
    }

    static func slotLimit(_ save: SaveData) -> Int { slotLimit(isClubMember: save.isClubMember) }

    static func freeSlotCount(_ save: SaveData) -> Int {
        max(0, slotLimit(save) - save.activeSlotCreatures.count)
    }

    /// True if a new creature can join the active slots.
    static func hasFreeSlot(_ save: SaveData) -> Bool { freeSlotCount(save) > 0 }

    enum SlotError: Error, Equatable { case notFound, slotsFull, lastActive }

    /// Moves a creature to the sanctuary. Never deletes. The last active creature stays (the
    /// Home screen and widget always need one).
    static func moveToSanctuary(_ save: inout SaveData, creatureId: String) -> Result<Void, SlotError> {
        guard let i = save.creatures.firstIndex(where: { $0.id == creatureId }) else { return .failure(.notFound) }
        if save.creatures[i].inSanctuary { return .success(()) }
        guard save.activeSlotCreatures.count > 1 else { return .failure(.lastActive) }
        save.creatures[i].inSanctuary = true
        if save.activeCreatureId == creatureId {
            save.activeCreatureId = save.activeSlotCreatures.first?.id
        }
        return .success(())
    }

    /// Brings a creature back from the sanctuary if a slot is free.
    static func moveToActive(_ save: inout SaveData, creatureId: String) -> Result<Void, SlotError> {
        guard let i = save.creatures.firstIndex(where: { $0.id == creatureId }) else { return .failure(.notFound) }
        if !save.creatures[i].inSanctuary { return .success(()) }
        guard hasFreeSlot(save) else { return .failure(.slotsFull) }
        save.creatures[i].inSanctuary = false
        return .success(())
    }

    /// Adds a new creature: into an active slot if one is free, else straight to the sanctuary.
    /// Nothing is ever turned away or deleted.
    static func admit(_ creature: Creature, to save: inout SaveData) {
        var c = creature
        if save.creature(id: c.id) == nil { c.inSanctuary = !hasFreeSlot(save) }
        save.replace(c)
    }

    // MARK: Hatch-rush (G6)

    enum SinkError: Error, Equatable { case notEnoughSparks, alreadyUsedToday, notGrowing, notFound }

    static func canHatchRush(_ save: SaveData, creature: Creature, now: Date,
                             timeZone: TimeZone = .current) -> Result<Void, SinkError> {
        guard CareEngine.nextGrowth(creature, at: now) != nil else { return .failure(.notGrowing) }
        guard save.lastHatchRushDay != CollectingEngine.dayKey(now, timeZone: timeZone) else {
            return .failure(.alreadyUsedToday)
        }
        guard save.sparks >= hatchRushCost else { return .failure(.notEnoughSparks) }
        return .success(())
    }

    /// Skips one day of growth for `hatchRushCost` sparks, max once per local day.
    /// Implemented by moving the creature's schedule one day earlier (stats are projected first,
    /// so no care time is lost or gained).
    @discardableResult
    static func hatchRush(_ save: inout SaveData, creatureId: String, now: Date,
                          timeZone: TimeZone = .current) -> Result<Void, SinkError> {
        guard let c = save.creature(id: creatureId) else { return .failure(.notFound) }
        if case .failure(let e) = canHatchRush(save, creature: c, now: now, timeZone: timeZone) { return .failure(e) }
        var out = CareEngine.decay(c, to: now)
        out.bornAt = out.bornAt.addingTimeInterval(-CareEngine.day)
        if let h = out.hatchedAt { out.hatchedAt = h.addingTimeInterval(-CareEngine.day) }
        // An egg that "should" have hatched now does: anchor the hatch to now at the latest,
        // so decay never counts time from before the rush.
        if out.hatchedAt == nil, CareEngine.hatchDate(out) <= now { out.hatchedAt = CareEngine.hatchDate(out) }
        save.replace(out)
        save.sparks -= hatchRushCost
        save.lastHatchRushDay = CollectingEngine.dayKey(now, timeZone: timeZone)
        return .success(())
    }

    // MARK: Gene hint (G6)

    struct GeneHint: Equatable, Sendable {
        let entry: Collecting.SeasonEntry
        /// Pairs of the player's creature ids that can produce the entry.
        let pairs: [[String]]
    }

    static func geneHintKey(season: Collecting.Season, entry: Collecting.SeasonEntry) -> String {
        "\(season.id)|\(entry.gene)|\(entry.variant)"
    }

    /// Which of the player's breedable pairings can produce `entry` (mutation ignored).
    static func geneHint(entry: Collecting.SeasonEntry, creatures: [Creature], now: Date) -> GeneHint {
        let breeders = creatures.filter { CareEngine.canBreed($0, at: now) }
        var pairs: [[String]] = []
        for i in breeders.indices {
            for j in breeders.indices where j > i {
                if pairingCanProduce(breeders[i].genome, breeders[j].genome, entry: entry) {
                    pairs.append([breeders[i].id, breeders[j].id])
                }
            }
        }
        return GeneHint(entry: entry, pairs: pairs)
    }

    /// Pays for a gene hint (once per entry; re-opening a paid hint is free).
    @discardableResult
    static func buyGeneHint(_ save: inout SaveData, season: Collecting.Season,
                            entry: Collecting.SeasonEntry) -> Result<Void, SinkError> {
        let key = geneHintKey(season: season, entry: entry)
        if save.geneHintKeys.contains(key) { return .success(()) }
        guard save.sparks >= geneHintCost else { return .failure(.notEnoughSparks) }
        save.sparks -= geneHintCost
        save.geneHintKeys.append(key)
        return .success(())
    }

    // MARK: Cosmetic shop (G6, placeholder)

    struct ShopItem: Identifiable, Equatable, Sendable {
        let id: String
        let price: Int
    }

    /// Placeholder catalogue. TODO(art): real cosmetics; TODO(server): live-ops prices (T5).
    static let shopItems: [ShopItem] = [
        ShopItem(id: "flower_crown", price: 100),
        ShopItem(id: "tiny_scarf", price: 120),
        ShopItem(id: "star_pin", price: 150),
        ShopItem(id: "bow_tie", price: 180),
        ShopItem(id: "biome_meadow", price: 250),
        ShopItem(id: "biome_night_sky", price: 300),
    ]

    @discardableResult
    static func buy(_ item: ShopItem, save: inout SaveData) -> Result<Void, SinkError> {
        guard save.sparks >= item.price else { return .failure(.notEnoughSparks) }
        save.sparks -= item.price
        save.cosmetics.append(item.id)
        return .success(())
    }

    // MARK: Pity hint (G7)

    static func pityHintActive(_ save: SaveData) -> Bool {
        save.breedsWithoutNewEntry >= pityThreshold
    }

    /// Season entries the player doesn't have yet.
    static func missingEntries(_ season: Collecting.Season, creatures: [Creature]) -> [Collecting.SeasonEntry] {
        let progress = CollectingEngine.seasonProgress(season, creatures: creatures)
        return season.entries.enumerated().compactMap { i, e in
            progress.indices.contains(i) && progress[i] ? nil : e
        }
    }

    /// Ids of the player's creatures that carry an allele of any missing season entry.
    static func carrierIds(season: Collecting.Season, creatures: [Creature]) -> Set<String> {
        var ids = Set<String>()
        let genomes = creatures.map(\.genome)
        for entry in missingEntries(season, creatures: creatures) {
            for i in carrierIndices(genomes, entry: entry) { ids.insert(creatures[i].id) }
        }
        return ids
    }

    /// A confirmed breed's child joins the save (G5 admit) and is counted for the pity hint (G7).
    /// The ONLY place a bred child is added, so the counter can't be skipped. Previews must not
    /// call this (they are not breeds). Idempotent per child id: a child already in the save
    /// (e.g. a re-delivered server result) is not counted twice.
    static func completeBreed(_ save: inout SaveData, child: Creature, now: Date,
                              timeZone: TimeZone = .current) {
        guard save.creature(id: child.id) == nil else { return }
        admit(child, to: &save)
        let stored = save.creature(id: child.id) ?? child
        recordBreed(&save, child: stored, season: CollectingEngine.currentSeason(now: now, timeZone: timeZone))
    }

    /// Number of entries of the current season still missing from the whole collection.
    static func missingCount(_ save: SaveData, now: Date, timeZone: TimeZone = .current) -> Int? {
        guard let season = CollectingEngine.currentSeason(now: now, timeZone: timeZone) else { return nil }
        return missingEntries(season, creatures: save.creatures).count
    }

    /// G7: "breeds without a new season entry" restarts whenever a new entry is found, however
    /// it arrived (breed, trade, gift). Compare the missing count before and after a change.
    static func resetPityIfNewEntry(_ save: inout SaveData, missingBefore: Int?, now: Date,
                                    timeZone: TimeZone = .current) {
        guard let before = missingBefore,
              let after = missingCount(save, now: now, timeZone: timeZone), after < before else { return }
        save.breedsWithoutNewEntry = 0
    }

    /// Call after every CONFIRMED breed (not previews): resets the counter if the child filled a
    /// missing entry, else counts one more breed without a new entry. Prefer `completeBreed`.
    static func recordBreed(_ save: inout SaveData, child: Creature, season: Collecting.Season?) {
        guard let season else { save.breedsWithoutNewEntry += 1; return }
        let others = save.creatures.filter { $0.id != child.id }
        let before = missingEntries(season, creatures: others).count
        let after = missingEntries(season, creatures: others + [child]).count
        if after < before {
            save.breedsWithoutNewEntry = 0
        } else {
            save.breedsWithoutNewEntry += 1
        }
    }
}

// MARK: - Daily spark cap (living-world spec §0)

/// New earning sources (living world). The daily surprise is NOT one of them: it keeps its own
/// once-per-day rule and never counts against the cap.
enum SparkSource: String, Codable, CaseIterable, Sendable {
    case weatherItem, jumpRope, souvenir, alarm, visit
}

extension EconomyEngine {
    /// One cap across all `SparkSource`s per local day. TODO(server): live-ops config (T5).
    static let dailySparkCap = 60

    /// Sparks still earnable today from capped sources.
    static func sparkCapRemaining(_ save: SaveData, now: Date, timeZone: TimeZone = .current) -> Int {
        let today = CollectingEngine.dayKey(now, timeZone: timeZone)
        let earned = save.living.sparkCapDay == today ? save.living.sparkCapEarned : 0
        return max(0, dailySparkCap - earned)
    }

    /// Grants up to `amount` sparks from a capped source and returns what was actually granted
    /// (0 once today's cap is reached; never negative, never takes sparks away).
    @discardableResult
    static func grantCappedSparks(_ save: inout SaveData, amount: Int, source: SparkSource, now: Date,
                                  timeZone: TimeZone = .current) -> Int {
        guard amount > 0 else { return 0 }
        let today = CollectingEngine.dayKey(now, timeZone: timeZone)
        if save.living.sparkCapDay != today {
            save.living.sparkCapDay = today
            save.living.sparkCapEarned = 0
        }
        let granted = min(amount, max(0, dailySparkCap - save.living.sparkCapEarned))
        guard granted > 0 else { return 0 }
        save.living.sparkCapEarned += granted
        save.sparks += granted
        return granted
    }
}
