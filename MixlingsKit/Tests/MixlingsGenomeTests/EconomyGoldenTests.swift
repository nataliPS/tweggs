import Foundation
import XCTest
@testable import MixlingsGenome

/// Replays the `economy` section of engine-ts/golden/vectors.json (genome-spec §9).
final class EconomyGoldenTests: XCTestCase {
    private struct File: Decodable {
        struct Constants: Decodable {
            let HATCH_RUSH_COST: Int
            let HATCH_RUSH_DAILY_MAX: Int
            let GENE_HINT_COST: Int
            let SHOP_PRICE_MIN: Int
            let SHOP_PRICE_MAX: Int
            let PITY_THRESHOLD: Int
            let GEN_BADGES: [Int]
            let FREE_SLOTS: Int
            let CLUB_SLOTS: Int
        }
        struct Pairing: Decodable {
            let a: Int
            let b: Int
            let gene: Int
            let variant: Int
            let canProduce: Bool
        }
        struct Carrier: Decodable {
            let entry: Collecting.SeasonEntry
            let indices: [Int]
        }
        struct Badge: Decodable {
            let generation: Int
            let badges: [Int]
        }
        struct Section: Decodable {
            let constants: Constants
            let pairings: [Pairing]
            let carriers: [Carrier]
            let badges: [Badge]
        }
        let economyGenomes: [Genome]
        let economy: Section
    }

    private func load() throws -> File {
        guard let url = Bundle.module.url(forResource: "vectors", withExtension: "json") else {
            throw GenomeError("vectors.json missing from test bundle; run `npm run golden` in engine-ts")
        }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }

    func testConstantsMatchTS() throws {
        let c = try load().economy.constants
        XCTAssertEqual(Economy.hatchRushCost, c.HATCH_RUSH_COST)
        XCTAssertEqual(Economy.hatchRushDailyMax, c.HATCH_RUSH_DAILY_MAX)
        XCTAssertEqual(Economy.geneHintCost, c.GENE_HINT_COST)
        XCTAssertEqual(Economy.shopPriceMin, c.SHOP_PRICE_MIN)
        XCTAssertEqual(Economy.shopPriceMax, c.SHOP_PRICE_MAX)
        XCTAssertEqual(Economy.pityThreshold, c.PITY_THRESHOLD)
        XCTAssertEqual(Economy.genBadgeLevels, c.GEN_BADGES)
        XCTAssertEqual(Economy.freeSlots, c.FREE_SLOTS)
        XCTAssertEqual(Economy.clubSlots, c.CLUB_SLOTS)
    }

    func testPairings() throws {
        let f = try load()
        XCTAssertFalse(f.economy.pairings.isEmpty)
        for p in f.economy.pairings {
            XCTAssertEqual(Economy.pairingCanProduce(f.economyGenomes[p.a], f.economyGenomes[p.b],
                                                     gene: p.gene, variant: p.variant),
                           p.canProduce, "\(p.a)x\(p.b) \(p.gene):\(p.variant)")
        }
    }

    func testCarriers() throws {
        let f = try load()
        for c in f.economy.carriers {
            XCTAssertEqual(Economy.carrierHint(f.economyGenomes, entry: c.entry), c.indices)
        }
    }

    func testBadges() throws {
        for b in try load().economy.badges {
            XCTAssertEqual(Economy.genBadges(generation: b.generation), b.badges)
        }
        XCTAssertFalse(Economy.pityHintActive(breedsWithoutNewEntry: 14))
        XCTAssertTrue(Economy.pityHintActive(breedsWithoutNewEntry: 15))
    }
}
