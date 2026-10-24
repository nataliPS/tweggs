import Foundation

/// One care action done from the widget (T4). Append-only in `active.json`; the app replays
/// each event once (by `id`) into `collection.json`, so concurrent widget taps never overwrite
/// each other or the app's data.
struct CareEvent: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var creatureId: String
    var action: CreatureStore.CareAction
    var at: Date

    init(id: String = UUID().uuidString.lowercased(), creatureId: String,
         action: CreatureStore.CareAction, at: Date) {
        self.id = id
        self.creatureId = creatureId
        self.action = action
        self.at = at
    }
}

/// What the widget needs, and nothing more (T4): the active creature and its egg timer.
/// Written by the app on every save; the widget reads ONLY this file. Its App Intents (Feed /
/// Pet) APPEND a `CareEvent` to `pendingCare` (and update `creature` for display only); the
/// app merges the events idempotently and drops merged ones when it next refreshes the file.
/// v2: `pendingCare` replaces v1's in-place stat edits.
struct ActiveSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 2

    var version: Int
    /// The Home creature with stats as of `creature.lastUpdated` (pending care included).
    /// Nil before onboarding.
    var creature: Creature?
    /// When the active egg hatches (nil if it's not an egg).
    var eggHatchesAt: Date?
    /// For the widget's "surprise waiting" hint.
    var lastSurpriseDay: String?
    /// Widget care not yet merged by the app, oldest first.
    var pendingCare: [CareEvent]

    init(version: Int = ActiveSnapshot.currentVersion, creature: Creature? = nil,
         eggHatchesAt: Date? = nil, lastSurpriseDay: String? = nil, pendingCare: [CareEvent] = []) {
        self.version = version
        self.creature = creature
        self.eggHatchesAt = eggHatchesAt
        self.lastSurpriseDay = lastSurpriseDay
        self.pendingCare = pendingCare
    }

    private enum CodingKeys: String, CodingKey {
        case version, creature, eggHatchesAt, lastSurpriseDay, pendingCare
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        creature = try c.decodeIfPresent(Creature.self, forKey: .creature)
        eggHatchesAt = try c.decodeIfPresent(Date.self, forKey: .eggHatchesAt)
        lastSurpriseDay = try c.decodeIfPresent(String.self, forKey: .lastSurpriseDay)
        pendingCare = try c.decodeIfPresent([CareEvent].self, forKey: .pendingCare) ?? []
    }

    init(save: SaveData, now: Date = .now) {
        let c = save.activeCreature
        self.init(creature: c,
                  eggHatchesAt: c.flatMap { CareEngine.stage($0, at: now) == .egg ? CareEngine.hatchDate($0) : nil },
                  lastSurpriseDay: save.lastSurpriseDay)
    }
}

/// JSON persistence in the App Group container, shared by the app and the widget extension.
///
/// Two files (T4):
/// - `collection.json`: the full `SaveData`. App only.
/// - `active.json`: `ActiveSnapshot` for the widget. Refreshed by the app after every change;
///   the widget's intents only append `CareEvent`s to it (see `applyToActive`).
///
/// Atomic writes and file coordination so the app and widget intents don't clobber each other.
/// Stateless (no in-memory cache) so it is trivially `Sendable`; callers hold `SaveData`.
struct CreatureStore: Sendable {
    static let appGroupId = "group.com.orizolabs.mixlings"
    static let collectionFileName = "collection.json"
    static let activeFileName = "active.json"
    /// Single-file save used up to v0.1 (SaveData v1/v2). Moved to `collection.json` on first load.
    static let legacyFileName = "mixlings-save.json"

    static let shared = CreatureStore()

    /// Merged widget event ids kept in the save (dedupe window). Far more than can be pending.
    static let appliedCareIdLimit = 500
    /// Pending widget events kept if the app isn't opened for a long time (oldest dropped).
    static let pendingCareLimit = 200

