// Independent TypeScript port of art/render.py `render_raw(p, silhouette)`.
// Purpose: prove the algorithm is portable (rounding, colorsys, ordering) before
// trusting the Swift port (MixlingsKit/Sources/MixlingsArt), which mirrors this file.
// Run: node art/ts-port/check.ts

import * as T from "./living-tables.ts";

export const S = 32;
export const EGG = 0, BABY = 1, TEEN = 2, ADULT = 3;

export interface Pheno {
  body: number; eyes: number; head: number; pattern: number; tail: number;
  palette: number; aura: number; shift: number; seed: number;
  mood?: number;  // 0 neutral (small smile), 1 "o", 2 hungry wobble; default 0
  stage?: number; // 0 egg, 1 baby, 2 teen, 3 adult; default 3
  weather?: number; // living world: 0 none, 1 rain, 2 heat, 3 snow, 4 wind, 5 night
  item?: number;    // care item 0..9 (see render.py)
  alive?: number;   // widget-alive frame: 0 none, 1 charging, 2 low power, 3 morning
  breath?: number;  // breathing phase 0..7 (inhale 0-3, exhale 4-7); default -1 = off
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

function bodyShape(v: number, stage: number): Mask {
  if (stage === EGG) return rowsMask(...EGG_ROWS);
  return stage === ADULT ? bodyAdult(v) : stage === TEEN ? bodyTeen(v) : bodyBaby(v);
}

/** Breathing: inflate a mask (new mask, not image scaling). Feet stay put, rows above the
 *  middle rise by dh (the middle row fills the gap), then every row widens by `side`. */
function growMask(m: Mask, side: number, dh: number): Mask {
  const pts = sortedPoints(m);
  const top = Math.min(...pts.map(p => p[1])), bot = Math.max(...pts.map(p => p[1]));
  const ref = top + floorDiv(bot - top, 2);
  const mid = newMask();
  const add = (o: Mask, x: number, y: number) => { if (x >= 0 && x < S && y >= 0 && y < S) o[y * S + x] = true; };
  for (const [x, y] of pts) {
    if (y >= ref) add(mid, x, y);
    if (y <= ref) add(mid, x, y - dh);
    if (y === ref) for (let k = 1; k < dh; k++) add(mid, x, y - k);
  }
  if (!side) return mid;
  const out = newMask();
  for (const [x, y] of sortedPoints(mid)) for (let d = -side; d <= side; d++) add(out, x + d, y);
  return out;
}

function bodyMask(v: number, stage: number, level = 0): Mask {
  let m = bodyShape(v, stage);
  if (level) m = growMask(m, T.BREATH_GROW[level][0], T.BREATH_GROW[level][1]);
  if (stage === EGG) return m;
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
const ROLE: Record<string, Role> = { B: "base", S: "shade", A: "accent", L: "light", K: "eye", W: "white", M: "mouth", a: "accent", R: "blush" };

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
  8: sprite(["..K", "KK.", "..K"]),      // squint (heat) - state eyes, never genes
  9: sprite(["K..K", ".KK."]),           // closed, asleep
  10: sprite(["K....K", ".KKKK."]),      // closed cyclops
  11: sprite(["KKKK"]),                  // soft half-closed lid (breathing)
  12: sprite(["KKKKKK"]),                // soft half-closed cyclops
};
const EYE_MIRROR: Record<number, boolean> = { 0: false, 1: false, 2: true, 3: true, 4: false, 5: false, 6: false, 7: false, 8: true, 9: true, 10: false, 11: true, 12: false };
const CYCLOPS_EYES = [7, 10, 12];
const MOODS: Record<number, [number, Sprite]> = {
  0: [14, sprite(["M..M", ".MM."])],
  1: [14, sprite([".MM.", "M..M", ".MM."])],
  2: [13, sprite([".M..M.", "M.MM.M"])],
  3: [14, sprite([".MM.", "MRRM", "MRRM", ".MM."])], // big yawn (wind-down)
  4: [14, sprite([".MM.", "MRRM", ".MM."])],         // small yawn
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
/** Wind: rows above refY lean right by (refY - y + 1) // 2. */
function stampBlown(c: Canvas, x0: number, y0: number, rows: string[], refY: number) {
  for (const [x, y, ch] of sprite(rows)) {
    const yy = y0 + y;
    const dx = yy < refY ? floorDiv(refY - yy + 1, 2) : 0;
    c.put(x0 + x + dx, yy, ROLE[ch], ch !== "a");
  }
}
function drawHead(c: Canvas, v: number, a: Anchors, stage: number, wind = false) {
  const part = HEADS[stage]?.[v];
  if (!part) return;
  if (wind) stampBlown(c, part[0], a.top + part[1], part[2], a.top);
  else stamp(c, part[0], a.top + part[1], part[2]);
}
function drawTail(c: Canvas, v: number, a: Anchors, stage: number, wind = false) {
  const part = TAILS[stage]?.[v];
  if (!part) return;
  if (wind) stampBlown(c, a.tailX + part[0], a.tailY + part[1], part[2], a.tailY);
  else stamp(c, a.tailX + part[0], a.tailY + part[1], part[2]);
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
  if (CYCLOPS_EYES.includes(v)) {
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
  const bx = !CYCLOPS_EYES.includes(eyes) ? 16 + dx + floorDiv(w + 1, 2) + 1 : 21;
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

const breathOf = (p: Pheno) => p.breath ?? -1;
const breathLevel = (p: Pheno) => breathOf(p) >= 0 ? T.BREATH_LEVEL[breathOf(p) % 8] : 0;
/** The body mask the creature is drawn with (breathing inflates it). */
const creatureMask = (p: Pheno) => bodyMask(p.body, p.stage ?? ADULT, breathLevel(p));
/** Inhale softly closes the eyes: level 1 half-closed, level 2 closed. */
function breathEyes(eyes: number, level: number): number {
  if (level === 0 || eyes === 9 || eyes === 10) return eyes;
  const cyc = CYCLOPS_EYES.includes(eyes);
  if (level === 1) return cyc ? 12 : 11;
  return cyc ? 10 : 9;
}

function build(p: Pheno, silhouette: boolean, face?: [number, number]): Canvas {
  const stage = p.stage ?? ADULT;
  const mask = creatureMask(p);
  const c = new Canvas();
  if (stage === EGG) {
    for (const [x, y] of sortedPoints(mask)) c.set(x, y, "base");
    eggPattern(c, mask, p.pattern);
    shadeBody(c, mask);
    outline(c);
    return c;
  }
  const a = anchors(mask);
  let eyes = p.eyes, mood = p.mood ?? 0, wind = false;
  if (face) [eyes, mood] = face;
  else if (!silhouette) { [eyes, mood] = stateFace(p); wind = stateWeather(p)[0] === WIND; }
  drawTail(c, p.tail, a, stage, wind);
  for (const [x, y] of sortedPoints(mask)) c.set(x, y, "base");
  drawHead(c, p.head, a, stage, wind);
  for (const [x, y] of sortedPoints(mask)) if (!c.has(x, y)) c.set(x, y, "base");
  // breathing: patterns stay put on the resting body; freckles follow the face
  const pa = breathOf(p) < 0 || p.pattern === 5 ? a : anchors(bodyMask(p.body, stage));
  applyPattern(c, mask, p.pattern, pa);
  shadeBody(c, mask);
  outline(c);
  const faceEyes = eyes;
  if (!face && breathOf(p) >= 0) eyes = breathEyes(eyes, breathLevel(p));
  drawEyes(c, eyes, a);
  if (!silhouette) drawFace(c, mask, faceEyes, mood, a);
  return c;
}

/** 32x32 RGBA, row-major, straight alpha (identical to Python render_raw(p, silhouette).tobytes()). */
export function render(p: Pheno, silhouette = false): Uint8Array {
  const buf = new Uint8Array(S * S * 4);
  if (silhouette) {
    const c = build(p, true);
    for (let i = 0; i < S * S; i++) {
      const px = c.px[i];
      if (!px || px.knock) continue;
      buf[i * 4] = 255; buf[i * 4 + 1] = 255; buf[i * 4 + 2] = 255; buf[i * 4 + 3] = 255;
    }
    return buf;
  }
  for (const [x, y, col] of creatureLayers(p)) {
    const i = (y * S + x) * 4;
    buf[i] = col[0]; buf[i + 1] = col[1]; buf[i + 2] = col[2]; buf[i + 3] = 255;
  }
  return buf;
}

// ============================================================ living world (render.py)
// docs/living-world-spec.md §1 weather, §8 jump rope, §9 pair life, §13 alive.
export const NONE = 0, RAIN = 1, HEAT = 2, SNOW = 3, WIND = 4, NIGHT = 5;
const I_UMBRELLA = 1, I_BOTTLE = 2, I_FAN = 3, I_HAT = 4, I_SCARF = 5, I_BEANIE = 6,
  I_BLANKET = 7, I_ROPE = 8, I_JUICE = 9;
const A_CHARGING = 1, A_LOWPOWER = 2, A_MORNING = 3;
const EYE_SQUINT = 8, EYE_CLOSED = 9, EYE_CLOSED_CYCLOPS = 10;
const LW = T.LW;
type Paint = [number, number, RGB];
const imod = (a: number, b: number) => ((a % b) + b) % b;

function lwSprite(x0: number, y0: number, rows: string[], out: Paint[], cmap: Record<string, RGB> = LW) {
  for (const [x, y, ch] of sprite(rows)) out.push([x0 + x, y0 + y, cmap[ch]]);
}
function rowExt(m: Mask, y: number): [number, number] {
  const xs = sortedPoints(m).filter(p => p[1] === y).map(p => p[0]);
  return xs.length ? [Math.min(...xs), Math.max(...xs)] : [16, 15];
}

function stateWeather(p: Pheno): [number, number] {
  let w = p.weather ?? 0, it = p.item ?? 0;
  const al = p.alive ?? 0;
  if (al === A_CHARGING) it = I_JUICE;
  else if (al === A_LOWPOWER) { w = NIGHT; it = I_BLANKET; }
  return [w, it];
}
function stateFace(p: Pheno): [number, number] {
  const [w] = stateWeather(p);
  const cyc = p.eyes === 7, al = p.alive ?? 0;
  if (w === NIGHT) return [cyc ? EYE_CLOSED_CYCLOPS : EYE_CLOSED, 0];
  if (al === A_MORNING) return [cyc ? 7 : 3, 1];
  if (al === A_CHARGING) return [cyc ? 7 : 3, 0];
  if (w === HEAT) return [cyc ? 7 : EYE_SQUINT, 1];
  if (w === RAIN) return [cyc ? 7 : 3, 0];
  if (w === SNOW) return [p.eyes, 2];
  return [p.eyes, p.mood ?? 0];
}

/** Integer parabola from (x0, hy) to (x1, hy) through the apex; vertical gaps filled. */
function ropeArc(x0: number, x1: number, hy: number, apex: number, out: Paint[], rgb: RGB) {
  const half = floorDiv(x1 - x0, 2), cx = x0 + half;
  let prev: number | null = null;
  for (let x = x0; x <= x1; x++) {
    const d = x - cx;
    const y = hy + floorDiv((apex - hy) * (half * half - d * d), half * half);
    out.push([x, y, rgb]);
    if (prev !== null && Math.abs(y - prev) > 1) {
      const step = y > prev ? 1 : -1;
      for (let yy: number = prev + step; yy !== y; yy += step) out.push([x, yy, rgb]);
    }
    prev = y;
  }
}

function mouthY(p: Pheno, a: Anchors): number {
  const [eyes] = stateFace(p);
  const { y0, h } = eyeLayout(eyes, a);
  return y0 + h + (h >= 3 ? 1 : 2);
}

function itemLayer(p: Pheno, it: number, m: Mask, a: Anchors, front: Paint[], behind: Paint[]) {
  const top = a.top, bottom = a.bottom, mid = a.midY;
  const [lx, rx] = rowExt(m, mid);
  if (it === I_UMBRELLA) {
    const y0 = Math.max(0, top - 11);
    lwSprite(10, y0, T.UMBRELLA, front);
    const hx = Math.min(rx, 24);
    for (let y = y0 + 6; y < mid + 2; y++) front.push([hx, y, LW["N"]]);
    front.push([hx - 1, mid + 2, LW["N"]], [hx - 2, mid + 1, LW["N"]]);
  } else if (it === I_BOTTLE) {
    lwSprite(rx - 1, mid - 2, T.BOTTLE, front);
  } else if (it === I_FAN) {
    lwSprite(Math.max(0, lx - 7), mid - 7, T.FAN, front);
  } else if (it === I_HAT) {
    lwSprite(8, top - 4, T.SUN_HAT, front);
  } else if (it === I_BEANIE) {
    lwSprite(10, top - 4, T.BEANIE, front);
  } else if (it === I_SCARF) {
    const sy = a.eyeY + 5;
    for (const y of [sy, sy + 1]) {
      const [l, r] = rowExt(m, y);
      for (let x = l - 1; x < r + 2; x++) {
        const ch = imod(x + y, 4) === 0 ? "w" : (y === sy + 1 ? "R" : "r");
        front.push([x, y, LW[ch]]);
      }
      front.push([l - 2, y, LW["o"]], [r + 2, y, LW["o"]]);
    }
    const [l, r] = rowExt(m, sy + 1);
    for (let x = l - 1; x < r + 2; x++) front.push([x, sy + 2, LW["o"]]);
    const tx = r - 4;
    const tail = ["orro", "orwo", "orro", "orRo"].slice(0, Math.max(1, Math.min(4, bottom - sy - 2))).concat(["oooo"]);
    tail.forEach((row, i) => lwSprite(tx, sy + 2 + i, [row], front)); // clipped to the body
  } else if (it === I_BLANKET) {
    const y0 = mid + 2;
    for (let y = y0; y < bottom + 3; y++) {
      const l = lx - 2, r = rx + 2;
      for (let x = l; x <= r; x++) {
        if (y === y0 || x === l || x === r || y === bottom + 2) {
          if (!(y === y0 && (x === l || x === r))) front.push([x, y, LW["o"]]);
          continue;
        }
        let ch = (floorDiv(x - l, 3) + floorDiv(y - y0, 3)) % 2 === 0 ? "p" : "P";
        if (y === y0 + 1) ch = "w";
        front.push([x, y, LW[ch]]);
      }
    }
  } else if (it === I_ROPE) {
    const hl = lx - 3, hr = rx + 2;
    lwSprite(hl, mid - 1, T.HANDLE, front);
    lwSprite(hr, mid - 1, T.HANDLE, front);
    ropeArc(hl, hr + 1, mid - 1, 0, behind, LW["M"]);
  } else if (it === I_JUICE) {
    lwSprite(18, mouthY(p, a), T.JUICE, front);
  }
}

function shiftCanvas(c: Canvas, dx: number, dy: number): Canvas {
  const out = new Canvas();
  for (let x = 0; x < S; x++) for (let y = 0; y < S; y++) {
    const px = c.get(x, y);
    if (!px) continue;
    const nx = x + dx, ny = y + dy;
    if (nx >= 0 && nx < S && ny >= 0 && ny < S) out.px[ny * S + nx] = px;
  }
  return out;
}
/** Morning stretch: rows <= refY move up one, row refY is kept twice. */
function stretchCanvas(c: Canvas, refY: number): Canvas {
  const out = new Canvas();
  for (let i = 0; i < S * S; i++) if (c.px[i] && Math.floor(i / S) >= refY) out.px[i] = c.px[i];
  for (let x = 0; x < S; x++) for (let y = 0; y < S; y++) {
    const px = c.get(x, y);
    if (px && y <= refY && y - 1 >= 0) out.px[(y - 1) * S + x] = px;
  }
  return out;
}

/** Weather / care item / alive layers. */
function living(p: Pheno, canvas: Canvas): [Canvas, Paint[], Paint[]] {
  const [w, it] = stateWeather(p);
  const al = p.alive ?? 0;
  if (w === NONE && it === 0 && al === 0) return [canvas, [], []];
  let behind: Paint[] = [], front: Paint[] = [];
  if (w === RAIN) {
    for (const [x, y] of T.RAIN_DROPS) {
      if (it === I_UMBRELLA && x >= 4 && x <= 28 && y <= 20) continue;
      behind.push([x, y, LW["c"]], [x, y + 1, LW["t"]], [x, y + 2, LW["b"]]);
    }
  } else if (w === SNOW) {
    for (const [x, y] of T.SNOW_FLAKES) lwSprite(x - 1, y - 1, T.FLAKE, behind);
  } else if (w === WIND) {
    for (const [x, y, n] of T.WIND_LINES) for (let i = 0; i < n; i++) behind.push([x + i, y, LW["q"]]);
    lwSprite(27, 5, T.LEAF, behind);
  } else if (w === HEAT) {
    lwSprite(0, 0, T.SUN, behind);
  } else if (w === NIGHT && it !== I_BLANKET) {
    lwSprite(1, 1, T.MOON, behind);
  }
  const stage = p.stage ?? ADULT;
  if (stage === EGG) {
    if (w === NIGHT) lwSprite(22, 3, T.ZZZ_ROWS, front);
    return [canvas, behind, front];
  }
  const m = creatureMask(p);
  const a = anchors(m);
  let bodyFront: Paint[] = [];
  const bodyBehind: Paint[] = [];
  itemLayer(p, it, m, a, bodyFront, bodyBehind);
  const [lx, rx] = rowExt(m, a.midY);
  if (w === RAIN) {
    for (const [dx, dy] of T.SHEEN) {
      const x = 16 + dx, y = a.midY + dy;
      if (inMask(m, x, y) && inMask(m, x, y + 1)) bodyFront.push([x, y, LW["w"]], [x, y + 1, LW["t"]]);
    }
  } else if (w === HEAT) {
    lwSprite(16 + a.eyeDx + 3, a.eyeY - 6, T.SWEAT, bodyFront);
  } else if (w === SNOW && it !== I_BEANIE && it !== I_HAT) {
    const pts = sortedPoints(m);
    for (let x = 12; x < 20; x++) {
      const ys = pts.filter(q => q[0] === x).map(q => q[1]);
      if (ys.length) {
        const t = Math.min(...ys);
        bodyFront.push([x, t, LW["w"]]);
        if (x >= 14 && x <= 17) bodyFront.push([x, t + 1, LW["w"]]);
      }
    }
  }
  if (w === NIGHT) lwSprite(22, Math.max(0, a.top - 8), T.ZZZ_ROWS, front);
  if (al === A_CHARGING) lwSprite(25, Math.max(0, a.top - 6), T.BOLT, front);
  if (al === A_MORNING) lwSprite(24, Math.max(0, a.top - 9), T.BANG, front);
  let dx = 0, dy = 0;
  if (w === RAIN) {
    dy = -1;
    const b = a.bottom + 1;
    for (let x = lx - 1; x < rx + 2; x++) behind.push([x, b + 1, LW["t"]]);
    for (let x = lx + 1; x < rx; x++) behind.push([x, b + 2, LW["c"]]);
    behind.push([lx - 3, b - 1, LW["t"]], [lx - 4, b - 2, LW["c"]], [rx + 3, b - 1, LW["t"]], [rx + 4, b - 2, LW["c"]]);
  } else if (w === SNOW) {
    dx = 1;
    for (const y of [a.midY - 1, a.midY + 1]) behind.push([lx - 2, y, LW["q"]], [rx + 4, y, LW["q"]]);
    behind.push([lx - 3, a.midY, LW["q"]], [rx + 5, a.midY, LW["q"]]);
  }
  if (al === A_MORNING && w !== NIGHT) {
    dx = 0; dy = 0;
    canvas = stretchCanvas(canvas, a.midY);
    bodyFront = bodyFront.map(([x, y, c]) => [x, y <= a.midY ? y - 1 : y, c] as Paint);
    front.push([lx - 2, a.top - 1, LW["q"]], [lx - 3, a.top - 2, LW["q"]], [rx + 2, a.top - 1, LW["q"]], [rx + 3, a.top - 2, LW["q"]]);
  } else if (dx || dy) {
    canvas = shiftCanvas(canvas, dx, dy);
  }
  front = bodyFront.map(([x, y, c]) => [x + dx, y + dy, c] as Paint).concat(front);
  behind = behind.concat(bodyBehind.map(([x, y, c]) => [x + dx, y + dy, c] as Paint));
  return [canvas, behind, front];
}

/** Colour creature as an ordered paint list (later entries win), 32x32 coordinates. */
export function creatureLayers(p: Pheno, face?: [number, number], plain = false, aura = true): Paint[] {
  let canvas = build(p, false, face);
  let behind: Paint[] = [], front: Paint[] = [];
  if (!plain) [canvas, behind, front] = living(p, canvas);
  const pal = palette(p.palette, p.shift);
  const out: Paint[] = [];
  const inS = (x: number, y: number) => x >= 0 && x < S && y >= 0 && y < S;
  if ((p.stage ?? ADULT) === ADULT && aura)
    for (const [x, y, role] of drawAura(p.aura, p.seed)) if (inS(x, y) && !canvas.has(x, y)) out.push([x, y, pal[role]]);
  for (const [x, y, rgb] of behind) if (inS(x, y) && !canvas.has(x, y)) out.push([x, y, rgb]);
  for (let x = 0; x < S; x++) for (let y = 0; y < S; y++) { const px = canvas.get(x, y); if (px) out.push([x, y, pal[px.role]]); }
  for (const [x, y, rgb] of front) if (inS(x, y)) out.push([x, y, rgb]);
  return out;
}

// ------------------------------------------------------------ scenes (64x48)
export const RW = 64, RH = 48;
export const DAY = 0, NIGHT_TIME = 1;
const SC_CHESS = 0, SC_PAINT = 1, SC_CHAT = 2, SC_NAP = 3, SC_STARS = 4, SC_BREAKFAST = 5, SC_HOMEWORK = 6;

export class Img {
  w: number; h: number; px: (RGB | null)[];
  constructor(w: number, h: number) { this.w = w; this.h = h; this.px = new Array(w * h).fill(null); }
  set(x: number, y: number, rgb: RGB, tint: RGB | null = null) {
    if (x >= 0 && x < this.w && y >= 0 && y < this.h) {
      if (tint) rgb = [floorDiv(rgb[0] * tint[0], 256), floorDiv(rgb[1] * tint[1], 256), floorDiv(rgb[2] * tint[2], 256)];
      this.px[y * this.w + x] = rgb;
    }
  }
  spr(x0: number, y0: number, rows: string[], tint: RGB | null = null, cmap: Record<string, RGB> = LW) {
    for (const [x, y, ch] of sprite(rows)) this.set(x0 + x, y0 + y, cmap[ch], tint);
  }
  get(x: number, y: number): RGB | null { return this.px[y * this.w + x]; }
  creature(layers: Paint[], ox: number, oy: number, mirror = false, tint: RGB | null = null) {
    for (const [x, y, rgb] of layers) this.set(ox + (mirror ? 31 - x : x), oy + y, rgb, tint);
  }
  rgba(): Uint8Array {
    const buf = new Uint8Array(this.w * this.h * 4);
    this.px.forEach((c, i) => { if (c) { buf[i * 4] = c[0]; buf[i * 4 + 1] = c[1]; buf[i * 4 + 2] = c[2]; buf[i * 4 + 3] = 255; } });
    return buf;
  }
}

const WALL_Y1 = 32, FLOOR_Y0 = 34;
const WIN_X0 = 24, WIN_Y0 = 3, WIN_X1 = 39, WIN_Y1 = 16;
const LAMP_LIT: Record<string, RGB> = { ...LW, y: LW["l"] };

function skyKind(tod: number, weather: number): string {
  const night = tod === NIGHT_TIME || weather === NIGHT;
  if (weather === RAIN) return night ? "rain_night" : "rain";
  if (weather === SNOW) return "snow";
  return night ? "night" : "day";
}

function drawWindow(im: Img, kind: string, weather: number) {
  const [top, bot] = T.SKY[kind];
  for (let y = WIN_Y0 + 1; y < WIN_Y1; y++) {
    const c = y < floorDiv(WIN_Y0 + WIN_Y1, 2) ? top : bot;
    for (let x = WIN_X0 + 1; x < WIN_X1; x++) im.set(x, y, c);
  }
  if (kind === "day") {
    im.spr(27, 5, T.CLOUD);
    if (weather === HEAT) im.spr(32, 4, ["..y..", ".yyy.", "yyyyy", ".yyy.", "..y.."]);
    if (weather === WIND) { im.spr(33, 11, T.LEAF); im.spr(29, 8, [".g", "G."]); }
  } else if (kind === "night") {
    for (const [x, y] of T.WIN_STARS) im.set(x, y, [255, 244, 200]);
    im.spr(34, 9, T.MOON);
  } else if (kind.startsWith("rain")) {
    for (const [x, y] of T.WIN_RAIN) { im.set(x, y, [200, 214, 236]); im.set(x - 1, y + 1, [200, 214, 236]); }
  } else {
    for (const [x, y] of T.WIN_SNOW) im.set(x, y, [255, 255, 255]);
  }
  const frame: RGB = (kind === "day" || kind === "rain" || kind === "snow") ? [255, 255, 255] : [196, 188, 228];
  const mx = floorDiv(WIN_X0 + WIN_X1, 2), my = floorDiv(WIN_Y0 + WIN_Y1, 2);
  for (let x = WIN_X0; x <= WIN_X1; x++) { im.set(x, WIN_Y0, LW["o"]); im.set(x, WIN_Y1, LW["o"]); im.set(x, my, frame); }
  for (let y = WIN_Y0; y <= WIN_Y1; y++) {
    im.set(WIN_X0, y, LW["o"]); im.set(WIN_X1, y, LW["o"]);
    if (y > WIN_Y0 && y < WIN_Y1) im.set(mx, y, frame);
  }
  for (let x = WIN_X0 - 1; x < WIN_X1 + 2; x++) { im.set(x, WIN_Y1 + 1, LW["N"]); im.set(x, WIN_Y1 + 2, LW["o"]); }
}

function drawRoomBg(im: Img, night: boolean) {
  const k = night ? 1 : 0;
  for (let y = 0; y <= WALL_Y1; y++) for (let x = 0; x < RW; x++)
    im.set(x, y, (x % 6 === 0 || x % 6 === 1) ? T.ROOM["stripe"][k] : T.ROOM["wall"][k]);
  for (let x = 0; x < RW; x++) im.set(x, WALL_Y1 + 1, T.ROOM["base"][k]);
  for (let y = FLOOR_Y0; y < RH; y++) for (let x = 0; x < RW; x++) {
    let c = T.ROOM["floor"][k];
    if ((y - FLOOR_Y0) % 5 === 4 || (x + 7 * floorDiv(y - FLOOR_Y0, 5)) % 21 === 0) c = T.ROOM["plank"][k];
    else if (y === FLOOR_Y0) c = T.ROOM["floor_hi"][k];
    im.set(x, y, c);
  }
}

function drawFurniture(im: Img, slots: number[], night: boolean) {
  const t = night ? T.NIGHT_TINT : null;
  if (slots[5]) {
    let prev: number | null = null;
    for (let x = 2; x < 62; x++) {
      const d = x - 32;
      const y = 1 + floorDiv(3 * (900 - d * d), 900);
      im.set(x, y, LW["N"], t);
      if (prev !== null && y !== prev) im.set(x, prev, LW["N"], t);
      prev = y;
      if (x % 6 === 5) {
        const c = LW[T.BULBS[floorDiv(x, 6) % 5]];
        im.set(x, y + 1, c, night ? null : t);
        im.set(x, y + 2, night ? LW["l"] : c, night ? null : t);
      }
    }
  }
  if (slots[0]) im.spr(4, 7, T.PICTURE, t);
  if (slots[1]) im.spr(46, 6, T.SHELF, t);
  if (slots[4]) {
    for (let y = 39; y < 47; y++) for (let x = 10; x < 54; x++) {
      const dx = (x - 32) * 4, dy = (y - 43) * 22, r = dx * dx + dy * dy;
      if (r <= 88 * 88) {
        const c = r > 74 * 74 ? "M" : (floorDiv(Math.abs(x - 32), 4) % 2 === 0 ? "m" : "w");
        im.set(x, y, LW[c], t);
      }
    }
  }
  if (slots[2]) im.spr(0, 27, T.PLANT, t);
  if (slots[3]) { if (night) im.spr(55, 12, T.LAMP, null, LAMP_LIT); else im.spr(55, 12, T.LAMP, t); }
}

function sceneFaces(scene: number, pa: Pheno, pb: Pheno): [[number, number], [number, number]] {
  const f = (p: Pheno, eyes: number, mood: number): [number, number] => {
    if (p.eyes === 7 && eyes !== 7 && eyes !== EYE_CLOSED_CYCLOPS) eyes = 7;
    if (p.eyes === 7 && eyes === EYE_CLOSED) eyes = EYE_CLOSED_CYCLOPS;
    return [eyes, mood];
  };
  if (scene === SC_CHESS) return [f(pa, pa.eyes, 1), f(pb, pb.eyes, 0)];
  if (scene === SC_PAINT) return [f(pa, 3, 0), f(pb, pb.eyes, 1)];
  if (scene === SC_CHAT) return [f(pa, pa.eyes, 1), f(pb, 3, 0)];
  if (scene === SC_NAP) return [f(pa, EYE_CLOSED, 0), f(pb, EYE_CLOSED, 0)];
  if (scene === SC_STARS) return [f(pa, 4, 1), f(pb, 4, 1)];
  if (scene === SC_BREAKFAST) return [f(pa, 3, 0), f(pb, 3, 0)];
  return [f(pa, pa.eyes, 0), f(pb, 2, 1)];
}

const pairSeed = (pa: Pheno, pb: Pheno, scene: number) =>
  (mul32(pa.seed, 31) + mul32(pb.seed, 7) + scene * 101) >>> 0;

function drawSceneProps(im: Img, scene: number, pa: Pheno, pb: Pheno, night: boolean) {
  const t = night ? T.NIGHT_TINT : null;
  if (scene === SC_CHESS) im.spr(24, 30, T.CHESS_TABLE, t);
  else if (scene === SC_PAINT) {
    im.spr(25, 21, T.EASEL, t);
    const qa = palette(pa.palette, pa.shift), qb = palette(pb.palette, pb.shift);
    const cols = [qa.base, qb.base, qa.accent, qb.accent];
    for (const [x, y, i] of T.EASEL_DABS) im.set(25 + x, 21 + y, cols[i], t);
    im.spr(36, 41, T.PAINT_POT, t);
  } else if (scene === SC_CHAT) {
    const rnd = new Mulberry(pairSeed(pa, pb, scene));
    const a = rnd.int(T.EMOTES.length);
    let b = rnd.int(T.EMOTES.length - 1);
    if (b >= a) b++;
    im.spr(15, 2, T.BUBBLE);
    im.spr(18, 3, T.EMOTES[a]);
    im.spr(38, 2, T.BUBBLE.map(r => [...r].reverse().join("")));
    im.spr(41, 3, T.EMOTES[b]);
  } else if (scene === SC_NAP) {
    const Y = 33;
    for (let y = Y; y < 45; y++) for (let x = 4; x < 60; x++) {
      if (y === Y || y === 44 || x === 4 || x === 59) {
        if (!((y === Y || y === 44) && (x === 4 || x === 59))) im.set(x, y, LW["o"], t);
        continue;
      }
      const c = y === Y + 1 ? "w" : ((floorDiv(x - 4, 4) + floorDiv(y - Y, 4)) % 2 === 0 ? "p" : "P");
      im.set(x, y, LW[c], t);
    }
    im.spr(28, 20, T.ZZZ_ROWS);
  } else if (scene === SC_STARS) im.spr(28, 22, T.TELESCOPE, t);
  else if (scene === SC_BREAKFAST) {
    im.spr(24, 30, T.BREAKFAST_TABLE, t);
    im.spr(25, 29, T.PLATE_FOOD, t);
    im.spr(32, 29, T.EGG_PLATE, t);
  } else if (scene === SC_HOMEWORK) im.spr(24, 28, T.DESK, null, night ? LAMP_LIT : LW);
}

/** 64x48 RGBA room (python render_room(...).tobytes()). */
export function renderRoom(pair: [Pheno, Pheno], scene: number, timeOfDay = DAY, weather = NONE,
  furniture: number[] = [1, 1, 1, 1, 1, 1]): Uint8Array {
  const [pa, pb] = pair;
  if (scene === SC_STARS) timeOfDay = NIGHT_TIME;
  const night = timeOfDay === NIGHT_TIME || weather === NIGHT;
  const im = new Img(RW, RH);
  drawRoomBg(im, night);
  drawWindow(im, skyKind(timeOfDay, weather), weather);
  drawFurniture(im, furniture, night);
  const [fa, fb] = sceneFaces(scene, pa, pb);
  const ct = night ? T.CREATURE_NIGHT : null;
  const oy = 12 + (scene === SC_NAP ? 2 : 0);
  im.creature(creatureLayers(pa, fa, true, false), 0, oy, true, ct);
  im.creature(creatureLayers(pb, fb, true, false), 32, oy, false, ct);
  drawSceneProps(im, scene, pa, pb, night);
  return im.rgba();
}

// ------------------------------------------------------------ jump rope
const JR_TRIP = 4, JR_CHEER = 5, YARD_GROUND = 40;

function drawYard(im: Img) {
  const Y = T.YARD;
  const fenceCol = (x: number) => [1, 2, 3, 4].includes(x % 6);
  for (let y = 0; y < RH; y++) for (let x = 0; x < RW; x++) {
    let c: RGB;
    if (y < 14) c = Y["sky0"];
    else if (y < 24) c = Y["sky1"];
    else if (y < 30) c = Y["sky2"];
    else if (y < YARD_GROUND - 6) {
      c = fenceCol(x) ? Y["fence"] : Y["sky2"];
      if ((y === 31 || y === 32) && !fenceCol(x)) c = Y["fence_s"];
    } else if (y < YARD_GROUND - 2) c = (x + y) % 3 === 0 ? Y["grass_d"] : Y["grass"];
    else c = y > YARD_GROUND - 2 ? Y["grass"] : Y["grass_l"];
    im.set(x, y, c);
  }
  for (let x = 0; x < RW; x++) {
    if (x % 6 === 2 || x % 6 === 3) im.set(x, 29, Y["fence"]);
    if (x % 6 === 4) for (let y = 30; y < YARD_GROUND - 6; y++) im.set(x, y, Y["fence_s"]);
  }
  for (const [x, y] of T.YARD_CLOUDS) im.spr(x, y, T.BIG_CLOUD);
  im.spr(54, 2, T.SUN);
  for (const [x, y] of T.YARD_TUFTS) {
    im.set(x, y, Y["grass_d"]); im.set(x + 1, y - 1, Y["grass_d"]); im.set(x + 2, y, Y["grass_d"]);
  }
  for (const [x, y, c] of T.YARD_FLOWERS) {
    im.spr(x - 1, y - 1, [".c.", "cyc", ".c."], null, { ...LW, c: LW[c], y: c !== "y" ? LW["y"] : LW["w"] });
    im.set(x, y + 1, LW["G"]);
  }
}

/** 64x48 RGBA jump-rope frame 0..5 (python render_jump_rope(p, frame).tobytes()). */
export function renderJumpRope(p: Pheno, frame: number): Uint8Array {
  const im = new Img(RW, RH);
  drawYard(im);
  const m = creatureMask(p);
  const a = anchors(m);
  const [lx, rx] = rowExt(m, a.midY);
  const ox = 16, baseOy = YARD_GROUND + 2 - (a.bottom + 1);
  let phase: number, h: number, face: [number, number];
  if (frame === JR_TRIP) { phase = 2; h = 0; face = [p.eyes === 7 ? 7 : EYE_SQUINT, 1]; }
  else if (frame === JR_CHEER) { phase = 0; h = 3; face = [p.eyes === 7 ? 7 : 3, 1]; }
  else {
    const [ph, pose] = T.JR_LOOP[imod(frame, 4)];
    phase = ph; h = T.JR_HEIGHT[pose]; face = [p.eyes, pose === 2 ? 1 : 0];
  }
  const oy = baseOy - h;
  const sw = floorDiv(rx - lx, 2) - h, cx = ox + 16;
  for (let x = cx - sw; x < cx + sw; x++) im.set(x, YARD_GROUND + 2, T.YARD["shadow"]);
  const hl = ox + lx - 3, hr = ox + rx + 2, hy = oy + a.midY - 1;
  const rope = LW["R"];
  let behind: Paint[] = [], front: Paint[] = [];
  if (frame === JR_TRIP) {
    const fy = YARD_GROUND + 1;
    ropeArc(hl, hr + 1, hy + 2, fy + 2, front, rope);
    for (const [x, y] of [[cx - 6, fy - 1], [cx - 5, fy - 2], [cx + 4, fy - 1], [cx + 5, fy - 2]]) front.push([x, y, rope]);
  } else if (phase === 0) ropeArc(hl, hr + 1, hy, Math.max(1, oy + a.top - 8), front, rope);
  else if (phase === 1) ropeArc(hl, hr + 1, hy, oy + a.midY + 5, front, rope);
  else if (phase === 2) ropeArc(hl, hr + 1, hy, YARD_GROUND + 3, front, rope);
  else ropeArc(hl, hr + 1, hy, Math.max(1, oy + a.top - 5), behind, rope);
  behind = behind.concat(behind.map(([x, y, c]) => [x, y + 1, c] as Paint));
  front = front.concat(front.map(([x, y, c]) => [x, y + 1, c] as Paint));
  for (const [x, y, c] of behind) im.set(x, y, c);
  let layers = creatureLayers(p, face, true, false);
  if (frame === JR_TRIP) {
    layers = layers.map(([x, y, c]) => [y < a.midY ? x - 1 : x, y, c] as Paint);
    im.creature(layers, ox, oy);
    for (const [dx, dy] of [[-2, -4], [3, -6], [8, -4]]) im.spr(ox + 16 + dx - 1, oy + a.top + dy - 1, T.DIZZY);
  } else im.creature(layers, ox, oy);
  for (const [x, y, c] of front) im.set(x, y, c);
  if (frame !== JR_TRIP) { im.spr(hl, hy, T.HANDLE); im.spr(hr, hy, T.HANDLE); }
  if (frame === JR_CHEER) for (const [x, y] of [[6, 12], [52, 16], [10, 26], [49, 30]]) im.spr(x, y, T.STARBURST);
  return im.rgba();
}

// ------------------------------------------------------------ wellbeing (64x48)
export const CALM_FRAMES = 4, WD_FRAMES = 4, GLYPH_CALM = 8;
const CALM_CMAP: Record<string, RGB> = { ...LW, o: T.CALM_INK };

/** Soft aura ring: integer ellipse band (doubled-coordinate centre), dotted lower half. */
function calmRing(cx2: number, cy2: number, rx: number, ry: number): [number, number][] {
  const out: [number, number][] = [];
  const rx2 = (2 * rx) ** 2, ry2 = (2 * ry) ** 2, one = rx2 * ry2;
  for (let y = 0; y < RH; y++) for (let x = 0; x < RW; x++) {
    const dx = 2 * x + 1 - cx2, dy = 2 * y + 1 - cy2;
    const v = dx * dx * ry2 + dy * dy * rx2;
    if (one * 10 <= v * 12 && v <= one) {
      if (2 * y + 1 > cy2 && (x + y) % 2) continue;
      out.push([x, y]);
    }
  }
  return out;
}

/** 64x48 meditating "calm" pose (python render_calm(p, frame).tobytes()). */
export function renderCalm(p: Pheno, frame = 0): Uint8Array {
  const f = imod(frame, CALM_FRAMES);
  const im = new Img(RW, RH);
  for (let y = 0; y < RH; y++) {
    let c = T.CALM_SKY[0][1];
    for (const [y0, col] of T.CALM_SKY) if (y >= y0) c = col;
    for (let x = 0; x < RW; x++) im.set(x, y, y < 38 ? c : T.CALM_GROUND);
  }
  for (const [x, y] of T.CALM_DOTS) if ((x + f) % 3) im.set(x, y, LW["w"]);
  const m = bodyMask(p.body, p.stage ?? ADULT);
  const a = anchors(m);
  const pal = palette(p.palette, p.shift);
  const lift = T.CALM_FLOAT[f];
  const ox = 16, oy = 36 - (a.bottom + 1) - lift;
  const cy2 = 2 * (oy + a.top + floorDiv(a.bottom - a.top, 2)) + 1;
  for (const [x, y] of calmRing(64, cy2, 17, 15)) {
    const bg = im.get(x, y)!, l = pal.light;
    im.set(x, y, [floorDiv(bg[0] + 2 * l[0], 3), floorDiv(bg[1] + 2 * l[1], 3), floorDiv(bg[2] + 2 * l[2], 3)]);
  }
  im.spr(20, 37, T.CALM_CUSHION, null, CALM_CMAP);
  const sw = 7 - lift;
  for (let x = 32 - sw; x < 32 + sw; x++) im.set(x, 36, LW["V"]);
  const eyes = p.eyes === 7 ? EYE_CLOSED_CYCLOPS : EYE_CLOSED;
  im.creature(creatureLayers(p, [eyes, 0], true, false), ox, oy);
  const [lx, ly] = T.CALM_LEAF_PATH[f];
  im.spr(lx, ly, T.CALM_LEAF, null, CALM_CMAP);
  const [sx, sy] = T.CALM_SPARKS[f];
  im.spr(sx - 1, sy - 1, T.CALM_SPARK, null, CALM_CMAP);
  T.CALM_SPARKS.forEach(([tx, ty], k) => { if (k !== f) im.set(tx, ty, LW["h"]); });
  return im.rgba();
}

/** 64x48 evening wind-down frame 0..3 (python render_wind_down(p, frame).tobytes()). */
export function renderWindDown(p: Pheno, frame = 0): Uint8Array {
  const f = imod(frame, WD_FRAMES);
  const LX = 50, LY = 21;
  const im = new Img(RW, RH);
  drawRoomBg(im, false);
  drawWindow(im, "night", NONE);
  const lit = new Set<number>();
  const lampOn = f <= 1;
  if (f <= 2) {
    const [core, rim] = lampOn ? [36, 72] : [0, 30];
    for (let y = LY - 9; y < LY + 12; y++) for (let x = LX - 9; x < LX + 18; x++) {
      const dx = x - (LX + 4), dy = floorDiv((y - (LY + 2)) * 3, 2);
      const r = dx * dx + dy * dy;
      if (x < RW && r <= rim && (r <= core || (x + y) % 2 === 0)) {
        const c = im.get(x, y)!, g = T.WD_GLOW;
        im.set(x, y, [floorDiv(c[0] + g[0], 2), floorDiv(c[1] + g[1], 2), floorDiv(c[2] + g[2], 2)]);
        lit.add(y * RW + x);
      }
    }
  }
  im.spr(LX - 2, LY + 8, T.WD_TABLE, null, CALM_CMAP);
  im.spr(LX, LY, T.WD_LAMP, null, { ...CALM_CMAP, h: LW[T.WD_BULB[f]] });
  if (lampOn) for (const [x, y] of sprite(T.WD_LAMP.slice(1, 3))) lit.add((LY + 1 + y) * RW + LX + x);
  const cord = LX + 7, pull = f === 2 ? 1 : 0;
  for (let y = LY + 3; y < LY + 6 + pull; y++) im.set(cord, y, LW["D"]);
  im.set(cord, LY + 6 + pull, lampOn ? LW["h"] : LW["d"]);
  im.spr(4, 38, T.WD_PILLOW, null, CALM_CMAP);
  const m = bodyMask(p.body, p.stage ?? ADULT);
  const a = anchors(m);
  const oy = 40 - (a.bottom + 1);
  let [eyes, mood] = T.WD_FACE[f];
  if (p.eyes === 7) eyes = eyes === 11 ? 12 : EYE_CLOSED_CYCLOPS;
  im.creature(creatureLayers(p, [eyes, mood], true, false), 4, oy);
  if (f === 3) im.spr(26, Math.max(1, oy + a.top - 6), T.WD_Z, null, CALM_CMAP);
  const t = T.WD_DIM[f];
  for (let y = 0; y < RH; y++) for (let x = 0; x < RW; x++) {
    const c = im.get(x, y);
    if (!c || (lampOn && lit.has(y * RW + x))) continue;
    im.px[y * RW + x] = [floorDiv(c[0] * t[0], 256), floorDiv(c[1] * t[1], 256), floorDiv(c[2] * t[2], 256)];
  }
  return im.rgba();
}

/** 16x16 white-on-transparent Lock Screen glyph (scenes 0..6, 7 = jump rope, 8 = calm). */
export function renderGlyph(scene: number): Uint8Array {
  const buf = new Uint8Array(16 * 16 * 4);
  for (const [x, y] of sprite(T.GLYPHS[scene])) buf.fill(255, (y * 16 + x) * 4, (y * 16 + x) * 4 + 4);
  return buf;
}
