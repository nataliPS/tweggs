import Foundation
import XCTest
@testable import MixlingsArt

// Decodable mirror of art/golden/renders.json (written by art/make_golden.py).
private struct RenderGolden: Decodable {
    struct Case: Decodable {
        let pheno: Phenotype
        let sha256: String
        let rgba_hex: String
    }
    let size: Int
    let cases: [Case]
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
        XCTAssertEqual(golden.cases.count, 74)
        var matched = 0
        for (i, c) in golden.cases.enumerated() {
            guard let want = decodeHex(c.rgba_hex) else {
                XCTFail("case \(i): bad rgba_hex"); continue
            }
            let got = MixlingsRenderer.render(c.pheno)
            XCTAssertEqual(got.width, 32)
            XCTAssertEqual(got.height, 32)
            XCTAssertEqual(got.rgba.count, want.count, "case \(i): byte count")
            if let k = zip(got.rgba, want).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                let px = k / 4
                let w = Array(want[(px * 4)..<(px * 4 + 4)])
                let g = Array(got.rgba[(px * 4)..<(px * 4 + 4)])
                XCTFail("case \(i) \(c.pheno): first differing pixel \(px) (x=\(px % 32), y=\(px / 32)) "
                        + "want RGBA \(w) got \(g)")
            } else if got.rgba.count == want.count {
                matched += 1
            }
        }
        XCTAssertEqual(matched, golden.cases.count, "\(matched)/\(golden.cases.count) golden renders matched")
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
