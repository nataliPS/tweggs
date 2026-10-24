import Foundation

/// Cached weather (§1). Written by the app's `LivingWeatherService` into the App Group
/// (`weather.json`); the widget only ever reads this cache. Contains no location: only the
/// classified weather, a few raw numbers for comments, and sunrise/sunset per local day.
struct WeatherSnapshot: Codable, Equatable, Sendable {
    struct Hour: Codable, Equatable, Sendable {
        /// Start of the hour.
        var date: Date
        var kind: WeatherKind
        var temperatureC: Double
    }

    struct Sun: Codable, Equatable, Sendable {
        /// Local day "yyyy-MM-dd" (in `WeatherSnapshot.timeZoneId`).
        var day: String
        var sunrise: Date?
        var sunset: Date?
    }

    var fetchedAt: Date
    var current: WeatherKind
    var currentTemperatureC: Double
    /// Next ~24 hours, oldest first.
    var hourly: [Hour]
    /// Today and the next days.
    var sun: [Sun]
    /// Time zone the `sun` day keys were computed in.
    var timeZoneId: String
    /// Display only (manual city name, or nil for "current location"). Never a coordinate.
    var placeName: String?

    /// Cache older than this is ignored (neutral weather) rather than shown as "now".
    static let staleAfter: TimeInterval = 6 * 3600
    /// Minimum time between fetches (≤ 1 fetch per 3 h per device, §1).
    static let refreshInterval: TimeInterval = 3 * 3600

    func needsRefresh(now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) >= Self.refreshInterval || now < fetchedAt
    }

    /// Classified weather at `date`: the hourly forecast slot containing it, else `current`
    /// while the cache is fresh, else `.none` (never guess).
    func kind(at date: Date) -> WeatherKind {
        if let h = hourly.last(where: { $0.date <= date && date < $0.date.addingTimeInterval(3600) }) {
            return h.kind
        }
        if date >= fetchedAt.addingTimeInterval(-3600), date < fetchedAt.addingTimeInterval(Self.staleAfter) {
            return current
        }
        return .none
    }

    func temperature(at date: Date) -> Double? {
        if let h = hourly.last(where: { $0.date <= date && date < $0.date.addingTimeInterval(3600) }) {
            return h.temperatureC
        }
        if date >= fetchedAt, date < fetchedAt.addingTimeInterval(Self.staleAfter) { return currentTemperatureC }
        return nil
    }

    func sun(forDay day: String) -> Sun? { sun.first { $0.day == day } }
}

/// Pure weather classification (§1 table). Thresholds: heat ≥ 28 °C or UV ≥ 8, snow ≤ 0 °C,
/// wind ≥ 30 km/h. Precipitation in the condition wins over temperature; rain is cosy, never sad.
enum WeatherClassifier {
    static let heatC: Double = 28
    static let heatUV: Int = 8
    static let freezeC: Double = 0
    static let windKmh: Double = 30

    /// `condition` is WeatherKit's `WeatherCondition.rawValue` (e.g. "heavyRain", "flurries").
    static func classify(condition: String, temperatureC: Double, windKmh: Double, uvIndex: Int) -> WeatherKind {
        let c = condition.lowercased()
        let snowWords = ["snow", "flurries", "sleet", "blizzard", "wintry", "hail"]
        let rainWords = ["rain", "drizzle", "shower", "thunder", "storm", "hurricane"]
        if snowWords.contains(where: { c.contains($0) }) { return .snow }
        if rainWords.contains(where: { c.contains($0) }) { return .rain }
        if temperatureC <= freezeC || c.contains("frigid") { return .snow }
        if temperatureC >= heatC || uvIndex >= heatUV || c == "hot" { return .heat }
        if windKmh >= Self.windKmh || c.contains("wind") || c.contains("breezy") { return .wind }
        return .none
    }
}

/// Last known device state for §13 alive frames (charging = snack, Low Power Mode = blanket nap).
/// The app writes it on change; the widget uses it only shortly after `updatedAt`.
struct DeviceSnapshot: Codable, Equatable, Sendable {
    var charging: Bool
    var lowPower: Bool
    var updatedAt: Date

    /// How long a cached state is trusted by the widget (the phone may be unplugged any time).
    static let validFor: TimeInterval = 60 * 60

    func isValid(at date: Date) -> Bool {
        date >= updatedAt.addingTimeInterval(-60) && date < updatedAt.addingTimeInterval(Self.validFor)
    }
}

/// JSON caches next to `active.json` in the App Group: `weather.json` and `device.json`.
/// Both are tiny and written atomically; the widget reads them, only the app writes them.
struct LivingCache: Sendable {
    static let weatherFileName = "weather.json"
    static let deviceFileName = "device.json"
    static let shared = LivingCache()

    let weatherURL: URL
    let deviceURL: URL

    init() {
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: CreatureStore.appGroupId)
            ?? (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        weatherURL = base.appendingPathComponent(Self.weatherFileName, isDirectory: false)
        deviceURL = base.appendingPathComponent(Self.deviceFileName, isDirectory: false)
    }

    init(directory: URL) {
        weatherURL = directory.appendingPathComponent(Self.weatherFileName, isDirectory: false)
        deviceURL = directory.appendingPathComponent(Self.deviceFileName, isDirectory: false)
    }

    func loadWeather() -> WeatherSnapshot? { read(WeatherSnapshot.self, from: weatherURL) }
    func saveWeather(_ s: WeatherSnapshot?) {
        if let s { write(s, to: weatherURL) } else { try? FileManager.default.removeItem(at: weatherURL) }
    }

    func loadDevice() -> DeviceSnapshot? { read(DeviceSnapshot.self, from: deviceURL) }
    func saveDevice(_ s: DeviceSnapshot) { write(s, to: deviceURL) }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            print("LivingCache write failed (\(url.lastPathComponent)): \(error)")
            #endif
        }
    }
}
