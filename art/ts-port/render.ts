// Independent TypeScript port of art/render.py `render(p, scale=1)`.
// Purpose: prove the algorithm is portable (rounding, colorsys, ordering) before
// trusting the Swift port (MixlingsKit/Sources/MixlingsArt), which mirrors this file.
// Run: node art/ts-port/check.ts

export const S = 32;

export interface Pheno {
  body: number; eyes: number; head: number; pattern: number; tail: number;
  palette: number; aura: number; shift: number; seed: number;
}
type RGB = [number, number, number];
type Role = "base" | "shade" | "accent" | "light" | "outline" | "eye" | "white" | "blush";
interface Px { role: Role; solid: boolean }

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
  [0x8FB8FF, 0x5C86D6, 0xFF9F68, 0xD4E3FF], // sky
  [0xFFD36E, 0xE0A93D, 0xFF6F91, 0xFFF0C2], // sunny
  [0xC3A6FF, 0x9479D9, 0x7EF0C8, 0xE7DCFF], // lavender
  [0xFF9B7A, 0xD9704F, 0x6EE7F2, 0xFFD3C4], // coral
  [0x9BE15D, 0x6DB33A, 0xFF7AD9, 0xDDF7C4], // lime
  [0x6FD6E8, 0x3FA8BC, 0xFFE066, 0xCDF4FA], // aqua
  [0xE8E2D0, 0xBDB4A0, 0xFF8A5B, 0xFFFFFF], // cream
  [0xA0A8B8, 0x727B8E, 0xFFD166, 0xD9DEE7], // stone
  [0xFF7AA2, 0xD24F79, 0xFFE27A, 0xFFC6D7], // rose
  [0x5E6BFF, 0x3C46C9, 0xFF9EE5, 0xB9BFFF], // cobalt
  [0x3D3D4E, 0x26262F, 0x7DF9FF, 0x6A6A82], // night (rare)
  [0xFFB347, 0xD98A1F, 0x8E7CFF, 0xFFE0B0], // tangerine
  [0xB8F2E6, 0x7FC7B8, 0xFF8FAB, 0xE6FBF6], // seafoam
  [0xF2F2F2, 0xC9C9D6, 0xFFB3F0, 0xFFFFFF], // ghost (rare)
];
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
    const amt = 0.035 * shift;
    base = shiftHue(base, amt); shade = shiftHue(shade, amt); light = shiftHue(light, amt);
  }
  let outline = darken(shade, 0.45);
  const lum = 0.299 * base[0] + 0.587 * base[1] + 0.114 * base[2];
  const dark = lum < 90;
  if (dark) outline = [18, 18, 24];
  return { base, shade, accent, light, outline,
    eye: dark ? accent : [34, 30, 46], white: [255, 255, 255], blush: [255, 140, 160] };
}

// ------------------------------------------------------------ masks (32x32 bool grids)
type Mask = boolean[]; // index y*S+x
const newMask = (): Mask => new Array(S * S).fill(false);
const inMask = (m: Mask, x: number, y: number) => x >= 0 && x < S && y >= 0 && y < S && m[y * S + x];

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
/** Mask points in Python sorted() order: by x, then y. */
function sortedPoints(m: Mask): [number, number][] {
  const out: [number, number][] = [];
  for (let x = 0; x < S; x++) for (let y = 0; y < S; y++) if (m[y * S + x]) out.push([x, y]);
  return out;
}

function bodyMask(v: number): Mask {
  let m: Mask;
  if (v === 0) m = ellipse(16, 20, 9.5, 8.5);
  else if (v === 1) m = ellipse(16, 19, 7.5, 10.5);
  else if (v === 2) { const a = ellipse(16, 15, 6.5, 6), b = ellipse(16, 22, 9.5, 7); m = a.map((t, i) => t || b[i]); }
  else if (v === 3) m = rrect(7, 11, 24, 28, 5);
  else if (v === 4) {
    m = newMask();
    for (let y = 9; y < 29; y++) {
      const t = (y - 9) / 19;
      const w = 9.5 * Math.pow(Math.sin(Math.PI * Math.min(1.0, t * 0.62 + 0.08)), 0.9);
      for (let x = 0; x < S; x++) if (Math.abs(x + 0.5 - 16) <= w) m[y * S + x] = true;
    }
  } else m = ellipse(16, 22, 11.5, 6.5);
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
  set(x: number, y: number, role: Role, solid = true) { this.px[y * S + x] = { role, solid }; }
  put(x: number, y: number, role: Role, solid = true) { if (x >= 0 && x < S && y >= 0 && y < S) this.set(x, y, role, solid); }
}

