import Foundation

// Living world (docs/living-world-spec.md). Plain value types shared by the app, the widget
// and the tests. Raw values of `WeatherKind` and `CareItem` match MixlingsArt's
// `Phenotype.weather` / `Phenotype.item` encodings (see `ArtAdapter`).

/// Weather as the creature experiences it (§1). `.night` is never produced by classification:
/// it is the sleeping/dark layer, decided by `ActivityStateMachine` from sunrise/sunset.
enum WeatherKind: Int, Codable, CaseIterable, Hashable, Sendable {
    case none = 0
    case rain = 1
    case heat = 2
    case snow = 3
    case wind = 4
    case night = 5

    var title: LocalizedStringResource {
        switch self {
        case .none: return "Clear"
        case .rain: return "Rain"
        case .heat: return "Hot"
        case .snow: return "Snow"
        case .wind: return "Windy"
        case .night: return "Night"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "sun.max.fill"
        case .rain: return "cloud.rain.fill"
        case .heat: return "thermometer.sun.fill"
        case .snow: return "snowflake"
        case .wind: return "wind"
        case .night: return "moon.stars.fill"
        }
    }
}

/// Cosmetic care items (§1, §8). Always free to earn; kept in the collection once given.
enum CareItem: Int, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case umbrella = 1
    case water = 2
    case fan = 3
    case sunHat = 4
    case scarf = 5
    case beanie = 6
    case blanket = 7
    case jumpRope = 8

    var id: Int { rawValue }

    /// Items that can be handed over from the care-item tray (the rope is won in the mini-game).
    static let giveable: [CareItem] = [.umbrella, .water, .fan, .sunHat, .scarf, .beanie, .blanket]

    /// Weather kinds this item is "right" for. Wind has no item (§1).
    var suits: Set<WeatherKind> {
        switch self {
        case .umbrella: return [.rain]
        case .water, .fan, .sunHat: return [.heat]
        case .scarf, .beanie: return [.snow]
        case .blanket: return [.night]
        case .jumpRope: return []
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .umbrella: return "Umbrella"
        case .water: return "Water bottle"
        case .fan: return "Fan"
        case .sunHat: return "Sun hat"
        case .scarf: return "Scarf"
        case .beanie: return "Beanie"
        case .blanket: return "Blanket"
        case .jumpRope: return "Jump rope"
        }
    }

    var systemImage: String {
        switch self {
        case .umbrella: return "umbrella.fill"
        case .water: return "waterbottle.fill"
        case .fan: return "fan.fill"
        case .sunHat: return "sun.max.fill"
        case .scarf: return "wind.snow"
        case .beanie: return "snowflake"
        case .blanket: return "bed.double.fill"
        case .jumpRope: return "figure.jumprope"
        }
    }
}

/// City picked by hand when location permission is off (§1). Coarse coordinates only
/// (rounded to 0.1°, ~10 km); stored on device, never sent to our servers.
struct ManualCity: Codable, Equatable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double

    init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = (latitude * 10).rounded() / 10
        self.longitude = (longitude * 10).rounded() / 10
    }
}

/// Living-world part of `SaveData` (additive; every field has a decode default, no version bump).
struct LivingState: Codable, Equatable, Sendable {
    // Daily spark cap across all new earning sources (§0).
    var sparkCapDay: String?
    var sparkCapEarned: Int

    // Weather care items (§1).
    /// Weather event ids already rewarded (once per event), newest last.
    var rewardedWeatherEvents: [String]
    /// Weather event id -> item given for it (drawn on the creature while the event lasts).
    var givenItems: [String: Int]
    /// `CareItem` raw values in the collection.
    var ownedItems: [Int]

    // Jump rope (§8).
    var jumpRopeBest: Int
    var jumpRopeGames: Int
    /// "I have an idea!" bubbles: local day + how many were used/dismissed that day (max 2).
    var ideaDay: String?
    var ideasUsed: Int

    // Pair life (§9).
    /// Second creature in the house; nil = pick automatically.
    var housePartnerId: String?
    /// Last time the app was active (start of "While you were away").
    var lastActiveAt: Date?

    // Settings (all opt-in).
    var weatherEnabled: Bool
    var useLocation: Bool
    var manualCity: ManualCity?
    var nudgesEnabled: Bool

    static let rewardedEventLimit = 60
    static let givenItemLimit = 30

    init(sparkCapDay: String? = nil, sparkCapEarned: Int = 0, rewardedWeatherEvents: [String] = [],
         givenItems: [String: Int] = [:], ownedItems: [Int] = [], jumpRopeBest: Int = 0,
         jumpRopeGames: Int = 0, ideaDay: String? = nil, ideasUsed: Int = 0,
         housePartnerId: String? = nil, lastActiveAt: Date? = nil, weatherEnabled: Bool = false,
         useLocation: Bool = false, manualCity: ManualCity? = nil, nudgesEnabled: Bool = false) {
        self.sparkCapDay = sparkCapDay
        self.sparkCapEarned = sparkCapEarned
        self.rewardedWeatherEvents = rewardedWeatherEvents
        self.givenItems = givenItems
        self.ownedItems = ownedItems
        self.jumpRopeBest = jumpRopeBest
        self.jumpRopeGames = jumpRopeGames
        self.ideaDay = ideaDay
        self.ideasUsed = ideasUsed
        self.housePartnerId = housePartnerId
        self.lastActiveAt = lastActiveAt
        self.weatherEnabled = weatherEnabled
        self.useLocation = useLocation
        self.manualCity = manualCity
        self.nudgesEnabled = nudgesEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case sparkCapDay, sparkCapEarned, rewardedWeatherEvents, givenItems, ownedItems
        case jumpRopeBest, jumpRopeGames, ideaDay, ideasUsed, housePartnerId, lastActiveAt
        case weatherEnabled, useLocation, manualCity, nudgesEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sparkCapDay = try c.decodeIfPresent(String.self, forKey: .sparkCapDay)
        sparkCapEarned = try c.decodeIfPresent(Int.self, forKey: .sparkCapEarned) ?? 0
        rewardedWeatherEvents = try c.decodeIfPresent([String].self, forKey: .rewardedWeatherEvents) ?? []
        givenItems = try c.decodeIfPresent([String: Int].self, forKey: .givenItems) ?? [:]
        ownedItems = try c.decodeIfPresent([Int].self, forKey: .ownedItems) ?? []
        jumpRopeBest = try c.decodeIfPresent(Int.self, forKey: .jumpRopeBest) ?? 0
        jumpRopeGames = try c.decodeIfPresent(Int.self, forKey: .jumpRopeGames) ?? 0
        ideaDay = try c.decodeIfPresent(String.self, forKey: .ideaDay)
        ideasUsed = try c.decodeIfPresent(Int.self, forKey: .ideasUsed) ?? 0
        housePartnerId = try c.decodeIfPresent(String.self, forKey: .housePartnerId)
        lastActiveAt = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        weatherEnabled = try c.decodeIfPresent(Bool.self, forKey: .weatherEnabled) ?? false
        useLocation = try c.decodeIfPresent(Bool.self, forKey: .useLocation) ?? false
        manualCity = try? c.decodeIfPresent(ManualCity.self, forKey: .manualCity)
        nudgesEnabled = try c.decodeIfPresent(Bool.self, forKey: .nudgesEnabled) ?? false
    }

    var owned: [CareItem] { ownedItems.compactMap(CareItem.init(rawValue:)) }

    func owns(_ item: CareItem) -> Bool { ownedItems.contains(item.rawValue) }
}
