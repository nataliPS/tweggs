import Foundation
import MixlingsGenome

/// Life stage. Stored implicitly (derived from `bornAt` / `hatchedAt`) so it can never drift.
enum Stage: Int, Codable, CaseIterable, Comparable, Sendable {
    case egg = 0
    case baby = 1
    case teen = 2
    case adult = 3

    static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .egg: return "Egg"
        case .baby: return "Baby"
        case .teen: return "Teen"
        case .adult: return "Adult"
        }
    }

    var next: Stage? { Stage(rawValue: rawValue + 1) }
}

/// How a creature came to be. Only informational in the prototype.
enum CreatureOrigin: String, Codable, Sendable {
    case hatched   // onboarding egg
    case starter   // free starter adult
    case bred      // child from breeding (later: server-validated)
}

/// Coarse emotional state derived from the stats. There is deliberately no "dead" state:
/// the lowest a Mixling can get is `.sleepy` (stats are floored by `CareEngine`).
enum Condition: String, Codable, Sendable {
    case happy
    case okay
    case sleepy

    var title: LocalizedStringResource {
        switch self {
        case .happy: return "Happy"
        case .okay: return "Okay"
        case .sleepy: return "Sleepy"
        }
    }
}

/// One creature. Stats are stored "as of `lastUpdated`"; call `CareEngine.decay(_:to:)`
/// to project them to another moment. All stats are 0...100 (higher is better):
/// - `hunger`: belly fullness (100 = just fed)
/// - `joy`: fun / play
/// - `mood`: affection / overall mood
struct Creature: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// `[[a, b] x 8]` in catalog gene order (genome-spec §1).
    var genome: Genome
    var origin: CreatureOrigin
    /// Twin palette shift for this owner (genome-spec §4.5). 0 for own/starter creatures.
    var paletteShift: Int

    /// When the egg was created.
    var bornAt: Date
    /// When the egg hatched. `nil` while still an egg that hasn't reached its natural hatch time.
    var hatchedAt: Date?

    var mood: Double
    var hunger: Double
    var joy: Double
    var lastUpdated: Date

    // MARK: Collecting (added in save v2; all have decode defaults so v1 saves still load)

    /// 0 for starters / the onboarding egg, `max(parent generations) + 1` for hybrids.
    var generation: Int
    /// Parent creature ids if known (hybrids). Nil for starters and old saves.
    var parentIds: [String]?
    /// True if this creature was the first to show its look (`comboKey`) in the local `DiscoveryLog`.
    /// TODO(server): global "first in the world" claim; for now this is first on this device.
    var discoveredFirst: Bool
    /// Card serial ("№ 1 287"). Assigned from the local counter when the creature joins the save.
    /// TODO(server): global serial issued by the server.
    var serial: Int?

    // MARK: Slots (added in save v3)

    /// G5: resting in the free, unlimited sanctuary instead of an active slot. Never deleted.
    var inSanctuary: Bool

    init(
        id: String,
        name: String,
        genome: Genome,
        origin: CreatureOrigin,
        paletteShift: Int = 0,
        bornAt: Date,
        hatchedAt: Date? = nil,
        mood: Double = CareEngine.startValue,
        hunger: Double = CareEngine.startValue,
        joy: Double = CareEngine.startValue,
        lastUpdated: Date? = nil,
        generation: Int = 0,
        parentIds: [String]? = nil,
        discoveredFirst: Bool = false,
        serial: Int? = nil,
        inSanctuary: Bool = false
    ) {
        self.id = id
        self.name = name
        self.genome = genome
        self.origin = origin
        self.paletteShift = paletteShift
        self.bornAt = bornAt
        self.hatchedAt = hatchedAt
        self.mood = mood
        self.hunger = hunger
        self.joy = joy
        self.lastUpdated = lastUpdated ?? bornAt
        self.generation = generation
        self.parentIds = parentIds
        self.discoveredFirst = discoveredFirst
        self.serial = serial
        self.inSanctuary = inSanctuary
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, genome, origin, paletteShift, bornAt, hatchedAt, mood, hunger, joy, lastUpdated
        case generation, parentIds, discoveredFirst, serial
        case inSanctuary
    }

    /// Tolerant decoding: fields added after v1 fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        genome = try c.decode(Genome.self, forKey: .genome)
        origin = try c.decode(CreatureOrigin.self, forKey: .origin)
        paletteShift = try c.decodeIfPresent(Int.self, forKey: .paletteShift) ?? 0
        bornAt = try c.decode(Date.self, forKey: .bornAt)
        hatchedAt = try c.decodeIfPresent(Date.self, forKey: .hatchedAt)
        mood = try c.decodeIfPresent(Double.self, forKey: .mood) ?? CareEngine.startValue
        hunger = try c.decodeIfPresent(Double.self, forKey: .hunger) ?? CareEngine.startValue
        joy = try c.decodeIfPresent(Double.self, forKey: .joy) ?? CareEngine.startValue
        lastUpdated = try c.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? bornAt
        generation = try c.decodeIfPresent(Int.self, forKey: .generation) ?? 0
        parentIds = try c.decodeIfPresent([String].self, forKey: .parentIds)
        discoveredFirst = try c.decodeIfPresent(Bool.self, forKey: .discoveredFirst) ?? false
        serial = try c.decodeIfPresent(Int.self, forKey: .serial)
        inSanctuary = try c.decodeIfPresent(Bool.self, forKey: .inSanctuary) ?? false
    }

    /// Look key for discovery / encyclopedia (genome-spec §8). Nil for a corrupt genome.
    var comboKey: String? { try? Collecting.comboKey(genome: genome) }

    var moodValue: Int { Int(mood.rounded()) }
    var hungerValue: Int { Int(hunger.rounded()) }
    var joyValue: Int { Int(joy.rounded()) }
}

