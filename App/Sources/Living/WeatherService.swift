import Foundation
import CoreLocation
#if TWEGGS_WEATHERKIT
import WeatherKit
#endif
import BackgroundTasks
import WidgetKit
import SwiftUI

/// §1 weather. Opt-in (Settings), privacy-first:
/// - Location: approximate (`kCLLocationAccuracyReduced`), When-In-Use only, asked only when the
///   player turns "Use my location" on; coordinates are rounded to 0.1° and never stored or sent
///   to our servers. Fallback: a city typed by hand (`ManualCity`, stored on device only).
///   No permission and no city = neutral weather.
/// - Fetch: through a `WeatherProvider`, at most once per 3 h per device (app open + BGAppRefresh).
///   `AppleWeatherProvider` (WeatherKit) exists ONLY when compiled with `TWEGGS_WEATHERKIT`;
///   otherwise (dev mode, free Apple ID) `SimulatedWeatherProvider` is used and WeatherKit is
///   not even linked, so it can never be called.
/// - Cache: `weather.json` in the App Group; the widget reads only that cache.
///
/// Named `LivingWeatherService` to avoid clashing with `WeatherKit.WeatherService`.
@MainActor
final class LivingWeatherService {
    static let shared = LivingWeatherService()
    static let refreshTaskId = "com.orizolabs.mixlings.weather"

    private let cache = LivingCache.shared
    private let location = CoarseLocation()
    private var inFlight = false

    var authorizationStatus: CLAuthorizationStatus { location.status }

