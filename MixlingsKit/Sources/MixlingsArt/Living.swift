// Living world (docs/living-world-spec.md §1 weather, §8 jump rope, §9 pair life, §13 alive).
// Swift port of the "living world", "scenes", "jump rope" and "lock-screen glyphs" sections
// of art/render.py. Mirrors art/ts-port/render.ts line by line (verified against every case
// of art/golden/renders.json). Constant tables live in LivingTables.swift (generated).
import Foundation

// MARK: - public constants

/// Named values for `Phenotype.weather`, `.item`, `.alive` and the scene renderers.
public enum LivingWorld {
    // Phenotype.weather
    public static let none = 0, rain = 1, heat = 2, snow = 3, wind = 4, night = 5
    // Phenotype.item
    public static let umbrella = 1, waterBottle = 2, fan = 3, sunHat = 4, scarf = 5,
                      beanie = 6, blanket = 7, jumpRope = 8, juiceBox = 9
    // Phenotype.alive
    public static let charging = 1, lowPower = 2, morning = 3
    // renderRoom scenes / renderGlyph indices (glyph 7 = jump rope)
    public static let chess = 0, painting = 1, chatting = 2, napping = 3, stargazing = 4,
                      breakfast = 5, homework = 6, jumpRopeGlyph = 7
    public static let sceneCount = 7, glyphCount = 8
    // time of day
    public static let day = 0, nightTime = 1
    /// Jump-rope frames: 0...3 rope loop (over, front, under, behind), 4 trip, 5 cheer.
    public static let jumpRopeFrames = 6
    /// Room / yard size and glyph size.
    public static let sceneWidth = 64, sceneHeight = 48, glyphSize = 16
}

let NONE = 0, RAIN = 1, HEAT = 2, SNOW = 3, WIND = 4, NIGHT = 5
let I_UMBRELLA = 1, I_BOTTLE = 2, I_FAN = 3, I_HAT = 4, I_SCARF = 5, I_BEANIE = 6,
    I_BLANKET = 7, I_ROPE = 8, I_JUICE = 9
let A_CHARGING = 1, A_LOWPOWER = 2, A_MORNING = 3
let EYE_SQUINT = 8, EYE_CLOSED = 9, EYE_CLOSED_CYCLOPS = 10

/// One painted pixel (later entries win).
struct Paint {
    var x: Int
    var y: Int
    var c: RGB
}

func lwSprite(_ x0: Int, _ y0: Int, _ rows: [String], _ out: inout [Paint],
              _ cmap: [Character: RGB] = LW) {
    for s in sprite(rows) { out.append(Paint(x: x0 + s.x, y: y0 + s.y, c: cmap[s.ch]!)) }
}

func rowExt(_ m: Mask, _ y: Int) -> (l: Int, r: Int) {
    let xs = m.sortedPoints().filter { $0.y == y }.map { $0.x }
    guard let lo = xs.min(), let hi = xs.max() else { return (16, 15) }
    return (lo, hi)
}

/// Effective (weather, item) after the widget-alive override (§13).
func stateWeather(_ p: Phenotype) -> (weather: Int, item: Int) {
    var w = p.weather, it = p.item
    if p.alive == A_CHARGING {
        it = I_JUICE
    } else if p.alive == A_LOWPOWER {
        w = NIGHT; it = I_BLANKET
    }
    return (w, it)
}

/// (eyes, mood) after weather / alive expressions.
func stateFace(_ p: Phenotype) -> (eyes: Int, mood: Int) {
    let w = stateWeather(p).weather
    let cyc = p.eyes == 7
    if w == NIGHT { return (cyc ? EYE_CLOSED_CYCLOPS : EYE_CLOSED, 0) }
    if p.alive == A_MORNING { return (cyc ? 7 : 3, 1) }
    if p.alive == A_CHARGING { return (cyc ? 7 : 3, 0) }
    if w == HEAT { return (cyc ? 7 : EYE_SQUINT, 1) }
    if w == RAIN { return (cyc ? 7 : 3, 0) }
    if w == SNOW { return (p.eyes, 2) }
    return (p.eyes, p.mood)
}

