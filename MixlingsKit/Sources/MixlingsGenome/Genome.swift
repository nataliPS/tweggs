// Genome logic (genome-spec §2, §4, §5, §6). Mirrors engine-ts/src/genome.ts line by line.

/// 8 genes in catalog order; each gene is exactly two alleles (variant indices).
/// Arrays (not tuples) so it is Codable and matches the JSON shape `[[a,b] x 8]`.
public typealias Genome = [[Int]]

public struct Parent: Codable, Equatable, Sendable {
    public var id: String
    public var genome: Genome
    /// Player who owns this parent. Used only for paletteShift keys; defaults to `id`.
    public var owner: String?

    public init(id: String, genome: Genome, owner: String? = nil) {
        self.id = id
        self.genome = genome
        self.owner = owner
    }
}

public struct Mutation: Codable, Equatable, Hashable, Sendable {
    public var gene: Int
    public var variant: Int

    public init(gene: Int, variant: Int) {
        self.gene = gene
        self.variant = variant
    }
}

public struct AppliedMutation: Codable, Equatable, Sendable {
    public var gene: Int
    public var variant: Int
    /// Which allele slot (0 or 1) was overwritten.
    public var allele: Int

    public init(gene: Int, variant: Int, allele: Int) {
        self.gene = gene
        self.variant = variant
        self.allele = allele
    }
}

public struct BreedInput: Codable, Equatable, Sendable {
    public var parentA: Parent
    public var parentB: Parent
    public var nonce: String
    public var unlockedMutations: [Mutation]

    public init(parentA: Parent, parentB: Parent, nonce: String, unlockedMutations: [Mutation]) {
        self.parentA = parentA
        self.parentB = parentB
        self.nonce = nonce
        self.unlockedMutations = unlockedMutations
    }
}

public struct BreedResult: Codable, Equatable, Sendable {
    public var id: String
    public var genome: Genome
    /// Seed as 8-char hex (debug / server logs).
    public var seedHex: String
    public var mutation: AppliedMutation?
    /// owner -> shift (0 for owner of ordered parentA, 1 for owner of parentB).
    public var paletteShift: [String: Int]
}

public enum RarityTier: String, Codable, Equatable, Sendable {
    case common, uncommon, rare, legendary
}

public struct RarityResult: Codable, Equatable, Sendable {
    public var score: Int
    public var tier: RarityTier

    public init(score: Int, tier: RarityTier) {
        self.score = score
        self.tier = tier
    }
}

public struct GenomeError: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "GenomeError: \(message)" }
}

public enum Genetics {
    public static let mutationChance: Double = 0.10

    // MARK: - Helpers

    /// Byte-wise (UTF-8) lexicographic compare. Returns <0, 0, >0.
    /// NOTE: Swift's `String <` / `==` use Unicode canonical ordering/equivalence,
    /// which differs from JS; always compare ids through this function.
    public static func compareIds(_ a: String, _ b: String) -> Int {
        let x: [UInt8] = Array(a.utf8)
        let y: [UInt8] = Array(b.utf8)
        let n = min(x.count, y.count)
        var i = 0
        while i < n {
            if x[i] != y[i] { return Int(x[i]) - Int(y[i]) }
            i += 1
        }
        return x.count - y.count
    }

    public static func validateGenome(_ genome: Genome) throws {
        guard genome.count == Catalog.geneCount else {
            throw GenomeError("genome must have \(Catalog.geneCount) genes")
        }
        for g in 0..<Catalog.geneCount {
            let pair = genome[g]
            guard pair.count == 2 else { throw GenomeError("gene \(g) must have 2 alleles") }
            let count = Catalog.genes[g].variants.count
            for v in pair where v < 0 || v >= count {
                throw GenomeError("gene \(g) allele \(v) out of range 0..\(count - 1)")
            }
        }
    }

    static func validateMutation(_ m: Mutation) throws {
        guard m.gene >= 0 && m.gene < Catalog.geneCount else {
            throw GenomeError("mutation gene \(m.gene) out of range")
        }
        let count = Catalog.genes[m.gene].variants.count
        guard m.variant >= 0 && m.variant < count else {
            throw GenomeError("mutation variant \(m.variant) out of range for gene \(m.gene)")
        }
    }

    // MARK: - Expression (§2)

    /// Expressed variant of one gene: higher dominance wins, tie -> lower index.
    /// Precondition: `a`, `b` are valid indices for `gene` (call validateGenome first).
    public static func expressGene(_ gene: Int, _ a: Int, _ b: Int) -> Int {
        let variants = Catalog.genes[gene].variants
        let da = variants[a].dominance
        let db = variants[b].dominance
        if da > db { return a }
        if db > da { return b }
        return a < b ? a : b
    }

