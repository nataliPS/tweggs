// Independent TypeScript port of art/render.py `render_raw(p, silhouette)`.
// Purpose: prove the algorithm is portable (rounding, colorsys, ordering) before
// trusting the Swift port (MixlingsKit/Sources/MixlingsArt), which mirrors this file.
// Run: node art/ts-port/check.ts

export const S = 32;
export const EGG = 0, BABY = 1, TEEN = 2, ADULT = 3;

export interface Pheno {
  body: number; eyes: number; head: number; pattern: number; tail: number;
  palette: number; aura: number; shift: number; seed: number;
  mood?: number;  // 0 neutral (small smile), 1 "o", 2 hungry wobble; default 0
  stage?: number; // 0 egg, 1 baby, 2 teen, 3 adult; default 3
}
type RGB = [number, number, number];
type Role = "base" | "shade" | "accent" | "light" | "outline" | "eye" | "white" | "blush" | "mouth";
interface Px { role: Role; solid: boolean; knock: boolean }

// ------------------------------------------------------------ python semantics
/** Python round(x) for floats: round-half-to-even. */
export function pyRound(x: number): number {
  const f = Math.floor(x);
  const d = x - f;
  if (d < 0.5) return f;
  if (d > 0.5) return f + 1;
  return f % 2 === 0 ? f : f + 1;
}
/** Python float % (CPython float_rem). */
export function pyMod(a: number, b: number): number {
  let m = a % b; // fmod
  if (m !== 0) { if ((b < 0) !== (m < 0)) m += b; } else { m = b < 0 ? -0 : 0; }
  return m;
}
/** Python int // for ints. */
const floorDiv = (a: number, b: number) => Math.floor(a / b);

// ------------------------------------------------------------ mulberry32
export class Mulberry {
  s: number;
  constructor(seed: number) { this.s = seed >>> 0; }
  next(): number {
    this.s = (this.s + 0x6D2B79F5) >>> 0;
    let t = this.s;
    t = Math.imul(t ^ (t >>> 15), t | 1) >>> 0;
    t = (t ^ ((t + (Math.imul(t ^ (t >>> 7), t | 61) >>> 0)) >>> 0)) >>> 0;
    return (t ^ (t >>> 14)) >>> 0;
  }
  int(n: number): number { return this.next() % n; }
  randrange(a: number, b: number): number { return a + this.int(b - a); }
  choice<T>(seq: T[]): T { return seq[this.int(seq.length)]; }
}
/** (seed * mult) & 0xFFFFFFFF, exact for any 32-bit-representable seed. */
const mul32 = (seed: number, mult: number) => Math.imul(seed | 0, mult | 0) >>> 0;

// ------------------------------------------------------------ colorsys (CPython verbatim)
const ONE_THIRD = 1.0 / 3.0, ONE_SIXTH = 1.0 / 6.0, TWO_THIRD = 2.0 / 3.0;
function rgbToHls(r: number, g: number, b: number): [number, number, number] {
  const maxc = Math.max(r, g, b), minc = Math.min(r, g, b);
  const sumc = maxc + minc, rangec = maxc - minc;
  const l = sumc / 2.0;
  if (minc === maxc) return [0.0, l, 0.0];
  let s: number;
  if (l <= 0.5) s = rangec / sumc; else s = rangec / (2.0 - maxc - minc);
  const rc = (maxc - r) / rangec, gc = (maxc - g) / rangec, bc = (maxc - b) / rangec;
  let h: number;
  if (r === maxc) h = bc - gc; else if (g === maxc) h = 2.0 + rc - bc; else h = 4.0 + gc - rc;
  h = pyMod(h / 6.0, 1.0);
  return [h, l, s];
}
function v_(m1: number, m2: number, hue: number): number {
  hue = pyMod(hue, 1.0);
  if (hue < ONE_SIXTH) return m1 + (m2 - m1) * hue * 6.0;
  if (hue < 0.5) return m2;
  if (hue < TWO_THIRD) return m1 + (m2 - m1) * (TWO_THIRD - hue) * 6.0;
  return m1;
}
function hlsToRgb(h: number, l: number, s: number): [number, number, number] {
  if (s === 0.0) return [l, l, l];
  const m2 = l <= 0.5 ? l * (1.0 + s) : l + s - (l * s);
  const m1 = 2.0 * l - m2;
  return [v_(m1, m2, h + ONE_THIRD), v_(m1, m2, h), v_(m1, m2, h - ONE_THIRD)];
}