/// Integer parabola from (x0, hy) to (x1, hy) through the apex; vertical gaps filled.
func ropeArc(_ x0: Int, _ x1: Int, _ hy: Int, _ apex: Int, _ out: inout [Paint], _ rgb: RGB) {
    let half = floorDiv(x1 - x0, 2), cx = x0 + half
    var prev: Int? = nil
    var x = x0
    while x <= x1 {
        let d = x - cx
        let y = hy + floorDiv((apex - hy) * (half * half - d * d), half * half)
        out.append(Paint(x: x, y: y, c: rgb))
        if let pv = prev, abs(y - pv) > 1 {
            let step = y > pv ? 1 : -1
            var yy = pv + step
            while yy != y { out.append(Paint(x: x, y: yy, c: rgb)); yy += step }
        }
        prev = y
        x += 1
    }
}

func mouthY(_ p: Phenotype, _ a: Anchors) -> Int {
    let e = eyeLayout(stateFace(p).eyes, a)
    return e.y0 + e.h + (e.h >= 3 ? 1 : 2)
}

func itemLayer(_ p: Phenotype, _ it: Int, _ m: Mask, _ a: Anchors,
               _ front: inout [Paint], _ behind: inout [Paint]) {
    let top = a.top, bottom = a.bottom, mid = a.midY
    let (lx, rx) = rowExt(m, mid)
    let N = LW["N"]!, o = LW["o"]!
    switch it {
    case I_UMBRELLA: // tilted to the right, handle in the right paw
        let y0 = max(0, top - 11)
        lwSprite(10, y0, UMBRELLA, &front)
        let hx = min(rx, 24)
        var y = y0 + 6
        while y < mid + 2 { front.append(Paint(x: hx, y: y, c: N)); y += 1 }
        front.append(Paint(x: hx - 1, y: mid + 2, c: N))
        front.append(Paint(x: hx - 2, y: mid + 1, c: N))
    case I_BOTTLE:
        lwSprite(rx - 1, mid - 2, BOTTLE, &front)
    case I_FAN:
        lwSprite(max(0, lx - 7), mid - 7, FAN, &front)
    case I_HAT:
        lwSprite(8, top - 4, SUN_HAT, &front)
    case I_BEANIE:
        lwSprite(10, top - 4, BEANIE, &front)
    case I_SCARF:
        let sy = a.eyeY + 5
        for y in [sy, sy + 1] {
            let (l, r) = rowExt(m, y)
            var x = l - 1
            while x < r + 2 {
                let ch: Character = pyIntMod(x + y, 4) == 0 ? "w" : (y == sy + 1 ? "R" : "r")
                front.append(Paint(x: x, y: y, c: LW[ch]!))
                x += 1
            }
            front.append(Paint(x: l - 2, y: y, c: o))
            front.append(Paint(x: r + 2, y: y, c: o))
        }
        let (l, r) = rowExt(m, sy + 1)
        var x = l - 1
        while x < r + 2 { front.append(Paint(x: x, y: sy + 2, c: o)); x += 1 }
        let tx = r - 4
        let tail = Array(["orro", "orwo", "orro", "orRo"].prefix(max(1, min(4, bottom - sy - 2)))) + ["oooo"]
        for (i, row) in tail.enumerated() { // clipped to the body (short on babies)
            lwSprite(tx, sy + 2 + i, [row], &front)
        }
    case I_BLANKET:
        let y0 = mid + 2
        var y = y0
        while y < bottom + 3 {
            let l = lx - 2, r = rx + 2
            for x in l...r {
                if y == y0 || x == l || x == r || y == bottom + 2 {
                    if !(y == y0 && (x == l || x == r)) { front.append(Paint(x: x, y: y, c: o)) }
                    continue
                }
                var ch: Character = (floorDiv(x - l, 3) + floorDiv(y - y0, 3)) % 2 == 0 ? "p" : "P"
                if y == y0 + 1 { ch = "w" }
                front.append(Paint(x: x, y: y, c: LW[ch]!))
            }
            y += 1
        }
    case I_ROPE:
        let hl = lx - 3, hr = rx + 2
        lwSprite(hl, mid - 1, HANDLE, &front)
        lwSprite(hr, mid - 1, HANDLE, &front)
        ropeArc(hl, hr + 1, mid - 1, 0, &behind, LW["M"]!)
    case I_JUICE: // straw tip at the right corner of the mouth
        lwSprite(18, mouthY(p, a), JUICE, &front)
    default:
        break
    }
}

func shiftCanvas(_ c: Canvas, _ dx: Int, _ dy: Int) -> Canvas {
    var out = Canvas()
    for x in 0..<S {
        for y in 0..<S {
            guard let px = c.get(x, y) else { continue }
            let nx = x + dx, ny = y + dy
            if nx >= 0 && nx < S && ny >= 0 && ny < S { out.px[ny * S + nx] = px }
        }
    }
    return out
}

