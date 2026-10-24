// Collecting features (genome-spec §8): combo keys, generations, seasons, daily surprise.
// Pure and deterministic. Mirrors engine-ts/src/collecting.ts line by line; golden vectors
// (`collecting` in vectors.json) cover both.
//
// Design rules (founder-approved): no paid randomness and no real-money resale, ever.
// The daily surprise is free, once per local day, and has no purchase path.

public enum Collecting {
    /// Genes that are drawn (body, eyes, head, pattern, tail, palette, aura). Temper is not part of the look.
    public static let visibleGeneCount = 7

    // MARK: Combo key

    /// Stable key of what a creature LOOKS like: the 7 visible expressed variants joined by "-",
    /// e.g. "0-1-2-3-4-5-6". Palette shift (twins) and temper are deliberately excluded.
    /// Returns nil if fewer than 7 expressed genes are given.
    public static func comboKey(expressed: [Int]) -> String? {
        guard expressed.count >= visibleGeneCount else { return nil }
        return expressed.prefix(visibleGeneCount).map { String($0) }.joined(separator: "-")
    }

    public static func comboKey(genome: Genome) throws -> String {
        let e = try Genetics.express(genome)
        guard let key = comboKey(expressed: e) else { throw GenomeError("comboKey: need 7 expressed genes") }
        return key
    }

    // MARK: Generation

    /// 0 with no known parents (starters, onboarding egg), else max(parent gens) + 1.
    public static func generation(parentGenerations: [Int]) -> Int {
        guard let m = parentGenerations.max() else { return 0 }
        return m + 1
    }

    // MARK: Seasons

    public struct SeasonEntry: Codable, Equatable, Hashable, Sendable {
        public let gene: Int
        public let variant: Int

        public init(gene: Int, variant: Int) {
            self.gene = gene
            self.variant = variant
        }
    }

    public struct Season: Codable, Equatable, Sendable, Identifiable {
        /// Stable id ("s1"), also the localization key stem in the app.
        public let id: String
        /// Inclusive local-day bounds, "yyyy-MM-dd".
        public let startDay: String
        public let endDay: String
        public let entries: [SeasonEntry]

        public init(id: String, startDay: String, endDay: String, entries: [SeasonEntry]) {
            self.id = id
            self.startDay = startDay
            self.endDay = endDay
            self.entries = entries
        }
    }

    /// Season 1 "Перша весна" / "First Spring": 12 non-mutation variants,
    /// 5 common, 4 uncommon, 3 rare. TODO(content): confirm real dates before launch.
    public static let season1 = Season(
        id: "s1",
        startDay: "2026-10-01",
        endDay: "2027-05-31",
        entries: [
            SeasonEntry(gene: 2, variant: 1),  // head catears      common
            SeasonEntry(gene: 3, variant: 1),  // pattern belly     common
            SeasonEntry(gene: 5, variant: 0),  // palette mint      common
            SeasonEntry(gene: 4, variant: 1),  // tail puff         common
            SeasonEntry(gene: 1, variant: 3),  // eyes happy        common
            SeasonEntry(gene: 2, variant: 5),  // head leaf         uncommon
            SeasonEntry(gene: 3, variant: 2),  // pattern spots     uncommon
            SeasonEntry(gene: 2, variant: 3),  // head horns        uncommon
            SeasonEntry(gene: 6, variant: 1),  // aura sparkle      uncommon
            SeasonEntry(gene: 4, variant: 4),  // tail flame        rare
            SeasonEntry(gene: 1, variant: 6),  // eyes star         rare
            SeasonEntry(gene: 5, variant: 12), // palette night     rare
        ]
    )

    public static let seasons: [Season] = [season1]

    /// Per entry: true if any of the given expressed phenotypes shows that variant.
    public static func seasonProgress(_ season: Season, expressed list: [[Int]]) -> [Bool] {
        season.entries.map { e in
            list.contains { x in x.indices.contains(e.gene) && x[e.gene] == e.variant }
        }
    }

    /// `day` is "yyyy-MM-dd"; ASCII compare of fixed-width dates == chronological compare.
    public static func isSeasonActive(_ season: Season, day: String) -> Bool {
        Genetics.compareIds(day, season.startDay) >= 0 && Genetics.compareIds(day, season.endDay) <= 0
    }

    // MARK: Daily surprise

    public enum Souvenir: Equatable, Hashable, Sendable, Codable {
        case sparks(Int)
        case cosmetic(String)

        private enum CodingKeys: String, CodingKey { case kind, amount, id }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            switch kind {
            case "sparks": self = .sparks(try c.decode(Int.self, forKey: .amount))
            case "cosmetic": self = .cosmetic(try c.decode(String.self, forKey: .id))
            default:
                throw DecodingError.dataCorruptedError(forKey: .kind, in: c,
                                                       debugDescription: "unknown souvenir kind \(kind)")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .sparks(let amount):
                try c.encode("sparks", forKey: .kind)
                try c.encode(amount, forKey: .amount)
            case .cosmetic(let id):
                try c.encode("cosmetic", forKey: .kind)
                try c.encode(id, forKey: .id)
            }
        }
    }

    /// Placeholder cosmetic ids. TODO(art): real cosmetics.
    public static let surpriseCosmetics: [String] = ["flower_crown", "tiny_scarf", "star_pin", "bow_tie"]
    public static let surpriseSparksMin = 5
    public static let surpriseSparksMax = 25
    /// Out of 100: rolls below this give sparks, the rest a cosmetic.
    public static let surpriseSparksChance = 80

    /// Free daily surprise for `playerId` on local day `day` ("yyyy-MM-dd").
    /// rng = mulberry32(fnv1a32("surprise|" + playerId + "|" + day));
    /// roll = rng.int(100); roll < 80 -> sparks 5 + rng.int(21) (5...25), else cosmetic[rng.int(count)].
    public static func dailySurprise(playerId: String, day: String) -> Souvenir {
        var rng = Mulberry32(seed: Hash.fnv1a32("surprise|" + playerId + "|" + day))
        let roll = rng.int(100)
        if roll < surpriseSparksChance {
            return .sparks(surpriseSparksMin + rng.int(surpriseSparksMax - surpriseSparksMin + 1))
        }
        return .cosmetic(surpriseCosmetics[rng.int(surpriseCosmetics.count)])
    }
}