    /// Phenotype: one expressed variant index per gene.
    public static func express(_ genome: Genome) throws -> [Int] {
        try validateGenome(genome)
        var out: [Int] = []
        out.reserveCapacity(Catalog.geneCount)
        for g in 0..<Catalog.geneCount {
            out.append(expressGene(g, genome[g][0], genome[g][1]))
        }
        return out
    }

    // MARK: - Rarity (§5)

    public static func tier(forScore score: Int) -> RarityTier {
        // G1 (retro 2026-10-24): common <=1, uncommon 2...3, rare 4...6, legendary >=7.
        if score <= 1 { return .common }
        if score <= 3 { return .uncommon }
        if score <= 6 { return .rare }
        return .legendary
    }

    public static func rarity(_ genome: Genome) throws -> RarityResult {
        let expressed = try express(genome)
        var score = 0
        for g in 0..<Catalog.geneCount {
            score += Catalog.genes[g].variants[expressed[g]].rarity
        }
        return RarityResult(score: score, tier: tier(forScore: score))
    }

    // MARK: - Breeding (§4)

    /// Breeding seed. Parent ids must already be ordered.
    public static func breedSeed(_ idA: String, _ idB: String, _ nonce: String) -> UInt32 {
        return Hash.fnv1a32(idA + "|" + idB + "|" + nonce)
    }

    /// Child id (§4.6).
    public static func childId(seed: UInt32) -> String {
        return "c_" + Hash.hex8(Hash.fnv1a32(Hash.hex8(seed) + "|child"))
    }

    /// Sort by gene, then variant (spec says input is pre-sorted; we enforce it).
    public static func sortMutations(_ list: [Mutation]) -> [Mutation] {
        return list.sorted { x, y in
            x.gene != y.gene ? x.gene < y.gene : x.variant < y.variant
        }
    }

    public static func breed(_ input: BreedInput) throws -> BreedResult {
        var pa = input.parentA
        var pb = input.parentB
        try validateGenome(pa.genome)
        try validateGenome(pb.genome)
        let cmp = compareIds(pa.id, pb.id)
        if cmp == 0 { throw GenomeError("cannot breed a creature with itself") }
        // 1. order parents
        if cmp > 0 {
            let t = pa
            pa = pb
            pb = t
        }
        let mutations = sortMutations(input.unlockedMutations)
        for m in mutations { try validateMutation(m) }

        // 2. seed
        let seed = breedSeed(pa.id, pb.id, input.nonce)
        var rng = Mulberry32(seed: seed)

        // 3. inheritance
        var genome: Genome = []
        genome.reserveCapacity(Catalog.geneCount)
        for g in 0..<Catalog.geneCount {
            let fromA = pa.genome[g][rng.int(2)]
            let fromB = pb.genome[g][rng.int(2)]
            genome.append([fromA, fromB])
        }

        // 4. mutation (roll is always drawn)
        var mutation: AppliedMutation? = nil
        let roll = rng.float()
        if !mutations.isEmpty && roll < mutationChance {
            let m = mutations[rng.int(mutations.count)]
            let allele = rng.int(2)
            genome[m.gene][allele] = m.variant
            mutation = AppliedMutation(gene: m.gene, variant: m.variant, allele: allele)
        }

        // 5. palette shift (first assignment wins if both parents share an owner)
        let ownerA = pa.owner ?? pa.id
        let ownerB = pb.owner ?? pb.id
        var paletteShift: [String: Int] = [ownerA: 0]
        if !ownerB.utf8.elementsEqual(ownerA.utf8) && paletteShift[ownerB] == nil {
            paletteShift[ownerB] = 1
        }

        // 6. id
        return BreedResult(
            id: childId(seed: seed),
            genome: genome,
            seedHex: Hash.hex8(seed),
            mutation: mutation,
            paletteShift: paletteShift
        )
    }

    // MARK: - Starters (§6)

    /// Starter creature. `slot` is a non-negative integer, formatted in decimal.
    public static func starter(playerId: String, slot: Int) throws -> Genome {
        guard slot >= 0 else { throw GenomeError("slot must be a non-negative integer") }
        var rng = Mulberry32(seed: Hash.fnv1a32("starter|" + playerId + "|" + String(slot)))
        var genome: Genome = []
        genome.reserveCapacity(Catalog.geneCount)
        for g in 0..<Catalog.geneCount {
            var pool: [Int] = []
            for (i, v) in Catalog.genes[g].variants.enumerated() where !v.mutationOnly {
                pool.append(i)
            }
            let a = pool[rng.int(pool.count)]
            let b = pool[rng.int(pool.count)]
            genome.append([a, b])
        }
        return genome
    }
}