// ------------------------------------------------------------ sprites
function sprite(rows: string[]): [number, number, string][] {
  const out: [number, number, string][] = [];
  rows.forEach((row, y) => [...row].forEach((ch, x) => { if (ch !== ".") out.push([x, y, ch]); }));
  return out;
}
const EYES: Record<number, [number, number, string][]> = {
  0: sprite(["KK", "KK"]),
  1: sprite([".KK.", "KWKK", "KKKK", ".KK."]),
  2: sprite(["KKK"]),
  3: sprite([".K.", "K.K"]),
  4: sprite(["KKK", "KWK", "KKK"]),
  5: sprite(["KK", "WK", "KK"]),
  6: sprite([".K.", "KAK", ".K."]),
};
const CYCLOPS = sprite([".KKKK.", "KWWKKK", "KWKKKK", "KKKKKK", ".KKKK."]);
const ROLE: Record<string, Role> = { B: "base", S: "shade", A: "accent", L: "light", K: "eye", W: "white", O: "outline" };

function drawHead(c: Canvas, v: number, a: Anchors) {
  const t = a.top;
  if (v === 1) {
    for (const side of [-1, 1]) {
      const cx = 16 + side * 5;
      for (let i = 0; i < 4; i++) for (let dx = -(3 - i); dx <= 3 - i; dx++) c.put(cx + dx, t - i + 1, "base");
      c.put(cx, t, "accent"); c.put(cx, t - 1, "accent");
    }
  } else if (v === 2) {
    for (const side of [-1, 1]) {
      const cx = 16 + side * 4;
      for (let i = 0; i < 7; i++) {
        for (const dx of [-1, 0, 1]) c.put(cx + dx, t - i + 1, "base");
        if (i >= 1 && i <= 5) c.put(cx, t - i + 1, "light");
      }
    }
  } else if (v === 3) {
    const rows: [number, number[]][] = [[0, [3, 4, 5, 6]], [-1, [4, 5, 6]], [-2, [5, 6, 7]], [-3, [6, 7]], [-4, [7, 8]], [-5, [8]]];
    for (const side of [-1, 1]) for (const [dy, xs] of rows) for (const dx of xs)
      c.put(16 + side * dx, t + dy, dy > -2 ? "light" : "accent");
  } else if (v === 4) {
    for (let i = 1; i < 5; i++) c.put(16, t - i, "shade");
    for (const dx of [-1, 0, 1]) for (const dy of [-1, 0, 1]) if (Math.abs(dx) + Math.abs(dy) < 2) c.put(16 + dx, t - 6 + dy, "accent");
  } else if (v === 5) {
    c.put(16, t - 1, "shade"); c.put(16, t - 2, "shade");
    for (const p of [[-1, -3], [-2, -3], [-2, -4], [-3, -4], [-1, -4]]) c.put(16 + p[0], t + p[1], "accent");
    for (const p of [[1, -2], [2, -3], [2, -2], [3, -3], [1, -3]]) c.put(16 + p[0], t + p[1], "accent");
  } else if (v === 6) {
    for (const dx of [-4, 0, 4]) {
      const hgt = dx !== 0 ? 3 : 4;
      for (let k = 0; k < hgt; k++) {
        const n = hgt - 1 - k;
        // python: range(-(n)//2 - 1 + 1, n//2 + 1)  (unary minus binds before //)
        for (let w = floorDiv(-n, 2) - 1 + 1; w < floorDiv(n, 2) + 1; w++) c.put(16 + dx + w, t - k, "accent");
      }
    }
  } else if (v === 7) {
    for (let x = 11; x < 22; x++) {
      if (x === 11 || x === 21) continue;
      c.put(x, t - 5, "accent", false); c.put(x, t - 3, "accent", false);
    }
    c.put(11, t - 4, "accent", false); c.put(21, t - 4, "accent", false);
  }
}

