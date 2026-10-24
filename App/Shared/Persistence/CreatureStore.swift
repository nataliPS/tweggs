import Foundation

/// JSON persistence in the App Group container, shared by the app and the widget extension.
///
/// Deliberately simple and widget-safe: a single small JSON file, atomic writes, and a
/// file coordinator so the app and the widget's App Intents don't clobber each other.
/// Stateless (no in-memory cache) so it is trivially `Sendable`; callers hold `SaveData`.
struct CreatureStore: Sendable {
    static let appGroupId = "group.com.orizolabs.mixlings"
    static let fileName = "mixlings-save.json"

    static let shared = CreatureStore()

    let fileURL: URL

    /// Default: App Group container. Falls back to Application Support if the App Group
    /// entitlement is missing (e.g. unsigned simulator builds), so the app still runs.
    init() {
        let fm = FileManager.default
        let base: URL
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupId) {
            base = group
        } else {
            // App and widget would silently use different files here — surface it in DEBUG.
            assertionFailure("App Group \(Self.appGroupId) unavailable; check entitlements")
            base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
                ?? fm.temporaryDirectory
        }
        self.fileURL = base.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// For tests.
    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: Load / save

    /// Loads the save, or returns a fresh one (new random playerId) if none exists / it's unreadable.
    /// A fresh save is NOT written automatically; the app writes it when onboarding starts.
    func load() -> SaveData {
        var result: SaveData?
        coordinate(writing: false) { url in
            guard let data = try? Data(contentsOf: url) else { return }
            result = try? Self.decoder.decode(SaveData.self, from: data)
        }
        return result ?? SaveData()
    }

    /// App launch: load, or create and PERSIST a fresh save so the random playerId is fixed
    /// from the very first run (otherwise every `load()` would mint a new playerId).
    func loadOrCreate() -> SaveData {
        update { _ in }
    }

    func save(_ data: SaveData) {
        coordinate(writing: true) { url in
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let bytes = try Self.encoder.encode(data)
                try bytes.write(to: url, options: [.atomic])
            } catch {
                #if DEBUG
                print("CreatureStore save failed: \(error)")
                #endif
            }
        }
    }

    /// Read-modify-write under one coordinated write. Returns the saved value.
    @discardableResult
    func update(_ body: (inout SaveData) -> Void) -> SaveData {
        var out = SaveData()
        coordinate(writing: true) { url in
            var current = (try? Data(contentsOf: url))
                .flatMap { try? Self.decoder.decode(SaveData.self, from: $0) } ?? SaveData()
            body(&current)
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Self.encoder.encode(current).write(to: url, options: [.atomic])
            } catch {
                #if DEBUG
                print("CreatureStore update failed: \(error)")
                #endif
            }
            out = current
        }
        return out
    }

    // MARK: Care helpers (used by both app and widget intents)

    enum CareAction: String, Codable, Sendable, CaseIterable {
        case feed, play, pet
    }

    /// Applies a care action to the given (or active) creature and saves.
    @discardableResult
    func apply(_ action: CareAction, creatureId: String? = nil, at now: Date = .now) -> SaveData {
        update { save in
            guard let id = creatureId ?? save.activeCreature?.id,
                  let c = save.creature(id: id) else { return }
            let updated: Creature
            switch action {
            case .feed: updated = CareEngine.feed(c, at: now)
            case .play: updated = CareEngine.play(c, at: now)
            case .pet: updated = CareEngine.pet(c, at: now)
            }
            save.replace(updated)
        }
    }

    // MARK: Private

    private func coordinate(writing: Bool, _ body: (URL) -> Void) {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var error: NSError?
        if writing {
            coordinator.coordinate(writingItemAt: fileURL, options: [], error: &error) { body($0) }
        } else {
            coordinator.coordinate(readingItemAt: fileURL, options: [], error: &error) { body($0) }
        }
        if error != nil {
            // Coordination failed (very rare); fall back to direct access.
            body(fileURL)
        }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .deferredToDate // exact Double round-trip
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        return d
    }
}
