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
        lastUpdated: Date? = nil
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
    }

    var moodValue: Int { Int(mood.rounded()) }
    var hungerValue: Int { Int(hunger.rounded()) }
    var joyValue: Int { Int(joy.rounded()) }
}

/// Everything persisted by `CreatureStore`. Versioned for future migrations.
struct SaveData: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    /// Random local player id (UUID string). Used as `starter(playerId, slot)` input and as
    /// breeding owner key. TODO(server): replace/link with an authenticated account id.
    var playerId: String
    var creatures: [Creature]
    var activeCreatureId: String?
    var onboardingComplete: Bool

    init(
        version: Int = SaveData.currentVersion,
        playerId: String = UUID().uuidString.lowercased(),
        creatures: [Creature] = [],
        activeCreatureId: String? = nil,
        onboardingComplete: Bool = false
    ) {
        self.version = version
        self.playerId = playerId
        self.creatures = creatures
        self.activeCreatureId = activeCreatureId
        self.onboardingComplete = onboardingComplete
    }

    var activeCreature: Creature? {
        if let id = activeCreatureId, let c = creatures.first(where: { $0.id == id }) { return c }
        return creatures.first
    }

    func creature(id: String) -> Creature? {
        creatures.first(where: { $0.id == id })
    }

    mutating func replace(_ creature: Creature) {
        if let i = creatures.firstIndex(where: { $0.id == creature.id }) {
            creatures[i] = creature
        } else {
            creatures.append(creature)
        }
    }
}