    func requestLocationPermission() async -> Bool {
        let s = await location.requestAuthorization()
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    /// Fetches if enabled and the cache is older than 3 h (or `force`). Returns the cache.
    @discardableResult
    func refreshIfNeeded(settings: LivingState, now: Date = .now, force: Bool = false) async -> WeatherSnapshot? {
        guard settings.weatherEnabled else {
            cache.saveWeather(nil)
            return nil
        }
        let cached = cache.loadWeather()
        if !force, let cached, !cached.needsRefresh(now: now) { return cached }
        guard !inFlight else { return cached }
        inFlight = true
        defer { inFlight = false }

        let provider = WeatherProviders.make()
        var place: WeatherPlace?
        // The simulated provider needs no place: never ask Core Location for it.
        if provider.needsPlace, settings.useLocation, let loc = await location.currentLocation() {
            let c = Self.coarse(loc)
            place = WeatherPlace(latitude: c.coordinate.latitude, longitude: c.coordinate.longitude, name: nil)
        } else if let city = settings.manualCity {
            place = WeatherPlace(latitude: city.latitude, longitude: city.longitude, name: city.name)
        }
        if provider.needsPlace, place == nil { return cached }
        do {
            let snap = try await provider.snapshot(for: place, now: now, timeZone: .current)
            cache.saveWeather(snap)
            WidgetCenter.shared.reloadAllTimelines()
            scheduleBackgroundRefresh()
            return snap
        } catch {
            #if DEBUG
            print("Weather fetch failed (\(provider.kind)): \(error)")
            #endif
            return cached
        }
    }

    /// BGAppRefresh entry point: reads settings from the save (app process only).
    func refreshInBackground() async {
        let settings = CreatureStore.shared.load().living
        await refreshIfNeeded(settings: settings)
        scheduleBackgroundRefresh()
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date().addingTimeInterval(WeatherSnapshot.refreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Looks up a city by name (Apple geocoder) and returns coarse coordinates to store locally.
    func lookUpCity(_ name: String) async -> ManualCity? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60 else { return nil }
        guard let placemark = try? await CLGeocoder().geocodeAddressString(trimmed).first,
              let loc = placemark.location else { return nil }
        let display = placemark.locality ?? placemark.name ?? trimmed
        return ManualCity(name: display, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
    }

    // MARK: Helpers

    static func coarse(_ loc: CLLocation) -> CLLocation {
        CLLocation(latitude: (loc.coordinate.latitude * 10).rounded() / 10,
                   longitude: (loc.coordinate.longitude * 10).rounded() / 10)
    }
}

extension WeatherProviders {
    /// The provider for one refresh. WeatherKit only with `TWEGGS_WEATHERKIT`; never otherwise.
    static func make() -> WeatherProvider {
        #if TWEGGS_WEATHERKIT
        return AppleWeatherProvider()
        #else
        return SimulatedWeatherProvider(forced: SimulatedWeatherOverride.current)
        #endif
    }
}

#if TWEGGS_WEATHERKIT
/// Apple WeatherKit (§1). Needs the WeatherKit capability + App Service on the App ID and the
/// `com.apple.developer.weatherkit` entitlement (commented out in project.yml in dev mode).
struct AppleWeatherProvider: WeatherProvider {
    struct MissingPlace: Error {}

    var kind: WeatherProviderKind { .apple }
    var needsPlace: Bool { true }

    func snapshot(for place: WeatherPlace?, now: Date, timeZone: TimeZone) async throws -> WeatherSnapshot {
        guard let place else { throw MissingPlace() }
        let loc = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let (current, hourly, daily) = try await WeatherService.shared.weather(
            for: loc, including: .current, .hourly, .daily)
        return Self.snapshot(current: current, hourly: Array(hourly.forecast),
                             daily: Array(daily.forecast), placeName: place.name, now: now, timeZone: timeZone)
    }

    // MARK: Mapping (WeatherKit -> cache)

    static func snapshot(current: CurrentWeather, hourly: [HourWeather], daily: [DayWeather],
                         placeName: String?, now: Date, timeZone: TimeZone = .current) -> WeatherSnapshot {
        let currentKind = WeatherClassifier.classify(
            condition: current.condition.rawValue,
            temperatureC: current.temperature.converted(to: .celsius).value,
            windKmh: current.wind.speed.converted(to: .kilometersPerHour).value,
            uvIndex: current.uvIndex.value)
        let hours = hourly
            .filter { $0.date >= now.addingTimeInterval(-3600) && $0.date < now.addingTimeInterval(26 * 3600) }
            .map { h in
                WeatherSnapshot.Hour(
                    date: h.date,
                    kind: WeatherClassifier.classify(
                        condition: h.condition.rawValue,
                        temperatureC: h.temperature.converted(to: .celsius).value,
                        windKmh: h.wind.speed.converted(to: .kilometersPerHour).value,
                        uvIndex: h.uvIndex.value),
                    temperatureC: h.temperature.converted(to: .celsius).value)
            }
        let sun = daily.prefix(3).map { d in
            WeatherSnapshot.Sun(day: CollectingEngine.dayKey(d.date.addingTimeInterval(12 * 3600), timeZone: timeZone),
                                sunrise: d.sun.sunrise, sunset: d.sun.sunset)
        }
        return WeatherSnapshot(fetchedAt: now, current: currentKind,
                               currentTemperatureC: current.temperature.converted(to: .celsius).value,
                               hourly: hours, sun: Array(sun), timeZoneId: timeZone.identifier,
                               placeName: placeName)
    }
}
#endif

/// One-shot approximate location, When-In-Use only.
@MainActor
final class CoarseLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    func requestAuthorization() async -> CLAuthorizationStatus {
        guard manager.authorizationStatus == .notDetermined, authContinuation == nil else {
            return manager.authorizationStatus
        }
        return await withCheckedContinuation { c in
            authContinuation = c
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async -> CLLocation? {
        let s = manager.authorizationStatus
        guard s == .authorizedWhenInUse || s == .authorizedAlways, locationContinuation == nil else { return nil }
        return await withCheckedContinuation { c in
            locationContinuation = c
            manager.requestLocation()
        }
    }

    private func finishLocation(_ loc: CLLocation?) {
        locationContinuation?.resume(returning: loc)
        locationContinuation = nil
    }

    private func finishAuth(_ s: CLAuthorizationStatus) {
        guard s != .notDetermined else { return }
        authContinuation?.resume(returning: s)
        authContinuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in self.finishLocation(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishLocation(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in self.finishAuth(s) }
    }
}

/// Required WeatherKit attribution (Apple Weather mark + legal link), shown in Settings and
/// wherever weather data is shown at length. In dev mode (simulated weather) it says so instead.
struct WeatherAttributionView: View {
    #if TWEGGS_WEATHERKIT
    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherAttribution?

    var body: some View {
        HStack(spacing: 10) {
            if let attribution {
                AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL
                                                     : attribution.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(verbatim: attribution.serviceName).font(Theme.caption(12))
                }
                .frame(height: 14)
                .accessibilityLabel(Text(verbatim: attribution.serviceName))
                Link("Weather data sources", destination: attribution.legalPageURL)
                    .font(Theme.caption(12))
            } else {
                Text(verbatim: "\u{F8FF} Weather").font(Theme.caption(12))
            }
        }
        .task {
            attribution = try? await WeatherService.shared.attribution
        }
    }
    #else
    var body: some View {
        Label("Simulated weather (dev mode)", systemImage: "cloud.sun")
            .font(Theme.caption(12))
            .foregroundStyle(Theme.inkSoft)
    }
    #endif
}