function thick(c: Canvas, tx: number, ty: number, pts: number[][], role: Role) {
  for (const [dx, dy] of pts) { c.put(tx + dx, ty + dy, role); c.put(tx + dx, ty + dy + 1, role); }
}
function putMask(c: Canvas, m: Mask, role: Role) {
  for (const [x, y] of sortedPoints(m)) c.put(x, y, role);
}
function drawTail(c: Canvas, v: number, a: Anchors) {
  const tx = a.tailX, ty = a.tailY;
  if (v === 1) putMask(c, ellipse(tx + 1.5, ty + 0.5, 2.4, 2.4), "light");
  else if (v === 2) thick(c, tx, ty, [[0, 0], [1, 0], [2, -1], [3, -2], [3, -3], [2, -4], [1, -4]], "base");
  else if (v === 3) {
    thick(c, tx, ty, [[0, 0], [1, 0], [2, -1], [3, -2], [4, -3], [5, -4]], "base");
    putMask(c, ellipse(tx + 6.5, ty - 4.5, 1.6, 1.6), "accent");
  } else if (v === 4) {
    for (const [dx, dy] of [[0, 0], [1, 0], [1, -1], [2, -1], [2, -2], [3, -2], [2, -3], [3, -4], [1, -2], [0, -1], [3, -3], [4, -3], [3, -5]])
      c.put(tx + dx, ty + dy, "accent");
  } else if (v === 5) {
    for (const [dx, dy] of [[0, 0], [1, 0], [1, -1], [2, -1], [2, -2], [1, -2], [1, -3], [2, -3], [3, -3], [3, -4], [4, -4], [4, -5], [3, -5], [5, -5], [5, -6]])
      c.put(tx + dx, ty + dy, "accent");
  }
}

function applyPattern(c: Canvas, m: Mask, v: number, a: Anchors, seed: number) {
  const rnd = new Mulberry(mul32(seed, 2654435761));
  const top = a.top, bottom = a.bottom;
  const pts = sortedPoints(m);
  if (v === 1) {
    const cy = a.midY + (bottom - a.midY) * 0.45;
    const e = ellipse(16, cy, 5, (bottom - top) * 0.28);
    for (const [x, y] of sortedPoints(e)) if (inMask(m, x, y)) c.set(x, y, "light");
  } else if (v === 2) {
    let spots = 0, tries = 0;
    while (spots < 4 && tries < 60) {
      tries++;
      const [x, y] = rnd.choice(pts);
      if (y <= a.eyeY + 1 && Math.abs(x - 16) < 6) continue;
      const ok = inMask(m, x, y) && inMask(m, x + 1, y) && inMask(m, x, y + 1) && inMask(m, x + 1, y + 1);
      if (ok) {
        for (const dx of [0, 1]) for (const dy of [0, 1]) c.set(x + dx, y + dy, "accent");
        spots++;
      }
    }
  } else if (v === 3) {
    for (const [x, y] of pts) if (y > a.eyeY + 3 && [0, 1].includes(pyMod(y - top, 5))) c.set(x, y, "accent");
  } else if (v === 4) {
    for (const [x, y] of pts) if (y < top + (bottom - top) * 0.3) c.set(x, y, "accent");
  } else if (v === 5) {
    for (const dx of [-1, 1]) for (const k of [0, 2]) {
      const px = 16 + dx * (a.eyeDx + 1 + floorDiv(k, 2)), py = a.eyeY + 2 + (k % 2);
      if (inMask(m, px, py)) c.set(px, py, "shade");
    }
  }
}

/**
 * Python picks the highlight anchor with `sorted(mask, key=...)[:1]`; the key ties
 * for every body, so the winner is the first tied point in CPython *set iteration
 * order* (hash-table layout), not something portable. The mask depends only on the
 * body variant, so the winner is a per-body constant. Recorded from CPython 3.13.
 */
