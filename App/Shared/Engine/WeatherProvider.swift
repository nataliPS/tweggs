import Foundation
import MixlingsGenome

/// Where to look up the weather. Coarse coordinates only (0.1°); never stored server-side.
struct WeatherPlace: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// Display only (manual city name), nil = "current location".
    var name: String?
}

enum WeatherProviderKind: String, Sendable {
    /// Apple WeatherKit. Compiled in ONLY with the `TWEGGS_WEATHERKIT` flag (paid developer
    /// account + WeatherKit capability). See project.yml.
    case apple
    /// Deterministic, offline. Default in dev mode (free Apple ID: no WeatherKit entitlement).
    case simulated
}

/// One source of `WeatherSnapshot`s (§1). `LivingWeatherService` picks the provider through
/// `WeatherProviders.make()`; nothing else talks to a weather backend.
protocol WeatherProvider: Sendable {
    var kind: WeatherProviderKind { get }
    /// True when a place (location or manual city) is required; without one weather stays neutral.
    var needsPlace: Bool { get }
    func snapshot(for place: WeatherPlace?, now: Date, timeZone: TimeZone) async throws -> WeatherSnapshot
}

enum WeatherProviders {
    /// True only when the app was compiled with `TWEGGS_WEATHERKIT`.
    static var weatherKitCompiled: Bool {
        #if TWEGGS_WEATHERKIT
        return true
        #else
        return false
        #endif
    }

    /// Pure selection rule (tested): WeatherKit only when compiled in, else simulated.
    static func kind(weatherKitCompiled: Bool) -> WeatherProviderKind {
        weatherKitCompiled ? .apple : .simulated
    }

    static var currentKind: WeatherProviderKind { kind(weatherKitCompiled: weatherKitCompiled) }

    // `make()` (the factory) lives in the app target, Sources/Living/WeatherService.swift, next
    // to `AppleWeatherProvider`. The widget never fetches: it only reads the cache.
}

/// Developer override for the simulated provider (Living world settings, DEBUG builds only).
enum SimulatedWeather: String, CaseIterable, Identifiable, Sendable {
    case clear, rain, heat, snow, wind, night

    var id: String { rawValue }
}

enum SimulatedWeatherOverride {
    static let defaultsKey = "debug.simulatedWeather"

    /// Always nil in Release builds.
    static var current: SimulatedWeather? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: defaultsKey).flatMap(SimulatedWeather.init(rawValue:))
        #else
        return nil
        #endif
    }

    static func set(_ value: SimulatedWeather?) {
        #if DEBUG
        if let value { UserDefaults.standard.set(value.rawValue, forKey: defaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: defaultsKey) }
        #endif
    }
}

/// Offline weather for dev mode: a deterministic daily pattern seeded by the local day
/// (`fnv1a32("sim-weather|<yyyy-MM-dd>")`), so every device shows the same weather on the same
/// day and tests are stable. Sunrise 07:00, sunset 19:00 local. Never touches the network.
struct SimulatedWeatherProvider: WeatherProvider {
    var forced: SimulatedWeather? = nil

    var kind: WeatherProviderKind { .simulated }
    var needsPlace: Bool { false }

    static let sunriseHour = 7
    static let sunsetHour = 19

    func snapshot(for place: WeatherPlace?, now: Date, timeZone: TimeZone) async throws -> WeatherSnapshot {
        Self.snapshot(now: now, timeZone: timeZone, forced: forced, placeName: place?.name)
    }

    /// Pure builder (tests call this directly).
    static func snapshot(now: Date, timeZone: TimeZone, forced: SimulatedWeather? = nil,
                         placeName: String? = nil) -> WeatherSnapshot {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let hourStart = cal.dateInterval(of: .hour, for: now)?.start ?? now
        let hours = (0..<26).map { i -> WeatherSnapshot.Hour in
            let d = hourStart.addingTimeInterval(Double(i) * 3600)
            let k = simulatedKind(at: d, timeZone: timeZone, forced: forced)
            return WeatherSnapshot.Hour(date: d, kind: k, temperatureC: temperature(for: k, at: d, timeZone: timeZone))
        }
        let sun = (0..<3).compactMap { offset -> WeatherSnapshot.Sun? in
            guard let day = cal.date(byAdding: .day, value: offset, to: now),
                  let start = cal.dateInterval(of: .day, for: day)?.start else { return nil }
            let key = CollectingEngine.dayKey(day, timeZone: timeZone)
            if forced == .night {
                // Whole day dark: sunrise and sunset in the first seconds of the day (rise < set).
                return WeatherSnapshot.Sun(day: key, sunrise: start.addingTimeInterval(1),
                                           sunset: start.addingTimeInterval(2))
            }
            return WeatherSnapshot.Sun(day: key,
                                       sunrise: cal.date(bySettingHour: sunriseHour, minute: 0, second: 0, of: start),
                                       sunset: cal.date(bySettingHour: sunsetHour, minute: 0, second: 0, of: start))
        }
        let currentKind = simulatedKind(at: now, timeZone: timeZone, forced: forced)
        return WeatherSnapshot(fetchedAt: now, current: currentKind,
                               currentTemperatureC: temperature(for: currentKind, at: now, timeZone: timeZone),
                               hourly: hours, sun: sun, timeZoneId: timeZone.identifier, placeName: placeName)
    }

    /// The day's weather kind and the local hours it lasts.
    static func dayPattern(day: String, month: Int) -> (kind: WeatherKind, startHour: Int, hours: Int) {
        var rng = Mulberry32(seed: Hash.fnv1a32("sim-weather|\(day)"))
        let winter = month == 12 || month <= 2
        let summer = (6...8).contains(month)
        // Roughly 4/10 clear days; the rest pick a season-appropriate kind.
        let pool: [WeatherKind]
        if winter { pool = [.none, .none, .none, .none, .snow, .snow, .snow, .rain, .wind, .wind] }
        else if summer { pool = [.none, .none, .none, .none, .heat, .heat, .heat, .rain, .rain, .wind] }
        else { pool = [.none, .none, .none, .none, .rain, .rain, .rain, .wind, .wind, .heat] }
        let k = pool[rng.int(pool.count)]
        let start = 8 + rng.int(8)      // 08:00 ... 15:00
        let length = 3 + rng.int(6)     // 3 ... 8 hours
        return (k, start, length)
    }

    static func simulatedKind(at date: Date, timeZone: TimeZone, forced: SimulatedWeather? = nil) -> WeatherKind {
        if let forced {
            switch forced {
            case .clear, .night: return .none
            case .rain: return .rain
            case .heat: return .heat
            case .snow: return .snow
            case .wind: return .wind
            }
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let p = dayPattern(day: CollectingEngine.dayKey(date, timeZone: timeZone),
                           month: cal.component(.month, from: date))
        let h = cal.component(.hour, from: date)
        return (p.startHour..<(p.startHour + p.hours)).contains(h) ? p.kind : .none
    }

    static func temperature(for kind: WeatherKind, at date: Date, timeZone: TimeZone) -> Double {
        switch kind {
        case .heat: return 31
        case .snow: return -3
        case .rain: return 12
        case .wind: return 14
        case .none, .night: return 18
        }
    }
}