// ------------------------------------------------------------ palettes
export const PALETTES: [number, number, number, number][] = [
  [0x7ED4A6, 0x4FA77E, 0xFFCB5C, 0xC9F2DA], // mint
  [0xF7A6C4, 0xD2759A, 0x7CC6FE, 0xFFD9E7], // bubblegum
  [0x8FA6FF, 0x5C70D6, 0xFF9F68, 0xD4DCFF], // sky
  [0xFFD36E, 0xE0A93D, 0xFF6F91, 0xFFF0C2], // sunny
  [0xC3A6FF, 0x9479D9, 0x7EF0C8, 0xE7DCFF], // lavender
  [0xFF9B7A, 0xD9704F, 0x6EE7F2, 0xFFD3C4], // coral
  [0xBCE34F, 0x88B226, 0xFF7AD9, 0xEAF8C0], // lime
  [0x4FD9EE, 0x25A8C2, 0xFFE066, 0xC6F6FD], // aqua
  [0xE8E2D0, 0xBDB4A0, 0xFF8A5B, 0xFFFFFF], // cream
  [0xA0A8B8, 0x727B8E, 0xFFD166, 0xD9DEE7], // stone
  [0xFF7AA2, 0xD24F79, 0xFFE27A, 0xFFC6D7], // rose
  [0x5E6BFF, 0x3C46C9, 0xFF9EE5, 0xB9BFFF], // cobalt
  [0x3D3D4E, 0x26262F, 0x7DF9FF, 0x6A6A82], // night (rare)
  [0xFFB347, 0xD98A1F, 0x8E7CFF, 0xFFE0B0], // tangerine
  [0xC0F5E4, 0x80C7AF, 0xFF8FAB, 0xE8FCF5], // seafoam
  [0xF2F2F2, 0xC9C9D6, 0xFFB3F0, 0xFFFFFF], // ghost (rare)
];
const GHOST = 15;
const GHOST_OUTLINE: RGB = [0x8E, 0x8A, 0xA8];
const TWIN_SHIFT = 0.08;
const hx = (c: number): RGB => [(c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF];

function shiftHue(rgb: RGB, amount: number): RGB {
  const [r, g, b] = rgb.map(v => v / 255);
  const [h0, l, s] = rgbToHls(r, g, b);
  const h = pyMod(h0 + amount, 1.0);
  const [r2, g2, b2] = hlsToRgb(h, l, s);
  return [pyRound(r2 * 255), pyRound(g2 * 255), pyRound(b2 * 255)];
}
const darken = (rgb: RGB, f: number): RGB => rgb.map(v => Math.max(0, pyRound(v * f))) as RGB;

function palette(idx: number, shift: number): Record<Role, RGB> {
  const row = PALETTES[((idx % 16) + 16) % 16]; // valid inputs: 0..15 (python index semantics for -16..-1)
  let base = hx(row[0]), shade = hx(row[1]), light = hx(row[3]);
  const accent = hx(row[2]);
  if (shift !== 0) {
    const amt = TWIN_SHIFT * shift;
    base = shiftHue(base, amt); shade = shiftHue(shade, amt); light = shiftHue(light, amt);
  }
  let outline = darken(shade, 0.45);
  const lum = 0.299 * base[0] + 0.587 * base[1] + 0.114 * base[2];
  const dark = lum < 90;
  if (dark) outline = [18, 18, 24];
  if (idx === GHOST) outline = GHOST_OUTLINE;
  return { base, shade, accent, light, outline,
    eye: dark ? accent : [34, 30, 46], white: [255, 255, 255], blush: [255, 140, 160],
    mouth: dark ? light : darken(shade, 0.45) };
}

// ------------------------------------------------------------ masks (32x32 bool grids)
type Mask = boolean[]; // index y*S+x
const newMask = (): Mask => new Array(S * S).fill(false);
const inMask = (m: Mask, x: number, y: number) => x >= 0 && x < S && y >= 0 && y < S && m[y * S + x];
const union = (a: Mask, b: Mask): Mask => a.map((t, i) => t || b[i]);

function ellipse(cx: number, cy: number, rx: number, ry: number): Mask {
  const m = newMask();
  for (let x = 0; x < S; x++) for (let y = 0; y < S; y++) {
    const a = (x + 0.5 - cx) / rx, b = (y + 0.5 - cy) / ry;
    if (a * a + b * b <= 1.0) m[y * S + x] = true;
  }
  return m;
}
function rrect(x0: number, y0: number, x1: number, y1: number, r: number): Mask {
  const m = newMask();
  for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) {
    const cx = Math.min(Math.max(x, x0 + r), x1 - r);
    const cy = Math.min(Math.max(y, y0 + r), y1 - r);
    if ((x - cx) ** 2 + (y - cy) ** 2 <= r * r + 0.5) m[y * S + x] = true;
  }
  return m;
}
/** Symmetric mask from per-row half-widths: row y0+i covers x 16-k .. 15+k. */
function rowsMask(y0: number, halves: number[]): Mask {
  const m = newMask();
  halves.forEach((k, i) => { for (let x = 16 - k; x < 16 + k; x++) m[(y0 + i) * S + x] = true; });
  return m;
}
/** Mask points in Python sorted() order: by x, then y. */
function sortedPoints(m: Mask): [number, number][] {
  const out: [number, number][] = [];
  for (let x = 0; x < S; x++) for (let y = 0; y < S; y++) if (m[y * S + x]) out.push([x, y]);
  return out;
}

