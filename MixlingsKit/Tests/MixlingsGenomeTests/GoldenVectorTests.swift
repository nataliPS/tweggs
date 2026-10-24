import Foundation
import XCTest
@testable import MixlingsGenome

// Decodable mirror of engine-ts/golden/vectors.json.
struct GoldenFile: Decodable {
    struct CatalogGene: Decodable {
        let index: Int
        let key: String
        let variants: [VariantDef]
    }
    struct HashCase: Decodable {
        let input: String
        let value: UInt32
        let hex: String
    }
    struct RngCase: Decodable {
        let seed: UInt32
        let next: [UInt32]
        let int7: [Int]
        let float: [Double]
    }
    struct BreedExpected: Decodable {
        let id: String
        let seedHex: String
        let genome: Genome
        let expressed: [Int]
        let rarity: RarityResult
        let mutation: AppliedMutation?
        let paletteShift: [String: Int]
    }
    struct BreedCase: Decodable {
        let name: String
        let input: BreedInput
        let expected: BreedExpected
    }
    struct StarterInput: Decodable {
        let playerId: String
        let slot: Int
    }
    struct StarterExpected: Decodable {
        let genome: Genome
        let expressed: [Int]
        let rarity: RarityResult
    }
    struct StarterCase: Decodable {
        let name: String
        let input: StarterInput
        let expected: StarterExpected
    }

    let specVersion: String
    let catalog: [CatalogGene]
    let hashes: [HashCase]
    let rng: [RngCase]
    let breeding: [BreedCase]
    let starters: [StarterCase]
}

final class GoldenVectorTests: XCTestCase {
    private static func loadGolden() throws -> GoldenFile {
        guard let url = Bundle.module.url(forResource: "vectors", withExtension: "json") else {
            throw GenomeError("vectors.json missing from test bundle; run `npm run golden` in engine-ts")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GoldenFile.self, from: data)
    }

    private var golden: GoldenFile!

    override func setUpWithError() throws {
        golden = try Self.loadGolden()
    }

    func testSpecVersion() {
        XCTAssertEqual(golden.specVersion, "0.1")
    }

    func testCatalogMatchesGolden() {
        XCTAssertEqual(Catalog.geneCount, golden.catalog.count)
        XCTAssertEqual(Catalog.geneKeys, golden.catalog.map { $0.key })
        for gene in golden.catalog {
            XCTAssertEqual(Catalog.genes[gene.index].key, gene.key)
            XCTAssertEqual(Catalog.genes[gene.index].variants, gene.variants, "catalog drift in \(gene.key); regenerate Catalog.swift")
        }
        XCTAssertEqual(Catalog.genes.map { $0.variants.count }, [6, 8, 8, 6, 6, 16, 4, 10])
    }

    func testKnownHashes() {
        XCTAssertEqual(Hash.fnv1a32(""), 0x811C_9DC5)
        XCTAssertEqual(Hash.fnv1a32("a"), 0xE40C_292C)
        XCTAssertEqual(Hash.fnv1a32("foobar"), 0xBF9C_F968)
        XCTAssertEqual(Hash.hex8(0), "00000000")
        XCTAssertEqual(Hash.hex8(0xABC), "00000abc")
    }

    func testGoldenHashes() {
        XCTAssertFalse(golden.hashes.isEmpty)
        for h in golden.hashes {
            XCTAssertEqual(Hash.fnv1a32(h.input), h.value, "hash of \(h.input)")
            XCTAssertEqual(Hash.hex8(Hash.fnv1a32(h.input)), h.hex, "hex of \(h.input)")
        }
    }

    func testGoldenRng() {
        XCTAssertEqual(golden.rng.count, 3)
        for c in golden.rng {
            var r = Mulberry32(seed: c.seed)
            var got: [UInt32] = []
            for _ in 0..<c.next.count { got.append(r.next()) }
            XCTAssertEqual(got, c.next, "next() seed \(c.seed)")

            var r2 = Mulberry32(seed: c.seed)
            var ints: [Int] = []
            for _ in 0..<c.int7.count { ints.append(r2.int(7)) }
            XCTAssertEqual(ints, c.int7, "int(7) seed \(c.seed)")

            var r3 = Mulberry32(seed: c.seed)
            for (i, expected) in c.float.enumerated() {
                let f = r3.float()
                // Exact by construction (UInt32 / 2^32 is exact in Double); also compare to JSON.
                XCTAssertEqual(f, Double(c.next[i]) / 4_294_967_296.0)
                XCTAssertEqual(f, expected, accuracy: 1e-15, "float() seed \(c.seed) #\(i)")
            }
        }
    }