/// Morning stretch: rows <= refY move up one, row refY is kept twice.
func stretchCanvas(_ c: Canvas, _ refY: Int) -> Canvas {
    var out = Canvas()
    for i in 0..<(S * S) where c.px[i] != nil && i / S >= refY { out.px[i] = c.px[i] }
    for x in 0..<S {
        for y in 0..<S {
            guard let px = c.get(x, y) else { continue }
            if y <= refY && y - 1 >= 0 { out.px[(y - 1) * S + x] = px }
        }
    }
    return out
}

/// Weather / care item / alive layers: (canvas, behind, front).
func living(_ p: Phenotype, _ canvasIn: Canvas) -> (Canvas, [Paint], [Paint]) {
    var canvas = canvasIn
    let (w, it) = stateWeather(p)
    if w == NONE && it == 0 && p.alive == 0 { return (canvas, [], []) }
    var behind: [Paint] = [], front: [Paint] = []
    let q = LW["q"]!
    if w == RAIN {
        for (x, y) in RAIN_DROPS {
            if it == I_UMBRELLA && x >= 4 && x <= 28 && y <= 20 { continue }
            behind.append(Paint(x: x, y: y, c: LW["c"]!))
            behind.append(Paint(x: x, y: y + 1, c: LW["t"]!))
            behind.append(Paint(x: x, y: y + 2, c: LW["b"]!))
        }
    } else if w == SNOW {
        for (x, y) in SNOW_FLAKES { lwSprite(x - 1, y - 1, FLAKE, &behind) }
    } else if w == WIND {
        for (x, y, n) in WIND_LINES { for i in 0..<n { behind.append(Paint(x: x + i, y: y, c: q)) } }
        lwSprite(27, 5, LEAF, &behind)
    } else if w == HEAT {
        lwSprite(0, 0, SUN, &behind)
    } else if w == NIGHT && it != I_BLANKET {
        lwSprite(1, 1, MOON, &behind)
    }
    if p.stage == EGG { // eggs only get the weather around them
        if w == NIGHT { lwSprite(22, 3, ZZZ_ROWS, &front) }
        return (canvas, behind, front)
    }
    let m = bodyMask(p.body, p.stage)
    let a = anchors(m)
    var bodyFront: [Paint] = [], bodyBehind: [Paint] = []
    itemLayer(p, it, m, a, &bodyFront, &bodyBehind)
    let (lx, rx) = rowExt(m, a.midY)
    if w == RAIN {
        for (dx, dy) in SHEEN {
            let x = 16 + dx, y = a.midY + dy
            if m.contains(x, y) && m.contains(x, y + 1) {
                bodyFront.append(Paint(x: x, y: y, c: LW["w"]!))
                bodyFront.append(Paint(x: x, y: y + 1, c: LW["t"]!))
            }
        }
    } else if w == HEAT {
        lwSprite(16 + a.eyeDx + 3, a.eyeY - 6, SWEAT, &bodyFront)
    } else if w == SNOW && it != I_BEANIE && it != I_HAT {
        let pts = m.sortedPoints()
        for x in 12..<20 {
            if let t = pts.filter({ $0.x == x }).map({ $0.y }).min() {
                bodyFront.append(Paint(x: x, y: t, c: LW["w"]!))
                if x >= 14 && x <= 17 { bodyFront.append(Paint(x: x, y: t + 1, c: LW["w"]!)) }
            }
        }
    }
    if w == NIGHT { lwSprite(22, max(0, a.top - 8), ZZZ_ROWS, &front) }
    if p.alive == A_CHARGING { lwSprite(25, max(0, a.top - 6), BOLT, &front) }
    if p.alive == A_MORNING { lwSprite(24, max(0, a.top - 9), BANG, &front) }
    // pose
    var dx = 0, dy = 0
    if w == RAIN { // happily splashing: hop + puddle
        dy = -1
        let b = a.bottom + 1
        for x in (lx - 1)..<(rx + 2) { behind.append(Paint(x: x, y: b + 1, c: LW["t"]!)) }
        if lx + 1 < rx { for x in (lx + 1)..<rx { behind.append(Paint(x: x, y: b + 2, c: LW["c"]!)) } }
        behind.append(Paint(x: lx - 3, y: b - 1, c: LW["t"]!))
        behind.append(Paint(x: lx - 4, y: b - 2, c: LW["c"]!))
        behind.append(Paint(x: rx + 3, y: b - 1, c: LW["t"]!))
        behind.append(Paint(x: rx + 4, y: b - 2, c: LW["c"]!))
    } else if w == SNOW { // shiver offset
        dx = 1
        for y in [a.midY - 1, a.midY + 1] {
            behind.append(Paint(x: lx - 2, y: y, c: q))
            behind.append(Paint(x: rx + 4, y: y, c: q))
        }
        behind.append(Paint(x: lx - 3, y: a.midY, c: q))
        behind.append(Paint(x: rx + 5, y: a.midY, c: q))
    }
    if p.alive == A_MORNING && w != NIGHT {
        dx = 0; dy = 0 // the stretch replaces the weather pose
        canvas = stretchCanvas(canvas, a.midY)
        bodyFront = bodyFront.map { Paint(x: $0.x, y: $0.y <= a.midY ? $0.y - 1 : $0.y, c: $0.c) }
        front.append(Paint(x: lx - 2, y: a.top - 1, c: q))
        front.append(Paint(x: lx - 3, y: a.top - 2, c: q))
        front.append(Paint(x: rx + 2, y: a.top - 1, c: q))
        front.append(Paint(x: rx + 3, y: a.top - 2, c: q))
    } else if dx != 0 || dy != 0 {
        canvas = shiftCanvas(canvas, dx, dy)
    }
    let fx = dx, fy = dy
    front = bodyFront.map { Paint(x: $0.x + fx, y: $0.y + fy, c: $0.c) } + front
    behind = behind + bodyBehind.map { Paint(x: $0.x + fx, y: $0.y + fy, c: $0.c) }
    return (canvas, behind, front)
}