/// Everything persisted by `CreatureStore` (collection.json). Versioned for future migrations.
/// v2 (collecting): sparks, daily surprise, cosmetics, hatch counter, discovery log,
/// season badges, trade offers. Every v2 field has a decode default, so v1 files load.
/// v3 (retro 2026-10-24): persisted starter genomes (T2), sanctuary flag on creatures (G5),
/// age band (C2), spark sinks (G6), pity counter (G7), first-share flag (U1), report/block (C3).
struct SaveData: Codable, Equatable, Sendable {
    static let currentVersion = 3

    var version: Int
    /// Random local player id (UUID string). Used as `starter(playerId, slot)` input and as
    /// breeding owner key. TODO(server): replace/link with an authenticated account id.
    var playerId: String
    var creatures: [Creature]
    var activeCreatureId: String?
    var onboardingComplete: Bool

    /// Soft currency from the free daily surprise. Never bought, never sold.
    var sparks: Int
    /// Local day ("yyyy-MM-dd") the daily surprise was last opened.
    var lastSurpriseDay: String?
    /// Cosmetic placeholder ids won from surprises (may repeat).
    var cosmetics: [String]
    /// Local count of creatures that joined this save; source of `Creature.serial`.
    var hatchCounter: Int
    var discoveries: DiscoveryLog
    /// Season ids whose album was completed (badge stays even if creatures leave later).
    var seasonBadges: [String]
    /// Trade offers created on this device. TODO(server): offers live on the server.
    var tradeOffers: [TradeOffer]

    // MARK: v3

    /// T2: starter genomes by slot ("0" onboarding egg, "1" gift adult, "2" day-2 baby).
    /// Written once and never re-derived, so a future change to `Genetics.starter` can't
    /// silently change a player's starters.
    var starterGenomes: [String: Genome]
    /// C2: coarse age band from the neutral age screen. Only the band is stored, never the year.
    var ageBand: AgeBand?
    /// Mix Club (subscription) flag. TODO(storekit): derive from `Transaction.currentEntitlements`.
    var isClubMember: Bool
    /// G7: breeds in a row whose child did not fill a missing season entry.
    var breedsWithoutNewEntry: Int
    /// G6: local day of the last hatch-rush (max 1 per day).
    var lastHatchRushDay: String?
    /// G6: gene hints already paid for (`SparkSinks.geneHintKey`); re-opening one is free.
    var geneHintKeys: [String]
    /// U1/H3: the "Make a baby with a friend" prompt was shown after onboarding.
    var firstSharePromptShown: Bool
    /// C3: offer ids / sender keys the player blocked or reported. TODO(server): send reports.
    var blockedSenders: [String]
    var reportedOffers: [String]
    /// G4: when the day-2 gift baby arrives. Anchored to the onboarding hatch (+1 day), never to
    /// a creature's hatch time (hatch-rush moves that). Nil before onboarding. Older saves get it
    /// inferred on decode (`inferredGiftBabyDueAt`).
    var giftBabyDueAt: Date?
    /// T4: ids of widget care events (`CareEvent`) already merged into this save, newest last.
    /// Makes the merge idempotent; capped at `CreatureStore.appliedCareIdLimit`.
    var appliedCareEventIds: [String]

