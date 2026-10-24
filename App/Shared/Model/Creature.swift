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
        serial: Int? = nil
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, genome, origin, paletteShift, bornAt, hatchedAt, mood, hunger, joy, lastUpdated
        case generation, parentIds, discoveredFirst, serial
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
    }

    /// Look key for discovery / encyclopedia (genome-spec §8). Nil for a corrupt genome.
    var comboKey: String? { try? Collecting.comboKey(genome: genome) }

    var moodValue: Int { Int(mood.rounded()) }
    var hungerValue: Int { Int(hunger.rounded()) }
    var joyValue: Int { Int(joy.rounded()) }
}

/// Everything persisted by `CreatureStore`. Versioned for future migrations.
/// v2 (collecting): sparks, daily surprise, cosmetics, hatch counter, discovery log,
/// season badges, trade offers. Every v2 field has a decode default, so v1 files load.
struct SaveData: Codable, Equatable, Sendable {
    static let currentVersion = 2

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
        tradeOffers: [TradeOffer] = []
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
    }

    private enum CodingKeys: String, CodingKey {
        case version, playerId, creatures, activeCreatureId, onboardingComplete
        case sparks, lastSurpriseDay, cosmetics, hatchCounter, discoveries, seasonBadges, tradeOffers
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
        if version < 2 { migrateToV2() }
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

    var activeCreature: Creature? {
        if let id = activeCreatureId, let c = creatures.first(where: { $0.id == id }) { return c }
        return creatures.first
    }

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
