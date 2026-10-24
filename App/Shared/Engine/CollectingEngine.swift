import Foundation
import MixlingsGenome

/// App-side collecting rules on top of `MixlingsGenome.Collecting` (genome-spec §8).
/// Pure: every function takes `now` / `timeZone` explicitly so app, widget and tests agree.
///
/// Founder rules: no paid randomness, no real-money resale, ever. The daily surprise is free,
/// once per local day, and there is deliberately no way to buy or re-roll it.
enum CollectingEngine {
    // MARK: Local day

    /// Local calendar day as "yyyy-MM-dd" (Gregorian, zero-padded, ASCII digits).
    static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Start of the next local day (for "come back in ..." countdowns).
    static func nextDayStart(after date: Date, timeZone: TimeZone = .current) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(CareEngine.day)
    }

    // MARK: Daily surprise

    static func canOpenSurprise(lastSurpriseDay: String?, now: Date, timeZone: TimeZone = .current) -> Bool {
        lastSurpriseDay != dayKey(now, timeZone: timeZone)
    }

    static func canOpenSurprise(_ save: SaveData, now: Date, timeZone: TimeZone = .current) -> Bool {
        canOpenSurprise(lastSurpriseDay: save.lastSurpriseDay, now: now, timeZone: timeZone)
    }

    /// Today's souvenir (same value all day, whether opened or not).
    static func surprise(for save: SaveData, now: Date, timeZone: TimeZone = .current) -> Collecting.Souvenir {
        Collecting.dailySurprise(playerId: save.playerId, day: dayKey(now, timeZone: timeZone))
    }

    /// Opens today's surprise and applies the reward. Returns nil if already opened today.
    @discardableResult
    static func openSurprise(_ save: inout SaveData, now: Date, timeZone: TimeZone = .current) -> Collecting.Souvenir? {
        guard canOpenSurprise(save, now: now, timeZone: timeZone) else { return nil }
        let souvenir = surprise(for: save, now: now, timeZone: timeZone)
        switch souvenir {
        case .sparks(let amount): save.sparks += amount
        case .cosmetic(let id): save.cosmetics.append(id)
        }
        save.lastSurpriseDay = dayKey(now, timeZone: timeZone)
        return souvenir
    }

    // MARK: Generation

    /// 0 for no parents, else max(parent generations) + 1.
    static func generation(parents: [Creature]) -> Int {
        Collecting.generation(parentGenerations: parents.map(\.generation))
    }

    /// Stamps lineage on a freshly bred child.
    static func withLineage(_ child: Creature, parents: [Creature]) -> Creature {
        var c = child
        c.generation = generation(parents: parents)
        c.parentIds = parents.map(\.id)
        return c
    }

    // MARK: Seasons

    static func expressed(_ creatures: [Creature]) -> [[Int]] {
        creatures.compactMap { try? Genetics.express($0.genome) }
    }

    static func seasonProgress(_ season: Collecting.Season, creatures: [Creature]) -> [Bool] {
        Collecting.seasonProgress(season, expressed: expressed(creatures))
    }

    static func foundCount(_ season: Collecting.Season, creatures: [Creature]) -> Int {
        seasonProgress(season, creatures: creatures).filter { $0 }.count
    }

    static func isComplete(_ season: Collecting.Season, creatures: [Creature]) -> Bool {
        !season.entries.isEmpty && foundCount(season, creatures: creatures) == season.entries.count
    }

    /// First owned creature expressing a season entry (shown in the album cell).
    static func owner(of entry: Collecting.SeasonEntry, in creatures: [Creature]) -> Creature? {
        creatures.first { c in
            guard let e = try? Genetics.express(c.genome), e.indices.contains(entry.gene) else { return false }
            return e[entry.gene] == entry.variant
        }
    }

    /// The season to show now: the active one, else the latest that has started, else the first.
    static func currentSeason(now: Date, timeZone: TimeZone = .current) -> Collecting.Season? {
        let day = dayKey(now, timeZone: timeZone)
        if let s = Collecting.seasons.first(where: { Collecting.isSeasonActive($0, day: day) }) { return s }
        return Collecting.seasons.last(where: { Genetics.compareIds($0.startDay, day) <= 0 })
            ?? Collecting.seasons.first
    }

    /// Adds a badge for every active season whose album is complete. Badges are never removed.
    static func awardSeasonBadges(_ save: inout SaveData, now: Date, timeZone: TimeZone = .current) {
        let day = dayKey(now, timeZone: timeZone)
        for season in Collecting.seasons
        where Collecting.isSeasonActive(season, day: day)
            && !save.seasonBadges.contains(season.id)
            && isComplete(season, creatures: save.creatures) {
            save.seasonBadges.append(season.id)
        }
    }

    /// Whole days left in a season (inclusive end day), or nil if it has ended / can't be parsed.
    static func daysLeft(_ season: Collecting.Season, now: Date, timeZone: TimeZone = .current) -> Int? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let parts = season.endDay.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let end = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let today = cal.startOfDay(for: now)
        guard let d = cal.dateComponents([.day], from: today, to: end).day, d >= 0 else { return nil }
        return d
    }

    /// Sample creature that shows exactly one season variant (album silhouettes).
    /// Homozygous for the entry, all other genes variant 0.
    static func sampleCreature(for entry: Collecting.SeasonEntry) -> Creature {
        var genome: Genome = Array(repeating: [0, 0], count: Catalog.geneCount)
        if genome.indices.contains(entry.gene) { genome[entry.gene] = [entry.variant, entry.variant] }
        return Creature(id: "season-\(entry.gene)-\(entry.variant)", name: "?", genome: genome,
                        origin: .starter, bornAt: Date(timeIntervalSince1970: 0),
                        hatchedAt: Date(timeIntervalSince1970: 0))
    }

    // MARK: Encyclopedia

    /// Expressed traits for a discovered look key ("0-1-2-3-4-5-6"); nil if malformed.
    static func traits(forComboKey key: String, seedId: String) -> ExpressedTraits? {
        let v = key.split(separator: "-").compactMap { Int($0) }
        guard v.count == Collecting.visibleGeneCount else { return nil }
        for (g, x) in v.enumerated() where x < 0 || x >= Catalog.genes[g].variants.count { return nil }
        return ExpressedTraits(body: v[0], eyes: v[1], head: v[2], pattern: v[3], tail: v[4],
                               palette: v[5], aura: v[6], temper: 0, shift: 0,
                               seed: PhenotypeMapper.seed(forCreatureId: seedId))
    }

    // MARK: Card

    /// "1 287" style grouping with no-break spaces (card serial "№ 1 287").
    static func groupedSerial(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append("\u{00A0}") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }
}

/// Localized names for catalog variants, seasons and cosmetics.
/// Keys are manual entries in Localizable.xcstrings ("variant.<gene>.<name>", "cosmetic.<id>");
/// a missing key falls back to the catalog name.
enum CollectingNames {
    static func variant(gene: Int, variant: Int) -> String {
        guard Catalog.genes.indices.contains(gene),
              Catalog.genes[gene].variants.indices.contains(variant) else { return "?" }
        let g = Catalog.genes[gene]
        let name = g.variants[variant].name
        return Bundle.main.localizedString(forKey: "variant.\(g.key).\(name)", value: name.capitalized, table: nil)
    }

    static func cosmetic(_ id: String) -> String {
        Bundle.main.localizedString(forKey: "cosmetic.\(id)",
                                    value: id.replacingOccurrences(of: "_", with: " ").capitalized,
                                    table: nil)
    }

    static func season(_ season: Collecting.Season) -> String {
        Bundle.main.localizedString(forKey: "season.\(season.id).name", value: season.id, table: nil)
    }
}