    init(
        version: Int = SaveData.currentVersion,
        playerId: String = UUID().uuidString.lowercased(),
        creatures: [Creature] = [],
        activeCreatureId: String? = nil,
        onboardingComplete: Bool = false,
        sparks: Int = 0,
        lastSurpriseDay: String? = nil,
        cosmetics: [String] = [],
        hatchCounter: Int = 0,
        discoveries: DiscoveryLog = DiscoveryLog(),
        seasonBadges: [String] = [],
        tradeOffers: [TradeOffer] = [],
        starterGenomes: [String: Genome] = [:],
        ageBand: AgeBand? = nil,
        isClubMember: Bool = false,
        breedsWithoutNewEntry: Int = 0,
        lastHatchRushDay: String? = nil,
        geneHintKeys: [String] = [],
        firstSharePromptShown: Bool = false,
        blockedSenders: [String] = [],
        reportedOffers: [String] = [],
        giftBabyDueAt: Date? = nil,
        appliedCareEventIds: [String] = []
    ) {
        self.version = version
        self.playerId = playerId
        self.creatures = creatures
        self.activeCreatureId = activeCreatureId
        self.onboardingComplete = onboardingComplete
        self.sparks = sparks
        self.lastSurpriseDay = lastSurpriseDay
        self.cosmetics = cosmetics
        self.hatchCounter = hatchCounter
        self.discoveries = discoveries
        self.seasonBadges = seasonBadges
        self.tradeOffers = tradeOffers
        self.starterGenomes = starterGenomes
        self.ageBand = ageBand
        self.isClubMember = isClubMember
        self.breedsWithoutNewEntry = breedsWithoutNewEntry
        self.lastHatchRushDay = lastHatchRushDay
        self.geneHintKeys = geneHintKeys
        self.firstSharePromptShown = firstSharePromptShown
        self.blockedSenders = blockedSenders
        self.reportedOffers = reportedOffers
        self.giftBabyDueAt = giftBabyDueAt
        self.appliedCareEventIds = appliedCareEventIds
    }