/// Colour creature as an ordered paint list (later entries win), 32x32 coordinates.
/// `plain`: no living-world layers (scenes pass their own `face`).
func creatureLayers(_ p: Phenotype, face: (eyes: Int, mood: Int)? = nil, plain: Bool = false,
                    aura: Bool = true) -> [Paint] {
    var canvas = build(p, false, face: face)
    var behind: [Paint] = [], front: [Paint] = []
    if !plain { (canvas, behind, front) = living(p, canvas) }
    let pal = makePalette(p.palette, p.shift)
    var out: [Paint] = []
    func inS(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < S && y >= 0 && y < S }
    if p.stage == ADULT && aura {
        for e in drawAura(p.aura, p.seed) where inS(e.x, e.y) && !canvas.has(e.x, e.y) {
            out.append(Paint(x: e.x, y: e.y, c: pal[e.role]))
        }
    }
    for b in behind where inS(b.x, b.y) && !canvas.has(b.x, b.y) { out.append(b) }
    for x in 0..<S {
        for y in 0..<S {
            if let px = canvas.get(x, y) { out.append(Paint(x: x, y: y, c: pal[px.role])) }
        }
    }
    for f in front where inS(f.x, f.y) { out.append(f) }
    return out
}

// MARK: - scenes (64x48)

let RW = 64, RH = 48

/// Opaque-or-empty RGB grid; every write is bounds-checked.
struct Img {
    let w: Int, h: Int
    var px: [RGB?]

    init(_ w: Int, _ h: Int) { self.w = w; self.h = h; px = [RGB?](repeating: nil, count: w * h) }

    mutating func set(_ x: Int, _ y: Int, _ rgbIn: RGB, _ tint: RGB? = nil) {
        guard x >= 0 && x < w && y >= 0 && y < h else { return }
        var rgb = rgbIn
        if let t = tint {
            rgb = RGB(floorDiv(rgb.r * t.r, 256), floorDiv(rgb.g * t.g, 256), floorDiv(rgb.b * t.b, 256))
        }
        px[y * w + x] = rgb
    }

    mutating func spr(_ x0: Int, _ y0: Int, _ rows: [String], _ tint: RGB? = nil,
                      _ cmap: [Character: RGB] = LW) {
        for s in sprite(rows) { set(x0 + s.x, y0 + s.y, cmap[s.ch]!, tint) }
    }

    mutating func creature(_ layers: [Paint], _ ox: Int, _ oy: Int, mirror: Bool = false, tint: RGB? = nil) {
        for l in layers { set(ox + (mirror ? 31 - l.x : l.x), oy + l.y, l.c, tint) }
    }

    func buffer() -> PixelBuffer {
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            guard let c = px[i] else { continue }
            buf[i * 4] = UInt8(c.r); buf[i * 4 + 1] = UInt8(c.g); buf[i * 4 + 2] = UInt8(c.b)
            buf[i * 4 + 3] = 255
        }
        return PixelBuffer(width: w, height: h, rgba: buf)
    }
}