    /// Full save (`collection.json`).
    let fileURL: URL
    /// Widget snapshot (`active.json`).
    let activeURL: URL
    /// Old single-file save, migrated on first load if `fileURL` doesn't exist yet.
    let legacyURL: URL?

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
        self.fileURL = base.appendingPathComponent(Self.collectionFileName, isDirectory: false)
        self.activeURL = base.appendingPathComponent(Self.activeFileName, isDirectory: false)
        self.legacyURL = base.appendingPathComponent(Self.legacyFileName, isDirectory: false)
    }

    /// For tests. The snapshot lives next to `fileURL` as "<name>.active.json" unless given.
    init(fileURL: URL, activeURL: URL? = nil, legacyURL: URL? = nil) {
        self.fileURL = fileURL
        self.activeURL = activeURL
            ?? fileURL.deletingPathExtension().appendingPathExtension("active.json")
        self.legacyURL = legacyURL
    }

    // MARK: Collection (app)

    /// Loads the save, or returns a fresh one (new random playerId) if none exists / it's unreadable.
    /// A fresh save is NOT written automatically; the app writes it when onboarding starts.
    /// Care done from the widget (in `active.json`) is merged in.
    func load() -> SaveData {
        migrateLegacyFileIfNeeded()
        let snapshot = loadActive()
        var result: SaveData?
        coordinate(fileURL, writing: false) { url in
            guard let data = try? Data(contentsOf: url) else { return }
            result = try? Self.decoder.decode(SaveData.self, from: data)
        }
        guard var save = result else { return SaveData() }
        if let snapshot { Self.merge(snapshot, into: &save) }
        return save
    }

    /// App launch: load, or create and PERSIST a fresh save so the random playerId is fixed
    /// from the very first run (otherwise every `load()` would mint a new playerId).
    func loadOrCreate() -> SaveData {
        update { _ in }
    }

    func save(_ data: SaveData) {
        update { $0 = data }
    }

    /// Read-modify-write under one coordinated write. Merges widget care first, then writes
    /// `collection.json` and refreshes `active.json` (dropping only the events merged here).
    /// Returns the saved value.
    @discardableResult
    func update(now: Date = .now, _ body: (inout SaveData) -> Void) -> SaveData {
        migrateLegacyFileIfNeeded()
        // Read the widget snapshot BEFORE taking the collection write lock (no nested coordination).
        let snapshot = loadActive()
        var out = SaveData()
        coordinate(fileURL, writing: true) { url in
            var current = (try? Data(contentsOf: url))
                .flatMap { try? Self.decoder.decode(SaveData.self, from: $0) } ?? SaveData()
            if let snapshot { Self.merge(snapshot, into: &current) }
            body(&current)
            write(current, to: url)
            out = current
        }
        refreshActive(from: out, now: now)
        return out
    }

    // MARK: Active snapshot (widget)

    /// Reads `active.json` only. Nil if it doesn't exist yet (not onboarded / never written).
    func loadActive() -> ActiveSnapshot? {
        var result: ActiveSnapshot?
        coordinate(activeURL, writing: false) { url in
            guard let data = try? Data(contentsOf: url) else { return }
            result = try? Self.decoder.decode(ActiveSnapshot.self, from: data)
        }
        return result
    }

    func saveActive(_ snapshot: ActiveSnapshot) {
        coordinate(activeURL, writing: true) { url in write(snapshot, to: url) }
    }

    /// App: rewrites `active.json` from `save` under ONE coordinated write of that file.
    /// Events the widget appended that `save` hasn't merged yet (e.g. a tap that landed after
    /// `update` read the snapshot) are kept, and the display creature includes them.
    func refreshActive(from save: SaveData, now: Date = .now) {
        coordinate(activeURL, writing: true) { url in
            let current = (try? Data(contentsOf: url))
                .flatMap { try? Self.decoder.decode(ActiveSnapshot.self, from: $0) }
            var snap = ActiveSnapshot(save: save, now: now)
            snap.pendingCare = Self.unmerged(current?.pendingCare ?? [], in: save)
            if var c = snap.creature {
                for e in snap.pendingCare where e.creatureId == c.id { c = Self.applying(e.action, to: c, at: e.at) }
                snap.creature = c
            }
            write(snap, to: url)
        }
    }

    /// Widget events not yet merged into `save`.
    static func unmerged(_ events: [CareEvent], in save: SaveData) -> [CareEvent] {
        let done = Set(save.appliedCareEventIds)
        return events.filter { !done.contains($0.id) }
    }

    /// Replays widget care into the save. Idempotent: each event id is applied at most once
    /// (ids are remembered in `appliedCareEventIds`). Events for creatures no longer in the save
    /// are marked merged and dropped. Only stats move; identity, genome and growth stay the app's.
    static func merge(_ snapshot: ActiveSnapshot, into save: inout SaveData) {
        let fresh = unmerged(snapshot.pendingCare, in: save)
        let legacy = snapshot.version < 2
        if legacy { mergeLegacyStats(snapshot, into: &save) }
        guard !fresh.isEmpty else { return }
        var seen = Set<String>()
        for e in fresh.sorted(by: { $0.at < $1.at }) where seen.insert(e.id).inserted {
            // v1 file: `creature` already carries every tap, so events are only marked merged.
            if !legacy, let c = save.creature(id: e.creatureId) {
                save.replace(applying(e.action, to: c, at: e.at))
            }
            save.appliedCareEventIds.append(e.id)
        }
        let overflow = save.appliedCareEventIds.count - appliedCareIdLimit
        if overflow > 0 { save.appliedCareEventIds.removeFirst(overflow) }
    }

    /// v1 `active.json` (written before the event log): the widget edited stats in place.
    /// Take them if newer, once, on the first launch after the update.
    private static func mergeLegacyStats(_ snapshot: ActiveSnapshot, into save: inout SaveData) {
        guard let w = snapshot.creature,
              let i = save.creatures.firstIndex(where: { $0.id == w.id }),
              w.lastUpdated > save.creatures[i].lastUpdated else { return }
        save.creatures[i].hunger = w.hunger
        save.creatures[i].joy = w.joy
        save.creatures[i].mood = w.mood
        save.creatures[i].lastUpdated = w.lastUpdated
    }

    // MARK: Care helpers

    enum CareAction: String, Codable, Sendable, CaseIterable {
        case feed, play, pet
    }

    static func applying(_ action: CareAction, to c: Creature, at now: Date) -> Creature {
        switch action {
        case .feed: return CareEngine.feed(c, at: now)
        case .play: return CareEngine.play(c, at: now)
        case .pet: return CareEngine.pet(c, at: now)
        }
    }

    /// App: applies a care action to the given (or active) creature and saves both files.
    @discardableResult
    func apply(_ action: CareAction, creatureId: String? = nil, at now: Date = .now) -> SaveData {
        update(now: now) { save in
            guard let id = creatureId ?? save.activeCreature?.id,
                  let c = save.creature(id: id) else { return }
            save.replace(Self.applying(action, to: c, at: now))
        }
    }

    /// Widget intents: appends a care event to `active.json` (never touches `collection.json`)
    /// and updates the snapshot creature for display. Append-only under one coordinated write.
    @discardableResult
    func applyToActive(_ action: CareAction, at now: Date = .now) -> ActiveSnapshot? {
        var out: ActiveSnapshot?
        coordinate(activeURL, writing: true) { url in
            guard let data = try? Data(contentsOf: url),
                  var snap = try? Self.decoder.decode(ActiveSnapshot.self, from: data),
                  let c = snap.creature else { return }
            // A v1 file keeps its version: the app then takes `creature`'s stats (which include
            // this tap) instead of replaying events, so nothing is applied twice.
            snap.pendingCare.append(CareEvent(creatureId: c.id, action: action, at: now))
            if snap.pendingCare.count > Self.pendingCareLimit {
                snap.pendingCare.removeFirst(snap.pendingCare.count - Self.pendingCareLimit)
            }
            snap.creature = Self.applying(action, to: c, at: now)
            write(snap, to: url)
            out = snap
        }
        return out
    }

    // MARK: Private

    private func migrateLegacyFileIfNeeded() {
        guard let legacyURL else { return }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: fileURL.path), fm.fileExists(atPath: legacyURL.path) else { return }
        // Copy (not move) first so a crash mid-way never loses the only save; then remove.
        do {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: legacyURL, to: fileURL)
            try? fm.removeItem(at: legacyURL)
        } catch {
            #if DEBUG
            print("CreatureStore legacy migration failed: \(error)")
            #endif
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(value).write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            print("CreatureStore write failed (\(url.lastPathComponent)): \(error)")
            #endif
        }
    }

    private func coordinate(_ target: URL, writing: Bool, _ body: (URL) -> Void) {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var error: NSError?
        var ran = false
        if writing {
            coordinator.coordinate(writingItemAt: target, options: [], error: &error) { ran = true; body($0) }
        } else {
            coordinator.coordinate(readingItemAt: target, options: [], error: &error) { ran = true; body($0) }
        }
        if error != nil && !ran {
            // Coordination failed (very rare); fall back to direct access.
            body(target)
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