    private enum CodingKeys: String, CodingKey {
        case version, playerId, creatures, activeCreatureId, onboardingComplete
        case sparks, lastSurpriseDay, cosmetics, hatchCounter, discoveries, seasonBadges, tradeOffers
        case starterGenomes, ageBand, isClubMember, breedsWithoutNewEntry, lastHatchRushDay, geneHintKeys
        case firstSharePromptShown, blockedSenders, reportedOffers
        case giftBabyDueAt, appliedCareEventIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        playerId = try c.decode(String.self, forKey: .playerId)
        creatures = try c.decodeIfPresent([Creature].self, forKey: .creatures) ?? []
        activeCreatureId = try c.decodeIfPresent(String.self, forKey: .activeCreatureId)
        onboardingComplete = try c.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        sparks = try c.decodeIfPresent(Int.self, forKey: .sparks) ?? 0
        lastSurpriseDay = try c.decodeIfPresent(String.self, forKey: .lastSurpriseDay)
        cosmetics = try c.decodeIfPresent([String].self, forKey: .cosmetics) ?? []
        hatchCounter = try c.decodeIfPresent(Int.self, forKey: .hatchCounter) ?? 0
        discoveries = try c.decodeIfPresent(DiscoveryLog.self, forKey: .discoveries) ?? DiscoveryLog()
        seasonBadges = try c.decodeIfPresent([String].self, forKey: .seasonBadges) ?? []
        tradeOffers = try c.decodeIfPresent([TradeOffer].self, forKey: .tradeOffers) ?? []
        starterGenomes = try c.decodeIfPresent([String: Genome].self, forKey: .starterGenomes) ?? [:]
        // Unknown future band values must not make the whole save unreadable.
        ageBand = try? c.decodeIfPresent(AgeBand.self, forKey: .ageBand)
        isClubMember = try c.decodeIfPresent(Bool.self, forKey: .isClubMember) ?? false
        breedsWithoutNewEntry = try c.decodeIfPresent(Int.self, forKey: .breedsWithoutNewEntry) ?? 0
        lastHatchRushDay = try c.decodeIfPresent(String.self, forKey: .lastHatchRushDay)
        geneHintKeys = try c.decodeIfPresent([String].self, forKey: .geneHintKeys) ?? []
        firstSharePromptShown = try c.decodeIfPresent(Bool.self, forKey: .firstSharePromptShown) ?? false
        blockedSenders = try c.decodeIfPresent([String].self, forKey: .blockedSenders) ?? []
        reportedOffers = try c.decodeIfPresent([String].self, forKey: .reportedOffers) ?? []
        giftBabyDueAt = try c.decodeIfPresent(Date.self, forKey: .giftBabyDueAt)
        appliedCareEventIds = try c.decodeIfPresent([String].self, forKey: .appliedCareEventIds) ?? []
        if version < 2 { migrateToV2() }
        if version < 3 { migrateToV3() }
        // Additive v3 field (no version bump): fill from existing data once, then it is stored.
        if giftBabyDueAt == nil { giftBabyDueAt = inferredGiftBabyDueAt }
    }

    /// Onboarding time + 1 day, recovered from saves written before `giftBabyDueAt` existed.
    /// The starter adult (slot 1) is created at the onboarding hatch and is backdated to be
    /// exactly adult then; adults can't be hatch-rushed, so its schedule still pins that moment.
    /// Fallback: the first hatched creature's hatch time (may be early if it was rushed).
    var inferredGiftBabyDueAt: Date? {
        guard !creatures.isEmpty else { return nil }
        let adultId = CreatureFactory.starterId(playerId: playerId, slot: CreatureFactory.Slot.giftAdult)
        let giftId = CreatureFactory.starterId(playerId: playerId, slot: CreatureFactory.Slot.dayTwoBaby)
        if let adult = creature(id: adultId)
            ?? creatures.first(where: { $0.origin == .starter && $0.id != giftId }) {
            return CareEngine.date(of: .adult, for: adult).addingTimeInterval(CareEngine.day)
        }
        let eggId = CreatureFactory.starterId(playerId: playerId, slot: CreatureFactory.Slot.firstEgg)
        guard let first = creature(id: eggId) ?? creatures.first(where: { $0.origin == .hatched }),
              first.hatchedAt != nil else { return nil }
        return CareEngine.hatchDate(first).addingTimeInterval(CareEngine.day)
    }

    /// G4: the day-2 gift baby is due (onboarding finished and its time has come).
    func isGiftBabyDue(now: Date) -> Bool {
        guard onboardingComplete, let due = giftBabyDueAt else { return false }
        return now >= due
    }

    /// v1 -> v2: give existing creatures serials (in save order) and seed the discovery log.
    mutating func migrateToV2() {
        for i in creatures.indices {
            let original = creatures[i]
            let updated = registered(original, at: original.bornAt)
            creatures[i] = updated
        }
        version = 2
    }

    /// v2 -> v3 (T2): capture the starter genomes that are already in the save, so they are
    /// never re-derived. Matches the deterministic starter ids first, then falls back to origin
    /// (very old saves used other ids): first `.hatched` -> slot 0, first `.starter` -> slot 1.
    /// The age band stays nil, so the app asks once (C2). Everything else uses decode defaults.
    mutating func migrateToV3() {
        for slot in 0...2 {
            let key = String(slot)
            guard starterGenomes[key] == nil,
                  let c = creature(id: CreatureFactory.starterId(playerId: playerId, slot: slot)) else { continue }
            starterGenomes[key] = c.genome
        }
        if starterGenomes["0"] == nil, let c = creatures.first(where: { $0.origin == .hatched }) {
            starterGenomes["0"] = c.genome
        }
        if starterGenomes["1"] == nil, let c = creatures.first(where: { $0.origin == .starter }) {
            starterGenomes["1"] = c.genome
        }
        version = 3
    }