export const HIGHLIGHT_TIE_WINNER: [number, number][] = [[9, 14], [13, 9], [10, 12], [9, 12], [13, 9], [6, 18]];
export let tieMode: "table" | "lex" = "table";
export function setTieMode(m: "table" | "lex") { tieMode = m; }

function shadeBody(c: Canvas, m: Mask, bodyVariant: number) {
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
  // highlight upper-left: min key, tie-break see HIGHLIGHT_TIE_WINNER
  const key = (x: number, y: number) => (x - cx) + (y - cy);
  let best = Infinity;
  for (const [x, y] of pts) best = Math.min(best, key(x, y));
  const ties = pts.filter(([x, y]) => key(x, y) === best); // lex (x, y) order
  let tl = ties[0];
  if (tieMode === "table") {
    const w = HIGHLIGHT_TIE_WINNER[bodyVariant >= 0 && bodyVariant <= 4 ? bodyVariant : 5];
    if (ties.some(p => p[0] === w[0] && p[1] === w[1])) tl = w;
  }
  if (tl) {
    const [x, y] = tl;
    for (const [px, py] of [[x + 2, y + 2], [x + 3, y + 2], [x + 2, y + 3]])
      if (inMask(m, px, py) && c.get(px, py)!.role === "base") c.set(px, py, "white");
  }
}

function drawEyes(c: Canvas, v: number, a: Anchors) {
  const ey = a.eyeY, dx = a.eyeDx;
  if (v === 7) {
    for (const [x, y, ch] of CYCLOPS) c.put(16 - 3 + x, ey - 2 + y, ROLE[ch]);
    return;
  }
  const spr = EYES[v];
  if (!spr) return; // python: KeyError for unknown variants
  const w = Math.max(...spr.map(s => s[0])) + 1;
  const h = Math.max(...spr.map(s => s[1])) + 1;
  for (const side of [-1, 1]) {
    const cx = 16 + side * dx;
    const x0 = side < 0 ? cx - floorDiv(w, 2) : cx - floorDiv(w - 1, 2);
    for (const [x, y, ch] of spr) {
      const xx = side > 0 ? x : (w - 1 - x);
      c.put(x0 + xx, ey - floorDiv(h, 2) + y, ROLE[ch]);
    }
  }
  for (const side of [-1, 1]) c.put(16 + side * (dx + 2), ey + 2, "blush");
}

function outline(c: Canvas) {
  const out: boolean[] = new Array(S * S).fill(false);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const p = c.get(x, y);
    if (!p || !p.solid || p.role === "outline") continue;
    for (const [nx, ny] of [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]])
      if (nx >= 0 && nx < S && ny >= 0 && ny < S && !c.has(nx, ny)) out[ny * S + nx] = true;
  }
  for (let i = 0; i < S * S; i++) if (out[i]) c.px[i] = { role: "outline", solid: false };
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

/** 32x32 RGBA, row-major, straight alpha (identical to Python render(p, 1).tobytes()). */
export function render(p: Pheno): Uint8Array {
  const pal = palette(p.palette, p.shift);
  const mask = bodyMask(p.body);
  const a = anchors(mask);
  const c = new Canvas();
  drawTail(c, p.tail, a);
  putMask(c, mask, "base");
  drawHead(c, p.head, a);
  for (const [x, y] of sortedPoints(mask)) if (!c.has(x, y)) c.set(x, y, "base");
  applyPattern(c, mask, p.pattern, a, p.seed);
  shadeBody(c, mask, p.body);
  outline(c);
  drawEyes(c, p.eyes, a);

  const buf = new Uint8Array(S * S * 4);
  for (const [x, y, role] of drawAura(p.aura, p.seed)) {
    if (x >= 0 && x < S && y >= 0 && y < S && !c.has(x, y)) {
      const col = pal[role], i = (y * S + x) * 4;
      buf[i] = col[0]; buf[i + 1] = col[1]; buf[i + 2] = col[2]; buf[i + 3] = p.aura === 2 ? 170 : 255;
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