    func testGoldenBreeding() throws {
        XCTAssertEqual(golden.breeding.count, 50)
        var mutated = 0
        for c in golden.breeding {
            let r = try Genetics.breed(c.input)
            XCTAssertEqual(r.id, c.expected.id, c.name)
            XCTAssertEqual(r.seedHex, c.expected.seedHex, c.name)
            XCTAssertEqual(r.genome, c.expected.genome, c.name)
            XCTAssertEqual(r.mutation, c.expected.mutation, c.name)
            XCTAssertEqual(r.paletteShift, c.expected.paletteShift, c.name)
            XCTAssertEqual(try Genetics.express(r.genome), c.expected.expressed, c.name)
            XCTAssertEqual(try Genetics.rarity(r.genome), c.expected.rarity, c.name)
            if r.mutation != nil { mutated += 1 }

            // Symmetry: swapping parents yields the identical child.
            let swapped = BreedInput(
                parentA: c.input.parentB,
                parentB: c.input.parentA,
                nonce: c.input.nonce,
                unlockedMutations: c.input.unlockedMutations
            )
            XCTAssertEqual(try Genetics.breed(swapped), r, "\(c.name) symmetry")

            if c.input.unlockedMutations.isEmpty {
                XCTAssertNil(r.mutation, "\(c.name) mutated without unlocks")
            }
        }
        XCTAssertGreaterThan(mutated, 0, "golden set should exercise mutation")
    }

    func testGoldenStarters() throws {
        XCTAssertEqual(golden.starters.count, 20)
        for c in golden.starters {
            let g = try Genetics.starter(playerId: c.input.playerId, slot: c.input.slot)
            XCTAssertEqual(g, c.expected.genome, c.name)
            XCTAssertEqual(try Genetics.express(g), c.expected.expressed, c.name)
            XCTAssertEqual(try Genetics.rarity(g), c.expected.rarity, c.name)
            for (gi, pair) in g.enumerated() {
                for v in pair {
                    XCTAssertFalse(Catalog.genes[gi].variants[v].mutationOnly, "\(c.name) has mutationOnly")
                }
            }
        }
    }

    func testExpressionRules() {
        // body: round(6, idx 0) vs bean(5, idx 1) -> round (0), regardless of order
        XCTAssertEqual(Genetics.expressGene(0, 0, 1), 0)
        XCTAssertEqual(Genetics.expressGene(0, 1, 0), 0)
        // palette: mint(5) vs bubblegum(5) tie -> lower index
        XCTAssertEqual(Genetics.expressGene(5, 1, 0), 0)
        XCTAssertEqual(Genetics.expressGene(5, 0, 1), 0)
        // G2: palette night(4, idx 12) beats lime(3, idx 6)
        XCTAssertEqual(Genetics.expressGene(5, 12, 6), 12)
        // night(4) beats a dominance-2 variant: tangerine(2, idx 13)
        XCTAssertEqual(Genetics.expressGene(5, 13, 12), 12)
        // G3 (revised): mutation-only variants have dominance 7; mutation chance lowered to 10%
        for gene in Catalog.genes {
            for v in gene.variants where v.mutationOnly { XCTAssertEqual(v.dominance, 7, v.name) }
        }
    }

    func testRarityTiers() {
        // G1: common <=1, uncommon 2...3, rare 4...6, legendary >=7
        XCTAssertEqual(Genetics.tier(forScore: 1), .common)
        XCTAssertEqual(Genetics.tier(forScore: 2), .uncommon)
        XCTAssertEqual(Genetics.tier(forScore: 3), .uncommon)
        XCTAssertEqual(Genetics.tier(forScore: 4), .rare)
        XCTAssertEqual(Genetics.tier(forScore: 6), .rare)
        XCTAssertEqual(Genetics.tier(forScore: 7), .legendary)
    }

    func testValidation() {
        XCTAssertThrowsError(try Genetics.express([[0, 0]]))
        let bad: Genome = Array(repeating: [0, 99], count: 8)
        XCTAssertThrowsError(try Genetics.express(bad))
        let ok: Genome = Array(repeating: [0, 0], count: 8)
        XCTAssertThrowsError(try Genetics.breed(BreedInput(
            parentA: Parent(id: "x", genome: ok),
            parentB: Parent(id: "x", genome: ok),
            nonce: "",
            unlockedMutations: []
        )))
    }

    func testCompareIdsIsUTF8ByteOrder() {
        XCTAssertLessThan(Genetics.compareIds("a", "b"), 0)
        XCTAssertGreaterThan(Genetics.compareIds("ab", "a"), 0)
        XCTAssertLessThan(Genetics.compareIds("Z", "a"), 0)
        XCTAssertLessThan(Genetics.compareIds("\u{FF5E}", "\u{1F600}"), 0)
    }
}