    /// T2: the persisted starter genome for `slot`, deriving and storing it on first use only.
    mutating func starterGenome(slot: Int) -> Genome? {
        let key = String(slot)
        if let g = starterGenomes[key] { return g }
        guard let g = try? Genetics.starter(playerId: playerId, slot: slot) else { return nil }
        starterGenomes[key] = g
        return g
    }

    /// The Home creature: the selected one, else the first creature in an active slot.
    var activeCreature: Creature? {
        if let id = activeCreatureId, let c = creatures.first(where: { $0.id == id }) { return c }
        return creatures.first(where: { !$0.inSanctuary }) ?? creatures.first
    }

    /// Creatures in active slots (G5).
    var activeSlotCreatures: [Creature] { creatures.filter { !$0.inSanctuary } }
    /// Creatures resting in the sanctuary (G5).
    var sanctuaryCreatures: [Creature] { creatures.filter(\.inSanctuary) }

    func creature(id: String) -> Creature? {
        creatures.first(where: { $0.id == id })
    }

    /// Updates an existing creature, or adds a new one. New creatures get a serial and are
    /// checked against the discovery log (see `registered`).
    mutating func replace(_ creature: Creature) {
        if let i = creatures.firstIndex(where: { $0.id == creature.id }) {
            // Callers may pass a copy taken before registration; never drop collecting state.
            let existing = creatures[i]
            var updated = creature
            if updated.serial == nil { updated.serial = existing.serial }
            updated.discoveredFirst = updated.discoveredFirst || existing.discoveredFirst
            creatures[i] = updated
        } else {
            let added = registered(creature, at: creature.bornAt)
            creatures.append(added)
        }
    }

    /// Assigns a serial (if missing) and records the creature's look in the discovery log.
    /// Every look is logged, but only bred hybrids can earn "Discoverer": starters are gifts,
    /// not discoveries. Idempotent for creatures that already have a serial / log entry.
    private mutating func registered(_ creature: Creature, at date: Date) -> Creature {
        var c = creature
        if c.serial == nil {
            hatchCounter += 1
            c.serial = hatchCounter
        }
        if let key = c.comboKey,
           discoveries.record(key: key, creatureId: c.id, at: date),
           c.origin == .bred {
            c.discoveredFirst = true
        }
        return c
    }
}

/// Local log of first-time looks, keyed by `Collecting.comboKey`.
/// TODO(server): submit new keys to the server to claim a global "first in the world" discovery.
struct DiscoveryLog: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var creatureId: String
        var date: Date
    }

    var entries: [String: Entry] = [:]

    init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    var count: Int { entries.count }

    func contains(_ key: String) -> Bool { entries[key] != nil }

    /// Records `key` if unseen. Returns true if this call was the first discovery.
    @discardableResult
    mutating func record(key: String, creatureId: String, at date: Date) -> Bool {
        guard entries[key] == nil else { return false }
        entries[key] = Entry(creatureId: creatureId, date: date)
        return true
    }
}

/// A friend-trade offer (stub). Free swap only: no tokens, no fees, no money, ever.
/// TODO(server): the server creates the offer, holds the creature in escrow, and swaps on accept.
struct TradeOffer: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        /// Created locally; link shared. Nothing has moved yet.
        case draft
        case cancelled
    }

    var id: String
    var creatureId: String
    var createdAt: Date
    var status: Status

    init(id: String = TradeOffer.makeId(), creatureId: String, createdAt: Date, status: Status = .draft) {
        self.id = id
        self.creatureId = creatureId
        self.createdAt = createdAt
        self.status = status
    }

    /// Placeholder link. TODO(server): offer id and URL come from the server.
    var url: URL {
        URL(string: "https://mix.orizolabs.app/t/\(id)") ?? URL(string: "https://mix.orizolabs.app")!
    }

    static func makeId() -> String {
        String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12))
    }
}