const DROP_ROWS: Record<number, [number, number[]]> = {
  [ADULT]: [9, [3, 4, 4, 5, 6, 7, 7, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 8]],
  [TEEN]: [13, [2, 3, 4, 5, 5, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 6]],
  [BABY]: [17, [2, 3, 3, 4, 5, 5, 5, 5, 5, 5, 5, 4]],
};
const EGG_ROWS: [number, number[]] = [11, [2, 3, 4, 4, 5, 5, 6, 6, 6, 7, 7, 7, 7, 7, 6, 6, 5, 3]];

function bodyAdult(v: number): Mask {
  if (v === 0) return ellipse(16, 20, 9.5, 8.5);
  if (v === 1) return ellipse(16, 19, 7.5, 10.5);
  if (v === 2) return union(ellipse(16, 15, 5, 6), ellipse(16, 22, 9.5, 7));
  if (v === 3) return rrect(7, 11, 24, 28, 2);
  if (v === 4) return rowsMask(...DROP_ROWS[ADULT]);
  return ellipse(16, 22, 11.5, 6.5);
}
function bodyTeen(v: number): Mask {
  if (v === 0) return ellipse(16, 22, 7.5, 7);
  if (v === 1) return ellipse(16, 21, 6, 8.5);
  if (v === 2) return union(ellipse(16, 18.5, 4, 5), ellipse(16, 24, 7.5, 5.5));
  if (v === 3) return rrect(9, 15, 22, 28, 2);
  if (v === 4) return rowsMask(...DROP_ROWS[TEEN]);
  return ellipse(16, 23.5, 9.5, 5.5);
}
function bodyBaby(v: number): Mask {
  if (v === 0) return ellipse(16, 23.5, 6, 5.5);
  if (v === 1) return ellipse(16, 23, 4.5, 6.5);
  if (v === 2) return union(ellipse(16, 21.5, 3, 3.5), ellipse(16, 25, 6, 4));
  if (v === 3) return rrect(10, 18, 21, 28, 1);
  if (v === 4) return rowsMask(...DROP_ROWS[BABY]);
  return ellipse(16, 25, 7.5, 4);
}

function bodyMask(v: number, stage: number): Mask {
  if (stage === EGG) return rowsMask(...EGG_ROWS);
  const m = stage === ADULT ? bodyAdult(v) : stage === TEEN ? bodyTeen(v) : bodyBaby(v);
  let bottom = -1;
  for (const [, y] of sortedPoints(m)) bottom = Math.max(bottom, y);
  for (const fx of [11, 12, 19, 20]) if (inMask(m, fx, bottom)) { if (bottom + 1 < S) m[(bottom + 1) * S + fx] = true; }
  return m;
}

interface Anchors { top: number; bottom: number; eyeY: number; eyeDx: number; tailX: number; tailY: number; midY: number }
function anchors(m: Mask): Anchors {
  const pts = sortedPoints(m);
  const top = Math.min(...pts.filter(p => p[0] === 16).map(p => p[1]));
  const bottom = Math.max(...pts.map(p => p[1]));
  const h = bottom - top;
  const eyeY = top + Math.max(3, pyRound(h * 0.38));
  const row = pts.filter(p => p[1] === eyeY).map(p => p[0]);
  const half = (Math.max(...row) - Math.min(...row)) / 2;
  const eyeDx = Math.max(2, Math.min(4, pyRound(half * 0.42)));
  const tailY = top + pyRound(h * 0.68);
  const tailX = Math.max(...pts.filter(p => p[1] === tailY).map(p => p[0])) + 1;
  return { top, bottom, eyeY, eyeDx, tailX, tailY, midY: top + floorDiv(h, 2) };
}

