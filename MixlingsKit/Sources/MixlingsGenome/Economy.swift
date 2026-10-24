// Economy constants and pairing-guidance helpers (genome-spec §9; retro 2026-10-24 G6/G7/G8).
// Pure and deterministic. Mirrors engine-ts/src/economy.ts line by line.
//
// Design rules (founder-approved): sparks are earned only (never sold), no paid randomness.
// Every sink below buys certainty or cosmetics, never a re-roll.

public enum Economy {
    /// G6: hatch-rush skips 1 day of growth for this many sparks.
    public static let hatchRushCost = 30
    /// G6: max hatch-rushes per player per local day.
    public static let hatchRushDailyMax = 1
    /// G6: gene hint (which of your pairings can produce a missing season entry).
    public static let geneHintCost = 20
    /// G6: cosmetic shop item price range in sparks, inclusive.
    public static let shopPriceMin = 100
    public static let shopPriceMax = 300
    public static var shopPriceRange: ClosedRange<Int> { shopPriceMin...shopPriceMax }
    /// G7: breeds in a row without a new season entry before previews highlight carrier parents.
    public static let pityThreshold = 15
    /// G8: generation ladder badges.
    public static let genBadgeLevels: [Int] = [5, 10]  // TS: GEN_BADGES
    /// Collection slots: free players / club members.
    public static let freeSlots = 8
    public static let clubSlots = 30

    /// True if some child of `a` x `b` (one allele from each parent, mutation ignored)
    /// would EXPRESS `variant` at `gene`. Genomes are assumed valid.
    public static func pairingCanProduce(_ a: Genome, _ b: Genome, gene: Int, variant: Int) -> Bool {
        for x in a[gene] {
            for y in b[gene] where Genetics.expressGene(gene, x, y) == variant {
                return true
            }
        }
        return false
    }

    /// Indices (ascending) of creatures in `collection` that carry the entry's allele in either copy.
    public static func carrierHint(_ collection: [Genome], entry: Collecting.SeasonEntry) -> [Int] {
        collection.indices.filter { i in
            collection[i][entry.gene][0] == entry.variant || collection[i][entry.gene][1] == entry.variant
        }
    }

    /// G7: whether the pity hint is active after `breedsWithoutNewEntry` consecutive breeds.
    public static func pityHintActive(breedsWithoutNewEntry: Int) -> Bool {
        breedsWithoutNewEntry >= pityThreshold
    }

    /// G8: badges (generation thresholds) earned by a creature of `generation`, ascending.
    public static func genBadges(generation: Int) -> [Int] {
        genBadgeLevels.filter { generation >= $0 }
    }
}