let WALL_Y1 = 32, FLOOR_Y0 = 34
let WIN_X0 = 24, WIN_Y0 = 3, WIN_X1 = 39, WIN_Y1 = 16
let LAMP_LIT: [Character: RGB] = { var m = LW; m["y"] = LW["l"]!; return m }()

func skyKind(_ tod: Int, _ weather: Int) -> String {
    let night = tod == LivingWorld.nightTime || weather == NIGHT
    if weather == RAIN { return night ? "rain_night" : "rain" }
    if weather == SNOW { return "snow" }
    return night ? "night" : "day"
}

func drawWindow(_ im: inout Img, _ kind: String, _ weather: Int) {
    let (top, bot) = SKY[kind]!
    for y in (WIN_Y0 + 1)..<WIN_Y1 {
        let c = y < floorDiv(WIN_Y0 + WIN_Y1, 2) ? top : bot
        for x in (WIN_X0 + 1)..<WIN_X1 { im.set(x, y, c) }
    }
    if kind == "day" {
        im.spr(27, 5, CLOUD)
        if weather == HEAT { im.spr(32, 4, ["..y..", ".yyy.", "yyyyy", ".yyy.", "..y.."]) }
        if weather == WIND { im.spr(33, 11, LEAF); im.spr(29, 8, [".g", "G."]) }
    } else if kind == "night" {
        for (x, y) in WIN_STARS { im.set(x, y, RGB(255, 244, 200)) }
        im.spr(34, 9, MOON)
    } else if kind.hasPrefix("rain") {
        for (x, y) in WIN_RAIN { im.set(x, y, RGB(200, 214, 236)); im.set(x - 1, y + 1, RGB(200, 214, 236)) }
    } else { // snow
        for (x, y) in WIN_SNOW { im.set(x, y, RGB(255, 255, 255)) }
    }
    let frame = (kind == "day" || kind == "rain" || kind == "snow") ? RGB(255, 255, 255) : RGB(196, 188, 228)
    let mx = floorDiv(WIN_X0 + WIN_X1, 2), my = floorDiv(WIN_Y0 + WIN_Y1, 2)
    let o = LW["o"]!
    for x in WIN_X0...WIN_X1 { im.set(x, WIN_Y0, o); im.set(x, WIN_Y1, o); im.set(x, my, frame) }
    for y in WIN_Y0...WIN_Y1 {
        im.set(WIN_X0, y, o); im.set(WIN_X1, y, o)
        if y > WIN_Y0 && y < WIN_Y1 { im.set(mx, y, frame) }
    }
    for x in (WIN_X0 - 1)..<(WIN_X1 + 2) { im.set(x, WIN_Y1 + 1, LW["N"]!); im.set(x, WIN_Y1 + 2, o) }
}

func drawRoomBg(_ im: inout Img, _ night: Bool) {
    func col(_ k: String) -> RGB { night ? ROOM[k]!.1 : ROOM[k]!.0 }
    for y in 0...WALL_Y1 {
        for x in 0..<RW { im.set(x, y, (x % 6 == 0 || x % 6 == 1) ? col("stripe") : col("wall")) }
    }
    for x in 0..<RW { im.set(x, WALL_Y1 + 1, col("base")) }
    for y in FLOOR_Y0..<RH {
        for x in 0..<RW {
            var c = col("floor")
            if (y - FLOOR_Y0) % 5 == 4 || (x + 7 * floorDiv(y - FLOOR_Y0, 5)) % 21 == 0 {
                c = col("plank")
            } else if y == FLOOR_Y0 {
                c = col("floor_hi")
            }
            im.set(x, y, c)
        }
    }
}

