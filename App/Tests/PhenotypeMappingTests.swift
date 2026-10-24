import XCTest
@testable import Mixlings

/// Expected values hand-derived from the catalog dominance table (Catalog.swift):
/// higher dominance wins, tie -> lower variant index (genome-spec §2).
final class PhenotypeMappingTests: XCTestCase {
    func testGeneOrderAndDominance() {
        let genome: [[Int]] = [
            [0, 4],   // body: round(6) vs drop(7) -> 4
            [7, 0],   // eyes: cyclops(8) vs dots(6) -> 7
            [2, 1],   // head: bunnyears(5) vs catears(5) tie -> 1
            [5, 3],   // pattern: freckles(2) vs stripes(3) -> 3
            [0, 0],   // tail: none -> 0
            [12, 15], // palette: night(2) vs ghost(9) -> 15
            [2, 1],   // aura: glow(2) vs sparkle(3) -> 1
            [8, 9],   // temper: noble(2) vs chaotic(8) -> 9
        ]
        let t = PhenotypeMapper.traits(genome: genome, creatureId: "a", paletteShift: 1)
        XCTAssertEqual(t.body, 4)
        XCTAssertEqual(t.eyes, 7)
        XCTAssertEqual(t.head, 1)
        XCTAssertEqual(t.pattern, 3)
        XCTAssertEqual(t.tail, 0)
        XCTAssertEqual(t.palette, 15)
        XCTAssertEqual(t.aura, 1)
        XCTAssertEqual(t.temper, 9)
        XCTAssertEqual(t.shift, 1)
        XCTAssertEqual(PhenotypeMapper.temperName(t), "chaotic")
    }

    func testSeedIsFNV1aOfCreatureId() {
        // fnv1a32("a") = 0xE40C292C
        XCTAssertEqual(PhenotypeMapper.seed(forCreatureId: "a"), 3_826_002_220)
        XCTAssertEqual(PhenotypeMapper.seed(forCreatureId: "s_test"), 1_221_717_971)
        XCTAssertEqual(PhenotypeMapper.seed(forCreatureId: "x"), PhenotypeMapper.seed(forCreatureId: "x"))
        XCTAssertGreaterThanOrEqual(PhenotypeMapper.seed(forCreatureId: "anything"), 0)
    }

    func testInvalidGenomeFallsBackInsteadOfCrashing() {
        let t = PhenotypeMapper.traits(genome: [[99, 99]], creatureId: "bad", paletteShift: 0)
        XCTAssertEqual(t.body, 0)
        XCTAssertEqual(t.temper, 0)
    }

    func testPhenotypeCarriesTraits() {
        let c = Creature(id: "abc", name: "A", genome: Array(repeating: [1, 1], count: 8),
                         origin: .starter, paletteShift: 1, bornAt: .now)
        let t = PhenotypeMapper.traits(for: c)
        XCTAssertEqual(t.seed, PhenotypeMapper.seed(forCreatureId: "abc"))
        XCTAssertEqual(t.palette, 1)
        XCTAssertEqual(t.shift, 1)
        // Building the MixlingsArt value must not trap.
        _ = PhenotypeMapper.phenotype(t)
    }
}
