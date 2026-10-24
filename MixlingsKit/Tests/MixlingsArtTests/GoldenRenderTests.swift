import Foundation
import XCTest
@testable import MixlingsArt

// Decodable mirror of art/golden/renders.json (written by art/make_golden.py).
private struct RenderGolden: Decodable {
    struct Case: Decodable {
        let pheno: Phenotype
        let silhouette: Bool?
        let sha256: String
        let rgba_hex: String
    }
    struct Scene: Decodable {
        let kind: String           // "room" | "jumprope" | "glyph"
        let pair: [Phenotype]?
        let scene: Int?
        let time_of_day: Int?
        let weather: Int?
        let furniture: [Int]?
        let pheno: Phenotype?
        let frame: Int?
        let width: Int
        let height: Int
        let sha256: String
        let rgba_hex: String
    }
    let size: Int
    let cases: [Case]
    let scenes: [Scene]
}

private func decodeHex(_ s: String) -> [UInt8]? {
    let chars = Array(s.utf8)
    guard chars.count % 2 == 0 else { return nil }
    func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: return c - 48        // 0-9
        case 97...102: return c - 97 + 10  // a-f
        case 65...70: return c - 65 + 10   // A-F
        default: return nil
        }
    }
    var out = [UInt8]()
    out.reserveCapacity(chars.count / 2)
    var i = 0
    while i < chars.count {
        guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
        out.append(hi << 4 | lo)
        i += 2
    }
    return out
}

final class GoldenRenderTests: XCTestCase {
    private func loadGolden() throws -> RenderGolden {
        guard let url = Bundle.module.url(forResource: "renders", withExtension: "json") else {
            XCTFail("renders.json missing from test bundle; copy art/golden/renders.json")
            throw NSError(domain: "MixlingsArtTests", code: 1)
        }
        return try JSONDecoder().decode(RenderGolden.self, from: Data(contentsOf: url))
    }