func drawFurniture(_ im: inout Img, _ slots: [Int], _ night: Bool) {
    let t: RGB? = night ? NIGHT_TINT : nil
    func on(_ i: Int) -> Bool { i < slots.count && slots[i] != 0 }
    if on(5) { // ceiling garland
        var prev: Int? = nil
        for x in 2..<62 {
            let d = x - 32
            let y = 1 + floorDiv(3 * (900 - d * d), 900)
            im.set(x, y, LW["N"]!, t)
            if let pv = prev, y != pv { im.set(x, pv, LW["N"]!, t) }
            prev = y
            if x % 6 == 5 {
                let c = LW[BULBS[floorDiv(x, 6) % 5]]!
                im.set(x, y + 1, c, night ? nil : t)
                im.set(x, y + 2, night ? LW["l"]! : c, night ? nil : t)
            }
        }
    }
    if on(0) { im.spr(4, 7, PICTURE, t) }
    if on(1) { im.spr(46, 6, SHELF, t) }
    if on(4) { // rug (behind creatures)
        for y in 39..<47 {
            for x in 10..<54 {
                let dx = (x - 32) * 4, dy = (y - 43) * 22
                let r = dx * dx + dy * dy
                if r <= 88 * 88 {
                    let c: Character = r > 74 * 74 ? "M" : (floorDiv(abs(x - 32), 4) % 2 == 0 ? "m" : "w")
                    im.set(x, y, LW[c]!, t)
                }
            }
        }
    }
    if on(2) { im.spr(0, 27, PLANT, t) }
    if on(3) {
        if night { im.spr(55, 12, LAMP, nil, LAMP_LIT) } else { im.spr(55, 12, LAMP, t) }
    }
}

func sceneFaces(_ scene: Int, _ pa: Phenotype, _ pb: Phenotype) -> ((eyes: Int, mood: Int), (eyes: Int, mood: Int)) {
    func f(_ p: Phenotype, _ e: Int, _ mood: Int) -> (eyes: Int, mood: Int) {
        var eyes = e
        if p.eyes == 7 && eyes != 7 && eyes != EYE_CLOSED_CYCLOPS { eyes = 7 }
        if p.eyes == 7 && eyes == EYE_CLOSED { eyes = EYE_CLOSED_CYCLOPS }
        return (eyes, mood)
    }
    switch scene {
    case LivingWorld.chess: return (f(pa, pa.eyes, 1), f(pb, pb.eyes, 0))
    case LivingWorld.painting: return (f(pa, 3, 0), f(pb, pb.eyes, 1))
    case LivingWorld.chatting: return (f(pa, pa.eyes, 1), f(pb, 3, 0))
    case LivingWorld.napping: return (f(pa, EYE_CLOSED, 0), f(pb, EYE_CLOSED, 0))
    case LivingWorld.stargazing: return (f(pa, 4, 1), f(pb, 4, 1))
    case LivingWorld.breakfast: return (f(pa, 3, 0), f(pb, 3, 0))
    default: return (f(pa, pa.eyes, 0), f(pb, 2, 1)) // homework: one focused, one sleepy
    }
}

/// Python `(pa.seed * 31 + pb.seed * 7 + scene * 101) & 0xFFFFFFFF`.
func pairSeed(_ pa: Phenotype, _ pb: Phenotype, _ scene: Int) -> UInt32 {
    return mask32(pa.seed &* 31 &+ pb.seed &* 7 &+ scene &* 101)
}

func drawSceneProps(_ im: inout Img, _ scene: Int, _ pa: Phenotype, _ pb: Phenotype, _ night: Bool) {
    let t: RGB? = night ? NIGHT_TINT : nil
    switch scene {
    case LivingWorld.chess:
        im.spr(24, 30, CHESS_TABLE, t)
    case LivingWorld.painting:
        im.spr(25, 21, EASEL, t)
        let qa = makePalette(pa.palette, pa.shift), qb = makePalette(pb.palette, pb.shift)
        let cols = [qa[.base], qb[.base], qa[.accent], qb[.accent]]
        for (x, y, i) in EASEL_DABS { im.set(25 + x, 21 + y, cols[i], t) }
        im.spr(36, 41, PAINT_POT, t)
    case LivingWorld.chatting:
        var rnd = ArtMulberry(pairSeed(pa, pb, scene))
        let a = rnd.int(EMOTES.count)
        var b = rnd.int(EMOTES.count - 1)
        if b >= a { b += 1 }
        im.spr(15, 2, BUBBLE)
        im.spr(18, 3, EMOTES[a])
        im.spr(38, 2, BUBBLE.map { String($0.reversed()) })
        im.spr(41, 3, EMOTES[b])
    case LivingWorld.napping:
        let Y = 33
        for y in Y..<45 {
            for x in 4..<60 {
                if y == Y || y == 44 || x == 4 || x == 59 {
                    if !((y == Y || y == 44) && (x == 4 || x == 59)) { im.set(x, y, LW["o"]!, t) }
                    continue
                }
                let c: Character = y == Y + 1 ? "w" : ((floorDiv(x - 4, 4) + floorDiv(y - Y, 4)) % 2 == 0 ? "p" : "P")
                im.set(x, y, LW[c]!, t)
            }
        }
        im.spr(28, 20, ZZZ_ROWS)
    case LivingWorld.stargazing:
        im.spr(28, 22, TELESCOPE, t)
    case LivingWorld.breakfast:
        im.spr(24, 30, BREAKFAST_TABLE, t)
        im.spr(25, 29, PLATE_FOOD, t)
        im.spr(32, 29, EGG_PLATE, t)
    case LivingWorld.homework: // desk lamp: never tinted, lit at night
        im.spr(24, 28, DESK, nil, night ? LAMP_LIT : LW)
    default:
        break
    }
}