// ------------------------------------------------------------ canvas
class Canvas {
  px: (Px | null)[] = new Array(S * S).fill(null);
  get(x: number, y: number) { return this.px[y * S + x]; }
  has(x: number, y: number) { return this.px[y * S + x] !== null; }
  set(x: number, y: number, role: Role, solid = true, knock = false) { this.px[y * S + x] = { role, solid, knock }; }
  put(x: number, y: number, role: Role, solid = true, knock = false) {
    if (x >= 0 && x < S && y >= 0 && y < S) this.set(x, y, role, solid, knock);
  }
}

// ------------------------------------------------------------ sprites
type Sprite = [number, number, string][];
function sprite(rows: string[]): Sprite {
  const out: Sprite = [];
  rows.forEach((row, y) => [...row].forEach((ch, x) => { if (ch !== ".") out.push([x, y, ch]); }));
  return out;
}
const ROLE: Record<string, Role> = { B: "base", S: "shade", A: "accent", L: "light", K: "eye", W: "white", M: "mouth", a: "accent" };

// Right eye; the left eye is its mirror (x -> 31 - x) when EYE_MIRROR, else a shifted copy.
const EYES: Record<number, Sprite> = {
  0: sprite(["KK", "KK", "KK"]),
  1: sprite([".KK.", "KWKK", "KKKK", ".KK."]),
  2: sprite(["KKKK", "...K"]),
  3: sprite([".KKK.", "K...K", "K...K"]),
  4: sprite([".WK.", "WWWK", "KWKK", ".KK."]),
  5: sprite([".K.", "WKK", "KKK", ".K."]),
  6: sprite([".K.", "KAK", ".K."]),
  7: sprite([".KKKK.", "KWWKKK", "KWKKKK", "KKKKKK", ".KKKK."]),
};
const EYE_MIRROR: Record<number, boolean> = { 0: false, 1: false, 2: true, 3: true, 4: false, 5: false, 6: false, 7: false };
const MOODS: Record<number, [number, Sprite]> = {
  0: [14, sprite(["M..M", ".MM."])],
  1: [14, sprite([".MM.", "M..M", ".MM."])],
  2: [13, sprite([".M..M.", "M.MM.M"])],
};

