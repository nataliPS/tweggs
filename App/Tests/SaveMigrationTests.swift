import XCTest
@testable import Mixlings

/// Backward compatibility: a save written by v0.1.0 (SaveData v1, no collecting fields)
/// must still load, keep every old value, and get serials + discovery log on migration.
final class SaveMigrationTests: XCTestCase {
    private func fixture() throws -> Data {
        // XcodeGen copies non-source files under Tests/ into the test bundle root.
        let bundle = Bundle(for: SaveMigrationTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "save-v1", withExtension: "json"),
                                "Tests/Fixtures/save-v1.json missing from the test bundle")
        return try Data(contentsOf: url)
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate // same as CreatureStore
        return d
    }

    func testV1SaveDecodesWithDefaults() throws {
        let save = try decoder.decode(SaveData.self, from: fixture())
        XCTAssertEqual(save.version, SaveData.currentVersion)
        XCTAssertEqual(save.playerId, "0b6f3c1e-7d2a-4b9e-9c51-2f8d7a6e1b00")
        XCTAssertEqual(save.activeCreatureId, "s_1a2b3c4d")
        XCTAssertTrue(save.onboardingComplete)
        XCTAssertEqual(save.creatures.count, 2)

        let mixy = try XCTUnwrap(save.creature(id: "s_1a2b3c4d"))
        XCTAssertEqual(mixy.name, "Mixy")
        XCTAssertEqual(mixy.origin, .hatched)
        XCTAssertEqual(mixy.hunger, 72.5)
        XCTAssertEqual(mixy.joy, 64)
        XCTAssertEqual(mixy.bornAt, Date(timeIntervalSinceReferenceDate: 783_000_000))
        XCTAssertEqual(mixy.hatchedAt, Date(timeIntervalSinceReferenceDate: 783_000_120))
        XCTAssertEqual(mixy.genome[5], [0, 2])

        // New fields: defaults.
        XCTAssertEqual(mixy.generation, 0)
        XCTAssertNil(mixy.parentIds)
        XCTAssertFalse(mixy.discoveredFirst)
        XCTAssertEqual(save.sparks, 0)
        XCTAssertNil(save.lastSurpriseDay)
        XCTAssertTrue(save.cosmetics.isEmpty)
        XCTAssertTrue(save.seasonBadges.isEmpty)
        XCTAssertTrue(save.tradeOffers.isEmpty)

        // Migration: serials in save order, both looks logged, no Discoverer for gifts.
        XCTAssertEqual(save.creatures.map(\.serial), [1, 2])
        XCTAssertEqual(save.hatchCounter, 2)
        XCTAssertEqual(save.discoveries.count, 2)
        XCTAssertFalse(save.creatures.contains { $0.discoveredFirst })
    }

    func testMigratedSaveRoundTripsWithoutRemigrating() throws {
        let save = try decoder.decode(SaveData.self, from: fixture())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let again = try decoder.decode(SaveData.self, from: encoder.encode(save))
        XCTAssertEqual(again, save)
        XCTAssertEqual(again.hatchCounter, 2)
    }

    func testV1FixtureThroughStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mixlings-v1-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try fixture().write(to: url)
        let store = CreatureStore(fileURL: url)
        let loaded = store.load()
        XCTAssertEqual(loaded.playerId, "0b6f3c1e-7d2a-4b9e-9c51-2f8d7a6e1b00", "old save must not be replaced by a fresh one")
        XCTAssertEqual(loaded.creatures.count, 2)
    }

    func testMinimalCreatureJSONDecodes() throws {
        // Oldest possible creature shape: only the required fields.
        let json = #"{"id":"x","name":"X","genome":[[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0],[0,0]],"origin":"starter","bornAt":0}"#
        let c = try decoder.decode(Creature.self, from: Data(json.utf8))
        XCTAssertEqual(c.paletteShift, 0)
        XCTAssertEqual(c.mood, CareEngine.startValue)
        XCTAssertEqual(c.lastUpdated, c.bornAt)
        XCTAssertEqual(c.generation, 0)
        XCTAssertNil(c.serial)
    }
}