// MARK: - jump rope (64x48 yard)

let YARD_GROUND = 40
let JR_TRIP = 4, JR_CHEER = 5

func drawYard(_ im: inout Img) {
    func Y(_ k: String) -> RGB { YARD[k]! }
    func fenceCol(_ x: Int) -> Bool { [1, 2, 3, 4].contains(x % 6) }
    for y in 0..<RH {
        for x in 0..<RW {
            var c: RGB
            if y < 14 {
                c = Y("sky0")
            } else if y < 24 {
                c = Y("sky1")
            } else if y < 30 {
                c = Y("sky2")
            } else if y < YARD_GROUND - 6 {
                c = fenceCol(x) ? Y("fence") : Y("sky2")
                if (y == 31 || y == 32) && !fenceCol(x) { c = Y("fence_s") }
            } else if y < YARD_GROUND - 2 {
                c = (x + y) % 3 == 0 ? Y("grass_d") : Y("grass")
            } else {
                c = y > YARD_GROUND - 2 ? Y("grass") : Y("grass_l")
            }
            im.set(x, y, c)
        }
    }
    for x in 0..<RW { // fence post tops
        if x % 6 == 2 || x % 6 == 3 { im.set(x, 29, Y("fence")) }
        if x % 6 == 4 { for y in 30..<(YARD_GROUND - 6) { im.set(x, y, Y("fence_s")) } }
    }
    for (x, y) in YARD_CLOUDS { im.spr(x, y, BIG_CLOUD) }
    im.spr(54, 2, SUN)
    for (x, y) in YARD_TUFTS {
        im.set(x, y, Y("grass_d")); im.set(x + 1, y - 1, Y("grass_d")); im.set(x + 2, y, Y("grass_d"))
    }
    for (x, y, c) in YARD_FLOWERS {
        var cm = LW
        cm["c"] = LW[c]!
        cm["y"] = c != "y" ? LW["y"]! : LW["w"]!
        im.spr(x - 1, y - 1, [".c.", "cyc", ".c."], nil, cm)
        im.set(x, y + 1, LW["G"]!)
    }
}

func jumpRopeImg(_ p: Phenotype, _ frame: Int) -> Img {
    var im = Img(RW, RH)
    drawYard(&im)
    let m = bodyMask(p.body, p.stage)
    let a = anchors(m)
    let (lx, rx) = rowExt(m, a.midY)
    let ox = 16, baseOy = YARD_GROUND + 2 - (a.bottom + 1)
    let phase: Int, h: Int, face: (eyes: Int, mood: Int)
    if frame == JR_TRIP {
        phase = 2; h = 0; face = (p.eyes == 7 ? 7 : EYE_SQUINT, 1)
    } else if frame == JR_CHEER {
        phase = 0; h = 3; face = (p.eyes == 7 ? 7 : 3, 1)
    } else {
        let (ph, pose) = JR_LOOP[pyIntMod(frame, 4)]
        phase = ph; h = JR_HEIGHT[pose]; face = (p.eyes, pose == 2 ? 1 : 0)
    }
    let oy = baseOy - h
    // ground shadow shrinks while airborne
    let sw = floorDiv(rx - lx, 2) - h, cx = ox + 16
    var x = cx - sw
    while x < cx + sw { im.set(x, YARD_GROUND + 2, YARD["shadow"]!); x += 1 }
    let hl = ox + lx - 3, hr = ox + rx + 2, hy = oy + a.midY - 1
    let rope = LW["R"]!
    var behind: [Paint] = [], front: [Paint] = []
    if frame == JR_TRIP { // rope tangled around the feet
        let fy = YARD_GROUND + 1
        ropeArc(hl, hr + 1, hy + 2, fy + 2, &front, rope)
        for (tx, ty) in [(cx - 6, fy - 1), (cx - 5, fy - 2), (cx + 4, fy - 1), (cx + 5, fy - 2)] {
            front.append(Paint(x: tx, y: ty, c: rope))
        }
    } else if phase == 0 {
        ropeArc(hl, hr + 1, hy, max(1, oy + a.top - 8), &front, rope)
    } else if phase == 1 {
        ropeArc(hl, hr + 1, hy, oy + a.midY + 5, &front, rope)
    } else if phase == 2 {
        ropeArc(hl, hr + 1, hy, YARD_GROUND + 3, &front, rope)
    } else {
        ropeArc(hl, hr + 1, hy, max(1, oy + a.top - 5), &behind, rope)
    }
    behind = behind + behind.map { Paint(x: $0.x, y: $0.y + 1, c: $0.c) }
    front = front + front.map { Paint(x: $0.x, y: $0.y + 1, c: $0.c) }
    for b in behind { im.set(b.x, b.y, b.c) }
    var layers = creatureLayers(p, face: face, plain: true, aura: false)
    if frame == JR_TRIP { // tilted: shift upper rows left by one
        layers = layers.map { Paint(x: $0.y < a.midY ? $0.x - 1 : $0.x, y: $0.y, c: $0.c) }
        im.creature(layers, ox, oy)
        for (dx, dy) in [(-2, -4), (3, -6), (8, -4)] { im.spr(ox + 16 + dx - 1, oy + a.top + dy - 1, DIZZY) }
    } else {
        im.creature(layers, ox, oy)
    }
    for f in front { im.set(f.x, f.y, f.c) }
    if frame != JR_TRIP { im.spr(hl, hy, HANDLE); im.spr(hr, hy, HANDLE) }
    if frame == JR_CHEER {
        for (sx, sy) in [(6, 12), (52, 16), (10, 26), (49, 30)] { im.spr(sx, sy, STARBURST) }
    }
    return im
}