    func testGoldenRendersPixelIdentical() throws {
        let golden = try loadGolden()
        XCTAssertEqual(golden.size, MixlingsRenderer.size)
        XCTAssertEqual(golden.cases.count, 215) // 146 approved v2 + 69 living-world
        var matched = 0
        for (i, c) in golden.cases.enumerated() {
            guard let want = decodeHex(c.rgba_hex) else {
                XCTFail("case \(i): bad rgba_hex"); continue
            }
            let got = (c.silhouette ?? false) ? MixlingsRenderer.renderSilhouette(c.pheno)
                                              : MixlingsRenderer.render(c.pheno)
            XCTAssertEqual(got.width, 32)
            XCTAssertEqual(got.height, 32)
            XCTAssertEqual(got.rgba.count, want.count, "case \(i): byte count")
            if let k = zip(got.rgba, want).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                let px = k / 4
                let w = Array(want[(px * 4)..<(px * 4 + 4)])
                let g = Array(got.rgba[(px * 4)..<(px * 4 + 4)])
                XCTFail("case \(i) \(c.pheno) silhouette=\(c.silhouette ?? false): first differing pixel \(px) (x=\(px % 32), y=\(px / 32)) "
                        + "want RGBA \(w) got \(g)")
            } else if got.rgba.count == want.count {
                matched += 1
            }
        }
        XCTAssertEqual(matched, golden.cases.count, "\(matched)/\(golden.cases.count) golden renders matched")
    }

    func testGoldenScenesPixelIdentical() throws {
        let golden = try loadGolden()
        XCTAssertEqual(golden.scenes.count, 63)
        var matched = 0
        for (i, sc) in golden.scenes.enumerated() {
            guard let want = decodeHex(sc.rgba_hex) else { XCTFail("scene \(i): bad rgba_hex"); continue }
            let got: PixelBuffer
            switch sc.kind {
            case "room":
                let pair = sc.pair!
                got = MixlingsRenderer.renderRoom((pair[0], pair[1]), scene: sc.scene!,
                                                  timeOfDay: sc.time_of_day!, weather: sc.weather!,
                                                  furniture: sc.furniture!)
            case "jumprope":
                got = MixlingsRenderer.renderJumpRope(sc.pheno!, frame: sc.frame!)
            default:
                got = MixlingsRenderer.renderGlyph(scene: sc.scene!)
            }
            XCTAssertEqual(got.width, sc.width, "scene \(i) width")
            XCTAssertEqual(got.height, sc.height, "scene \(i) height")
            guard got.rgba.count == want.count else { XCTFail("scene \(i): byte count"); continue }
            if let k = zip(got.rgba, want).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                let px = k / 4
                XCTFail("scene \(i) \(sc.kind) \(sc.scene ?? sc.frame ?? -1): first differing pixel (x=\(px % sc.width), y=\(px / sc.width)) "
                        + "want RGBA \(Array(want[(px * 4)..<(px * 4 + 4)])) got \(Array(got.rgba[(px * 4)..<(px * 4 + 4)]))")
            } else {
                matched += 1
            }
        }
        XCTAssertEqual(matched, golden.scenes.count, "\(matched)/\(golden.scenes.count) golden scenes matched")
    }

    func testGoldenCoversLivingWorld() throws {
        let golden = try loadGolden()
        XCTAssertEqual(Set(golden.cases.map { $0.pheno.weather }), Set(0...5))
        XCTAssertEqual(Set(golden.cases.map { $0.pheno.item }), Set(0...9))
        XCTAssertEqual(Set(golden.cases.map { $0.pheno.alive }), Set(0...3))
        XCTAssertEqual(Set(golden.scenes.filter { $0.kind == "room" }.compactMap { $0.scene }), Set(0..<LivingWorld.sceneCount))
        XCTAssertEqual(Set(golden.scenes.filter { $0.kind == "jumprope" }.compactMap { $0.frame }), Set(0..<LivingWorld.jumpRopeFrames))
        XCTAssertEqual(golden.scenes.filter { $0.kind == "glyph" }.count, LivingWorld.glyphCount)
    }

    func testLivingWorldDefaultsKeepV2Render() {
        // New fields default to 0 and leave the approved v2 output untouched.
        let p = Phenotype(body: 2, eyes: 4, head: 6, pattern: 2, tail: 4, palette: 7, aura: 1, seed: 9)
        XCTAssertEqual(p.weather, 0); XCTAssertEqual(p.item, 0); XCTAssertEqual(p.alive, 0)
        var q = p
        q.weather = LivingWorld.rain
        XCTAssertNotEqual(MixlingsRenderer.render(p).rgba, MixlingsRenderer.render(q).rgba)
        // Silhouettes ignore living-world layers.
        XCTAssertEqual(MixlingsRenderer.renderSilhouette(p), MixlingsRenderer.renderSilhouette(q))
    }

    func testSceneSizesAndOpacity() {
        let a = Phenotype(body: 0, eyes: 1, head: 1, pattern: 1, tail: 1, palette: 0, aura: 0)
        let b = Phenotype(body: 3, eyes: 7, head: 4, pattern: 3, tail: 2, palette: 12, aura: 2)
        for s in 0..<LivingWorld.sceneCount {
            let room = MixlingsRenderer.renderRoom((a, b), scene: s, timeOfDay: LivingWorld.nightTime)
            XCTAssertEqual(room.width, 64); XCTAssertEqual(room.height, 48)
            XCTAssertTrue(stride(from: 3, to: room.rgba.count, by: 4).allSatisfy { room.rgba[$0] == 255 }, "room is opaque")
            let g = MixlingsRenderer.renderGlyph(scene: s)
            XCTAssertEqual(g.width, 16)
            XCTAssertTrue(stride(from: 0, to: g.rgba.count, by: 4).allSatisfy {
                g.rgba[$0 + 3] == 0 || Array(g.rgba[$0..<$0 + 4]) == [255, 255, 255, 255]
            }, "glyph is one colour")
        }
        for f in 0..<LivingWorld.jumpRopeFrames {
            XCTAssertEqual(MixlingsRenderer.renderJumpRope(a, frame: f).rgba.count, 64 * 48 * 4)
        }
    }

    func testGoldenCoversStagesMoodsAndSilhouettes() throws {
        let golden = try loadGolden()
        XCTAssertEqual(Set(golden.cases.map { $0.pheno.stage }), [0, 1, 2, 3])
        XCTAssertEqual(Set(golden.cases.map { $0.pheno.mood }), [0, 1, 2])
        XCTAssertTrue(golden.cases.contains { $0.silhouette == true })
    }

    func testPhenotypeDefaultsAreAdultNeutral() throws {
        let p = Phenotype(body: 0, eyes: 0, head: 0, pattern: 0, tail: 0, palette: 0, aura: 0)
        XCTAssertEqual(p.mood, 0)
        XCTAssertEqual(p.stage, 3)
        // Older JSON without mood/stage/shift/seed still decodes, with defaults.
        let json = #"{"body":1,"eyes":2,"head":3,"pattern":4,"tail":5,"palette":6,"aura":1}"#
        let d = try JSONDecoder().decode(Phenotype.self, from: Data(json.utf8))
        XCTAssertEqual(d.stage, 3)
        XCTAssertEqual(d.mood, 0)
        XCTAssertEqual(d.shift, 0)
    }

    func testSilhouetteIsOneColourWithKnockedOutEyes() {
        let p = Phenotype(body: 0, eyes: 1, head: 1, pattern: 2, tail: 3, palette: 4, aura: 1)
        let sil = MixlingsRenderer.renderSilhouette(p)
        var opaque = 0
        for i in stride(from: 0, to: sil.rgba.count, by: 4) {
            let a = sil.rgba[i + 3]
            XCTAssertTrue(a == 0 || a == 255)
            if a == 255 {
                opaque += 1
                XCTAssertEqual(Array(sil.rgba[i..<i + 3]), [255, 255, 255])
            }
        }
        XCTAssertGreaterThan(opaque, 200)
        // Eye pixels (round adult, eye row y=18) are knocked out inside the body.
        XCTAssertEqual(sil.rgba[(18 * 32 + 19) * 4 + 3], 0)
        XCTAssertEqual(sil.rgba[(18 * 32 + 12) * 4 + 3], 0)
        XCTAssertEqual(sil.rgba[(18 * 32 + 16) * 4 + 3], 255)
        let colour = MixlingsRenderer.render(p)
        XCTAssertNotEqual(colour.rgba, sil.rgba)
    }

    func testPythonRoundIsBankers() {
        XCTAssertEqual(pyRound(0.5), 0)
        XCTAssertEqual(pyRound(1.5), 2)
        XCTAssertEqual(pyRound(2.5), 2)
        XCTAssertEqual(pyRound(30.5), 30)
        XCTAssertEqual(pyRound(-0.5), 0)
        XCTAssertEqual(pyRound(2.4999), 2)
    }

    func testPythonModAndFloorDiv() {
        XCTAssertEqual(pyMod(-0.25, 1.0), 0.75)
        XCTAssertEqual(pyMod(1.25, 1.0), 0.25)
        XCTAssertEqual(floorDiv(-1, 2), -1)
        XCTAssertEqual(floorDiv(-2, 2), -1)
        XCTAssertEqual(floorDiv(3, 2), 1)
        XCTAssertEqual(pyIntMod(-3, 5), 2)
    }

    func testSeedMaskMatchesPythonBigInt() {
        // python: (519 * 2654435761) & 0xFFFFFFFF
        XCTAssertEqual(mask32(519 &* 2_654_435_761), UInt32((519 * 2_654_435_761) % 4_294_967_296))
    }

    func testScaledIsNearestNeighbour() {
        let p = MixlingsRenderer.render(Phenotype(body: 0, eyes: 1, head: 1, pattern: 1, tail: 1, palette: 0, aura: 2))
        let big = p.scaled(by: 3)
        XCTAssertEqual(big.width, 96)
        for (x, y) in [(0, 0), (16, 20), (31, 31), (5, 9)] {
            let si = (y * 32 + x) * 4
            let di = ((y * 3 + 2) * 96 + x * 3 + 1) * 4
            XCTAssertEqual(Array(p.rgba[si..<si + 4]), Array(big.rgba[di..<di + 4]))
        }
    }
}