type Part = [number, number, string[]];
const HEADS: Record<number, Record<number, Part>> = {
  [ADULT]: {
    1: [8, -4, ["...B........B...", "..BAB......BAB..", "..BAB......BAB..", ".BAAAB....BAAAB.", ".BAAAB....BAAAB.", "BBBBBBB..BBBBBBB"]],
    2: [11, -5, ["BBB....BBB", "BLB....BLB", "BLB....BLB", "BLB....BLB", "BLB....BLB", "BLB....BLB", "BBB....BBB"]],
    3: [7, -5, ["A................A", "AA..............AA", ".AA............AA.", ".AAA..........AAA.", "..LLL........LLL..", "..LLLL......LLLL.."]],
    4: [15, -7, [".A.", "AAA", ".A.", ".S.", ".S.", ".S.", ".S."]],
    5: [13, -4, ["AAA....", ".AA.AAA", "...SAA.", "...S..."]],
    6: [10, -5, [".....AA.....", "....AAAA....", ".A..AAAA..A.", ".AA.AAAA.AA.", ".AAAAAAAAAA.", ".SSSSSSSSSS."]],
    7: [10, -5, [".aaaaaaaaaa.", "a..........a", ".aaaaaaaaaa."]],
  },
  [TEEN]: {
    1: [9, -3, ["..B........B..", ".BAB......BAB.", ".BAAB....BAAB.", "BBBBB....BBBBB"]],
    2: [11, -4, ["BBB....BBB", "BLB....BLB", "BLB....BLB", "BBB....BBB"]],
    3: [8, -3, ["A..............A", "AA............AA", ".LL..........LL.", ".LLL........LLL."]],
    4: [15, -5, [".A.", "AAA", ".A.", ".S.", ".S."]],
    5: [13, -3, ["AA..AA", ".AASA.", "...S.."]],
    6: [12, -4, ["...AA...", ".A.AA.A.", ".AAAAAA.", "SSSSSSSS"]],
    7: [12, -5, [".aaaaaa.", "a......a", ".aaaaaa."]],
  },
  [BABY]: {
    1: [10, -2, ["..B......B..", ".BAB....BAB."]],
    2: [11, -3, [".BB....BB.", ".BL....LB.", ".BB....BB."]],
    3: [10, -2, ["A..........A", ".LL......LL."]],
    4: [15, -3, [".A.", "AAA", ".S."]],
    5: [14, -2, ["AA.A", "..S."]],
    6: [13, -2, [".AA.", "AAAA"]],
    7: [13, -4, [".aaaa.", "a....a", ".aaaa."]],
  },
};
const TAILS: Record<number, Record<number, Part>> = {
  [ADULT]: {
    1: [-1, -2, [".BBB.", "BLBBB", "BBBBS", "BBBSS", ".SSS."]],
    2: [0, -5, ["..BBBB.", ".B....B", ".B.BB.B", ".B.B..B", "BB..BB.", "B......"]],
    3: [0, -6, [".....AAA", ".....AAA", ".....AAA", "....BB..", "...BB...", "..BB....", "BBB.....", "BB......"]],
    4: [0, -6, ["....A", "...AA", "..ABA", ".ABBA", "ABBB.", "BBB..", "BB..."]],
    5: [0, -6, [".....A", "...AAA", "...AA.", ".AAA..", ".AA...", ".AA...", "AA...."]],
  },
  [TEEN]: {
    1: [-1, -1, ["BBB", "BBS", ".S."]],
    2: [0, -2, [".BB", "B.B", "BB."]],
    3: [0, -2, ["..A", ".B.", "B.."]],
    4: [0, -2, [".A", "BA", "B."]],
    5: [0, -2, ["..A", ".A.", "AA."]],
  },
};

function stamp(c: Canvas, x0: number, y0: number, rows: string[]) {
  for (const [x, y, ch] of sprite(rows)) c.put(x0 + x, y0 + y, ROLE[ch], ch !== "a");
}
function drawHead(c: Canvas, v: number, a: Anchors, stage: number) {
  const part = HEADS[stage]?.[v];
  if (part) stamp(c, part[0], a.top + part[1], part[2]);
}
function drawTail(c: Canvas, v: number, a: Anchors, stage: number) {
  const part = TAILS[stage]?.[v];
  if (part) stamp(c, a.tailX + part[0], a.tailY + part[1], part[2]);
}

const SPOT_GRID = [[-7, -2], [5, -3], [-3, 2], [4, 3], [-8, 4], [0, 6], [6, -7], [-5, 7]];

function applyPattern(c: Canvas, m: Mask, v: number, a: Anchors) {
  const top = a.top, bottom = a.bottom;
  const pts = sortedPoints(m);
  if (v === 1) {
    const cy = a.midY + (bottom - a.midY) * 0.45;
    const e = ellipse(16, cy, 5, (bottom - top) * 0.28);
    for (const [x, y] of sortedPoints(e)) if (inMask(m, x, y)) c.set(x, y, "light");
  } else if (v === 2) {
    let spots = 0;
    for (const [dx, dy] of SPOT_GRID) {
      if (spots === 4) break;
      const x = 16 + dx, y = a.midY + dy;
      if (y <= a.eyeY + 2 && -7 <= dx && dx <= 5) continue;
      if (inMask(m, x, y) && inMask(m, x + 1, y) && inMask(m, x, y + 1) && inMask(m, x + 1, y + 1)) {
        for (const i of [0, 1]) for (const j of [0, 1]) c.set(x + i, y + j, "accent");
        spots++;
      }
    }
  } else if (v === 3) {
    for (const [x, y] of pts) if (y > a.eyeY + 3 && [0, 1].includes(pyMod(y - top, 5))) c.set(x, y, "accent");
  } else if (v === 4) {
    for (const [x, y] of pts) if (y < top + (bottom - top) * 0.3) c.set(x, y, "accent");
  } else if (v === 5) {
    for (const [dx, dy] of [[0, 0], [2, 0], [1, 1]]) {
      const x = 16 + a.eyeDx + 1 + dx, y = a.eyeY + 3 + dy;
      for (const px of [x, 31 - x]) if (inMask(m, px, y)) c.set(px, y, "accent");
    }
  }
}