// MARK: - public API

extension MixlingsRenderer {
    /// 64x48 cutaway room: back wall + window (day / night / rain / snow sky), floor strip,
    /// 6 furniture slots (picture, shelf, plant, lamp, rug, garland; 0 = empty) and the pair
    /// living `scene` (`LivingWorld.chess` ... `.homework`). Stargazing is always at night.
    /// Opaque. Pixel-identical to Python `render_room(pair, scene, time_of_day, weather, furniture)`.
    public static func renderRoom(_ pair: (Phenotype, Phenotype), scene: Int,
                                  timeOfDay: Int = LivingWorld.day, weather: Int = LivingWorld.none,
                                  furniture: [Int] = [1, 1, 1, 1, 1, 1]) -> PixelBuffer {
        let (pa, pb) = pair
        let tod = scene == LivingWorld.stargazing ? LivingWorld.nightTime : timeOfDay
        let night = tod == LivingWorld.nightTime || weather == NIGHT
        var im = Img(RW, RH)
        drawRoomBg(&im, night)
        drawWindow(&im, skyKind(tod, weather), weather)
        drawFurniture(&im, furniture, night)
        let (fa, fb) = sceneFaces(scene, pa, pb)
        let ct: RGB? = night ? CREATURE_NIGHT : nil
        let oy = 12 + (scene == LivingWorld.napping ? 2 : 0)
        im.creature(creatureLayers(pa, face: fa, plain: true, aura: false), 0, oy, mirror: true, tint: ct)
        im.creature(creatureLayers(pb, face: fb, plain: true, aura: false), 32, oy, mirror: false, tint: ct)
        drawSceneProps(&im, scene, pa, pb, night)
        return im.buffer()
    }

    /// 64x48 jump-rope frame in the yard: 0...3 rope loop (over, front, under, behind) with
    /// the jump synced, 4 trip, 5 cheer. Pixel-identical to Python `render_jump_rope(p, frame)`.
    public static func renderJumpRope(_ p: Phenotype, frame: Int) -> PixelBuffer {
        return jumpRopeImg(p, frame).buffer()
    }

    /// 16x16 one-colour Lock Screen glyph (white on transparent) for a scene
    /// (`LivingWorld.chess` ... `.homework`, 7 = jump rope).
    public static func renderGlyph(scene: Int) -> PixelBuffer {
        var buf = [UInt8](repeating: 0, count: 16 * 16 * 4)
        guard scene >= 0 && scene < GLYPHS.count else { return PixelBuffer(width: 16, height: 16, rgba: buf) }
        for s in sprite(GLYPHS[scene]) {
            let i = (s.y * 16 + s.x) * 4
            buf[i] = 255; buf[i + 1] = 255; buf[i + 2] = 255; buf[i + 3] = 255
        }
        return PixelBuffer(width: 16, height: 16, rgba: buf)
    }
}
