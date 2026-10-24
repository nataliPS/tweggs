import Foundation
import XCTest
@testable import MixlingsGenome

/// Replays the `collecting` section of engine-ts/golden/vectors.json.
final class CollectingGoldenTests: XCTestCase {
    private struct File: Decodable {
        struct ComboCase: Decodable {
            let expressed: [Int]
            let key: String
        }
        struct SurpriseCase: Decodable {
            let playerId: String
            let day: String
            let souvenir: Collecting.Souvenir
        }
        struct Section: Decodable {
            let comboKeys: [ComboCase]
            let surprises: [SurpriseCase]
            let seasons: [Collecting.Season]
        }
        let collecting: Section
    }

    private func load() throws -> File.Section {
        guard let url = Bundle.module.url(forResource: "vectors", withExtension: "json") else {
            throw GenomeError("vectors.json missing from test bundle; run `npm run golden` in engine-ts")
        }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).collecting
    }

    func testComboKeys() throws {
        let s = try load()
        XCTAssertFalse(s.comboKeys.isEmpty)
        for c in s.comboKeys {
            XCTAssertEqual(Collecting.comboKey(expressed: c.expressed), c.key)
        }
        XCTAssertNil(Collecting.comboKey(expressed: [0, 1]))
    }

    func testSurprises() throws {
        let s = try load()
        XCTAssertEqual(s.surprises.count, 20)
        for c in s.surprises {
            XCTAssertEqual(Collecting.dailySurprise(playerId: c.playerId, day: c.day), c.souvenir,
                           "\(c.playerId) \(c.day)")
        }
    }

    func testSeasonsMatchTS() throws {
        let s = try load()
        XCTAssertEqual(s.seasons, Collecting.seasons)
    }

    func testGeneration() {
        XCTAssertEqual(Collecting.generation(parentGenerations: []), 0)
        XCTAssertEqual(Collecting.generation(parentGenerations: [0, 0]), 1)
        XCTAssertEqual(Collecting.generation(parentGenerations: [2, 0]), 3)
    }
}