const EGG_SPOTS = [[12, 14], [18, 12], [16, 18], [11, 21], [19, 22], [15, 25]];
const EGG_FRECKLES = [[13, 14], [18, 13], [20, 18], [11, 19], [16, 22], [19, 25]];

function eggPattern(c: Canvas, m: Mask, v: number) {
  const pts = sortedPoints(m);
  if (v === 1) {
    for (const [x, y] of pts) if (y >= 22) c.set(x, y, "light");
  } else if (v === 2) {
    for (const [x, y] of EGG_SPOTS) for (const i of [0, 1]) for (const j of [0, 1])
      if (inMask(m, x + i, y + j)) c.set(x + i, y + j, "accent");
  } else if (v === 3) {
    for (const [x, y] of pts) {
      const z = floorDiv(x, 2) % 2;
      if (y === 18 + z || y === 19 + z || y === 23 + z) c.set(x, y, "accent");
    }
  } else if (v === 4) {
    for (const [x, y] of pts) if (y < 16) c.set(x, y, "accent");
  } else if (v === 5) {
    for (const [x, y] of EGG_FRECKLES) if (inMask(m, x, y)) c.set(x, y, "accent");
  }
}

function shadeBody(c: Canvas, m: Mask) {
  const pts = sortedPoints(m);
  const xs = pts.map(p => p[0]), ys = pts.map(p => p[1]);
  const cx = (Math.min(...xs) + Math.max(...xs)) / 2, cy = (Math.min(...ys) + Math.max(...ys)) / 2;
  for (const [x, y] of pts) {
    if (!inMask(m, x + 1, y + 1) || (!inMask(m, x + 1, y) && y > cy)) {
      if (x >= cx - 1 || y >= cy + 2) {
        if (c.get(x, y)!.role === "base") c.set(x, y, "shade");
      }
    }
  }
  // highlight: middle of the points with minimal x + y (sorted order)
  let best = Infinity;
  for (const [x, y] of pts) best = Math.min(best, x + y);
  const ties = pts.filter(([x, y]) => x + y === best);
  const [x, y] = ties[floorDiv(ties.length - 1, 2)];
  for (const [px, py] of [[x + 2, y + 2], [x + 3, y + 2], [x + 2, y + 3]])
    if (inMask(m, px, py) && c.get(px, py)!.role === "base") c.set(px, py, "white");
}

interface EyeLayout { spr: Sprite; x0: number; y0: number; w: number; h: number; dx: number }
function eyeLayout(v: number, a: Anchors): EyeLayout {
  const spr = EYES[v];
  const w = Math.max(...spr.map(s => s[0])) + 1;
  const h = Math.max(...spr.map(s => s[1])) + 1;
  const dx = Math.max(a.eyeDx, floorDiv(w, 2) + 1);
  return { spr, x0: 16 + dx - floorDiv(w, 2), y0: a.eyeY - floorDiv(h, 2), w, h, dx };
}

function drawEyes(c: Canvas, v: number, a: Anchors) {
  const { spr, x0, y0, w } = eyeLayout(v, a);
  if (v === 7) {
    for (const [x, y, ch] of spr) c.put(13 + x, y0 + y, ROLE[ch], true, true);
    return;
  }
  for (const [x, y, ch] of spr) {
    c.put(x0 + x, y0 + y, ROLE[ch], true, true);
    const lx = EYE_MIRROR[v] ? 31 - (x0 + x) : 31 - (x0 + w - 1) + x;
    c.put(lx, y0 + y, ROLE[ch], true, true);
  }
}

function drawFace(c: Canvas, m: Mask, eyes: number, mood: number, a: Anchors) {
  const { y0, w, h, dx } = eyeLayout(eyes, a);
  const my = y0 + h + (h >= 3 ? 1 : 2);
  const [mx, mouth] = MOODS[mood] ?? MOODS[0];
  for (const [x, y, ch] of mouth) c.put(mx + x, my + y, ROLE[ch]);
  const by = a.eyeY + 2;
  const bx = eyes !== 7 ? 16 + dx + floorDiv(w + 1, 2) + 1 : 21;
  for (const x of [bx, 31 - bx]) if (inMask(m, x, by)) c.put(x, by, "blush");
}

function outline(c: Canvas) {
  const out: boolean[] = new Array(S * S).fill(false);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const p = c.get(x, y);
    if (!p || !p.solid || p.role === "outline") continue;
    for (const [nx, ny] of [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]])
      if (nx >= 0 && nx < S && ny >= 0 && ny < S && !c.has(nx, ny)) out[ny * S + nx] = true;
  }
  for (let i = 0; i < S * S; i++) if (out[i]) c.px[i] = { role: "outline", solid: false, knock: false };
}

const radians = (d: number) => d * (Math.PI / 180.0); // CPython: x * degToRad
function drawAura(v: number, seed: number): [number, number, Role][] {
  if (v === 0) return [];
  const rnd = new Mulberry(mul32(seed, 7) + v); // python: (seed*7+v) & 0xFFFFFFFF; Mulberry masks
  const extra: [number, number, Role][] = [];
  if (v === 1) {
    for (let i = 0; i < 5; i++) {
      const x = rnd.randrange(1, S - 1), y = rnd.randrange(1, 14);
      extra.push([x, y, "white"], [x - 1, y, "accent"], [x + 1, y, "accent"], [x, y - 1, "accent"], [x, y + 1, "accent"]);
    }
  } else if (v === 2) {
    for (let a = 0; a < 360; a += 9) {
      if (floorDiv(a, 9) % 5 >= 3) continue;
      const r = 14.5;
      const x = pyRound(16 + r * Math.cos(radians(a)));
      const y = pyRound(18 + r * 0.85 * Math.sin(radians(a)));
      extra.push([x, y, "light"]);
    }
  } else if (v === 3) {
    const heart = [[0, 0], [2, 0], [0, 1], [1, 1], [2, 1], [1, 2]];
    for (let i = 0; i < 3; i++) {
      const x = rnd.randrange(2, S - 4), y = rnd.randrange(1, 10);
      for (const [dx, dy] of heart) extra.push([x + dx, y + dy, "blush"]);
    }
  }
  return extra;
}

function build(p: Pheno, silhouette: boolean): Canvas {
  const stage = p.stage ?? ADULT;
  const mask = bodyMask(p.body, stage);
  const c = new Canvas();
  if (stage === EGG) {
    for (const [x, y] of sortedPoints(mask)) c.set(x, y, "base");
    eggPattern(c, mask, p.pattern);
    shadeBody(c, mask);
    outline(c);
    return c;
  }
  const a = anchors(mask);
  drawTail(c, p.tail, a, stage);
  for (const [x, y] of sortedPoints(mask)) c.set(x, y, "base");
  drawHead(c, p.head, a, stage);
  for (const [x, y] of sortedPoints(mask)) if (!c.has(x, y)) c.set(x, y, "base");
  applyPattern(c, mask, p.pattern, a);
  shadeBody(c, mask);
  outline(c);
  drawEyes(c, p.eyes, a);
  if (!silhouette) drawFace(c, mask, p.eyes, p.mood ?? 0, a);
  return c;
}

/** 32x32 RGBA, row-major, straight alpha (identical to Python render_raw(p, silhouette).tobytes()). */
export function render(p: Pheno, silhouette = false): Uint8Array {
  const c = build(p, silhouette);
  const buf = new Uint8Array(S * S * 4);
  if (silhouette) {
    for (let i = 0; i < S * S; i++) {
      const px = c.px[i];
      if (!px || px.knock) continue;
      buf[i * 4] = 255; buf[i * 4 + 1] = 255; buf[i * 4 + 2] = 255; buf[i * 4 + 3] = 255;
    }
    return buf;
  }
  const pal = palette(p.palette, p.shift);
  if ((p.stage ?? ADULT) === ADULT) {
    for (const [x, y, role] of drawAura(p.aura, p.seed)) {
      if (x >= 0 && x < S && y >= 0 && y < S && !c.has(x, y)) {
        const col = pal[role], i = (y * S + x) * 4;
        buf[i] = col[0]; buf[i + 1] = col[1]; buf[i + 2] = col[2]; buf[i + 3] = 255;
      }
    }
  }
  for (let i = 0; i < S * S; i++) {
    const px = c.px[i];
    if (!px) continue;
    const col = pal[px.role];
    buf[i * 4] = col[0]; buf[i * 4 + 1] = col[1]; buf[i * 4 + 2] = col[2]; buf[i * 4 + 3] = 255;
  }
  return buf;
}
