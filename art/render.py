"""Mixlings pixel creature renderer (reference implementation).

Composes a 32x32 creature from part variants:
body, eyes, head, pattern, tail, palette, aura (+ paletteShift),
plus two non-genetic layers: `stage` (egg / baby / teen / adult) and
`mood` (expression). Also a one-colour `silhouette` mode (Lock Screen).

Portability rules (this file is mirrored by art/ts-port/render.ts and
MixlingsKit/Sources/MixlingsArt, verified pixel-for-pixel by art/golden):
- the only randomness is Mulberry (mulberry32);
- parts are explicit tables; nothing depends on set/dict iteration order
  (every loop over a mask goes through `pts(mask)`, i.e. sorted by x then y);
- every float -> int conversion is Python round() (banker's rounding).
"""
from __future__ import annotations

import colorsys
import math
import random
import sys
from dataclasses import dataclass

from PIL import Image, ImageDraw, ImageFont

S = 32  # canvas size

EGG, BABY, TEEN, ADULT = 0, 1, 2, 3


class Mulberry:
    """mulberry32, identical to docs/genome-spec.md §3 (portable to Swift/TS)."""

    def __init__(self, seed: int):
        self.s = seed & 0xFFFFFFFF

    def next(self) -> int:
        self.s = (self.s + 0x6D2B79F5) & 0xFFFFFFFF
        t = self.s
        t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF
        t ^= (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
        return (t ^ (t >> 14)) & 0xFFFFFFFF

    def int(self, n: int) -> int:
        return self.next() % n

    def randrange(self, a: int, b: int) -> int:
        return a + self.int(b - a)

    def choice(self, seq):
        return seq[self.int(len(seq))]


# ---------------------------------------------------------------- palettes
def hx(c: str) -> tuple[int, int, int]:
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


# base, shade, accent, light(belly). Names and indices are fixed (genome catalog).
PALETTES = [
    ("#7ED4A6", "#4FA77E", "#FFCB5C", "#C9F2DA"),  # mint      h147
    ("#F7A6C4", "#D2759A", "#7CC6FE", "#FFD9E7"),  # bubblegum
    ("#8FA6FF", "#5C70D6", "#FF9F68", "#D4DCFF"),  # sky       h228 (was 218)
    ("#FFD36E", "#E0A93D", "#FF6F91", "#FFF0C2"),  # sunny
    ("#C3A6FF", "#9479D9", "#7EF0C8", "#E7DCFF"),  # lavender
    ("#FF9B7A", "#D9704F", "#6EE7F2", "#FFD3C4"),  # coral
    ("#BCE34F", "#88B226", "#FF7AD9", "#EAF8C0"),  # lime      h76 (was 91)
    ("#4FD9EE", "#25A8C2", "#FFE066", "#C6F6FD"),  # aqua      h188, more saturated
    ("#E8E2D0", "#BDB4A0", "#FF8A5B", "#FFFFFF"),  # cream
    ("#A0A8B8", "#727B8E", "#FFD166", "#D9DEE7"),  # stone
    ("#FF7AA2", "#D24F79", "#FFE27A", "#FFC6D7"),  # rose
    ("#5E6BFF", "#3C46C9", "#FF9EE5", "#B9BFFF"),  # cobalt
    ("#3D3D4E", "#26262F", "#7DF9FF", "#6A6A82"),  # night (rare)
    ("#FFB347", "#D98A1F", "#8E7CFF", "#FFE0B0"),  # tangerine
    ("#C0F5E4", "#80C7AF", "#FF8FAB", "#E8FCF5"),  # seafoam   h161 pale (was 167)
    ("#F2F2F2", "#C9C9D6", "#FFB3F0", "#FFFFFF"),  # ghost (rare)
]
GHOST = 15
GHOST_OUTLINE = (0x8E, 0x8A, 0xA8)  # pale outline: ghosts look see-through
TWIN_SHIFT = 0.08                    # hue turns per paletteShift step


def shift_hue(rgb, amount):
    r, g, b = (v / 255 for v in rgb)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    h = (h + amount) % 1.0
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return (round(r * 255), round(g * 255), round(b * 255))


def darken(rgb, f):
    return tuple(max(0, round(v * f)) for v in rgb)


def palette(idx: int, shift: int = 0):
    base, shade, accent, light = (hx(c) for c in PALETTES[idx])
    if shift:
        amt = TWIN_SHIFT * shift
        base, shade, light = (shift_hue(c, amt) for c in (base, shade, light))
    outline = darken(shade, 0.45)
    lum = 0.299 * base[0] + 0.587 * base[1] + 0.114 * base[2]
    dark = lum < 90
    if dark:  # dark creatures get glowing eyes and a near-black outline
        outline = (18, 18, 24)
    if idx == GHOST:
        outline = GHOST_OUTLINE
    return {
        "base": base, "shade": shade, "accent": accent, "light": light,
        "outline": outline,
        "eye": accent if dark else (34, 30, 46),
        "white": (255, 255, 255),
        "blush": (255, 140, 160),
        "mouth": light if dark else darken(shade, 0.45),
    }


# ---------------------------------------------------------------- masks
def pts(mask: set) -> list:
    """The only way masks are iterated: sorted by x, then y (portable order)."""
    return sorted(mask)


def ellipse(cx, cy, rx, ry):
    return {(x, y) for x in range(S) for y in range(S)
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0}


def rrect(x0, y0, x1, y1, r):
    out = set()
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            cx = min(max(x, x0 + r), x1 - r)
            cy = min(max(y, y0 + r), y1 - r)
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 0.5:
                out.add((x, y))
    return out


def rows_mask(y0, halves):
    """Symmetric mask from per-row half-widths: row y0+i covers x 16-k .. 15+k."""
    out = set()
    for i, k in enumerate(halves):
        for x in range(16 - k, 16 + k):
            out.add((x, y0 + i))
    return out


# Drop half-widths per stage (adult = the approved sin/pow curve, tabulated).
DROP_ROWS = {
    ADULT: (9, [3, 4, 4, 5, 6, 7, 7, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 8]),
    TEEN: (13, [2, 3, 4, 5, 5, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 6]),
    BABY: (17, [2, 3, 3, 4, 5, 5, 5, 5, 5, 5, 5, 4]),
}
# 14 x 18 egg (rows 11..28).
EGG_ROWS = (11, [2, 3, 4, 4, 5, 5, 6, 6, 6, 7, 7, 7, 7, 7, 6, 6, 5, 3])


def body_adult(v):
    if v == 0:   # round
        return ellipse(16, 20, 9.5, 8.5)
    if v == 1:   # bean (tall)
        return ellipse(16, 19, 7.5, 10.5)
    if v == 2:   # pear: narrow head on a wide base
        return ellipse(16, 15, 5, 6) | ellipse(16, 22, 9.5, 7)
    if v == 3:   # block: nearly square corners
        return rrect(7, 11, 24, 28, 2)
    if v == 4:   # drop
        return rows_mask(*DROP_ROWS[ADULT])
    return ellipse(16, 22, 11.5, 6.5)  # mochi (wide)


def body_teen(v):  # ~80 %
    if v == 0:
        return ellipse(16, 22, 7.5, 7)
    if v == 1:
        return ellipse(16, 21, 6, 8.5)
    if v == 2:
        return ellipse(16, 18.5, 4, 5) | ellipse(16, 24, 7.5, 5.5)
    if v == 3:
        return rrect(9, 15, 22, 28, 2)
    if v == 4:
        return rows_mask(*DROP_ROWS[TEEN])
    return ellipse(16, 23.5, 9.5, 5.5)


def body_baby(v):  # ~60 %
    if v == 0:
        return ellipse(16, 23.5, 6, 5.5)
    if v == 1:
        return ellipse(16, 23, 4.5, 6.5)
    if v == 2:
        return ellipse(16, 21.5, 3, 3.5) | ellipse(16, 25, 6, 4)
    if v == 3:
        return rrect(10, 18, 21, 28, 1)
    if v == 4:
        return rows_mask(*DROP_ROWS[BABY])
    return ellipse(16, 25, 7.5, 4)


def body_mask(v: int, stage: int = ADULT) -> set:
    if stage == EGG:
        return rows_mask(*EGG_ROWS)
    m = body_adult(v) if stage == ADULT else body_teen(v) if stage == TEEN else body_baby(v)
    # little feet
    bottom = max(y for _, y in pts(m))
    for fx in (11, 12, 19, 20):
        if (fx, bottom) in m:
            m.add((fx, bottom + 1))
    return m


def anchors(mask: set) -> dict:
    p = pts(mask)
    top = min(y for x, y in p if x == 16)
    bottom = max(y for _, y in p)
    h = bottom - top
    eye_y = top + max(3, round(h * 0.38))
    row = [x for x, y in p if y == eye_y]
    half = (max(row) - min(row)) / 2
    eye_dx = max(2, min(4, round(half * 0.42)))
    tail_y = top + round(h * 0.68)
    tail_x = max(x for x, y in p if y == tail_y) + 1
    return {"top": top, "bottom": bottom, "eye_y": eye_y, "eye_dx": eye_dx,
            "tail": (tail_x, tail_y), "mid_y": top + h // 2}


# ---------------------------------------------------------------- sprites
# ASCII sprites, '.' empty. Roles: B base, S shade, A accent, L light, K eye,
# W white, M mouth; lower-case 'a' = accent that floats (not outlined).
def sprite(rows):
    out = []
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                out.append((x, y, ch))
    return out


ROLE = {"B": "base", "S": "shade", "A": "accent", "L": "light", "K": "eye",
        "W": "white", "M": "mouth", "a": "accent"}

# Eye sprites describe the RIGHT eye; the left eye is its mirror image
# (x -> 31 - x), except glints stay top-left on both (`EYE_MIRROR` False).
EYES = {
    0: sprite(["KK", "KK", "KK"]),                       # dots 2x3
    1: sprite([".KK.", "KWKK", "KKKK", ".KK."]),          # big round 4x4
    2: sprite(["KKKK", "...K"]),                          # sleepy 4x2, lash on the outside
    3: sprite([".KKK.", "K...K", "K...K"]),               # happy arch 5x3
    4: sprite([".WK.", "WWWK", "KWKK", ".KK."]),          # sparkle 4x4 with + glint
    5: sprite([".K.", "WKK", "KKK", ".K."]),              # oval 3x4, white top-left
    6: sprite([".K.", "KAK", ".K."]),                     # star
    7: sprite([".KKKK.", "KWWKKK", "KWKKKK", "KKKKKK", ".KKKK."]),  # cyclops (single, centred)
}
EYE_MIRROR = {0: False, 1: False, 2: True, 3: True, 4: False, 5: False, 6: False, 7: False}

# Mood layer (not a gene): mouth sprites centred on x 15.5, drawn under the eyes.
MOODS = {
    0: (14, sprite(["M..M", ".MM."])),        # neutral: small smile
    1: (14, sprite([".MM.", "M..M", ".MM."])),  # "o"
    2: (13, sprite([".M..M.", "M.MM.M"])),     # hungry wobble
}

# Heads per stage: variant -> (x0, dy0 from body top, rows). Symmetric about x=15.5
# except the antenna / leaf (single stems, as approved).
HEADS = {
    ADULT: {
        1: (8, -4, ["...B........B...",          # cat ears (raised, accent inner ear)
                    "..BAB......BAB..",
                    "..BAB......BAB..",
                    ".BAAAB....BAAAB.",
                    ".BAAAB....BAAAB.",
                    "BBBBBBB..BBBBBBB"]),
        2: (11, -5, ["BBB....BBB",                 # bunny ears
                     "BLB....BLB", "BLB....BLB", "BLB....BLB", "BLB....BLB", "BLB....BLB",
                     "BBB....BBB"]),
        3: (7, -5, ["A................A",          # horns
                    "AA..............AA",
                    ".AA............AA.",
                    ".AAA..........AAA.",
                    "..LLL........LLL..",
                    "..LLLL......LLLL.."]),
        4: (15, -7, [".A.", "AAA", ".A.", ".S.", ".S.", ".S.", ".S."]),  # antenna
        5: (13, -4, ["AAA....",                    # leaf sprout
                     ".AA.AAA",
                     "...SAA.",
                     "...S..."]),
        6: (10, -5, [".....AA.....",               # crest: 5px centre spike, shade base
                     "....AAAA....",
                     ".A..AAAA..A.",
                     ".AA.AAAA.AA.",
                     ".AAAAAAAAAA.",
                     ".SSSSSSSSSS."]),
        7: (10, -5, [".aaaaaaaaaa.", "a..........a", ".aaaaaaaaaa."]),  # halo
    },
    TEEN: {  # half-grown parts
        1: (9, -3, ["..B........B..",
                    ".BAB......BAB.",
                    ".BAAB....BAAB.",
                    "BBBBB....BBBBB"]),
        2: (11, -4, ["BBB....BBB", "BLB....BLB", "BLB....BLB", "BBB....BBB"]),
        3: (8, -3, ["A..............A",
                    "AA............AA",
                    ".LL..........LL.",
                    ".LLL........LLL."]),
        4: (15, -5, [".A.", "AAA", ".A.", ".S.", ".S."]),
        5: (13, -3, ["AA..AA", ".AASA.", "...S.."]),
        6: (12, -4, ["...AA...", ".A.AA.A.", ".AAAAAA.", "SSSSSSSS"]),
        7: (12, -5, [".aaaaaa.", "a......a", ".aaaaaa."]),
    },
    BABY: {  # nubs
        1: (10, -2, ["..B......B..", ".BAB....BAB."]),
        2: (11, -3, [".BB....BB.", ".BL....LB.", ".BB....BB."]),
        3: (10, -2, ["A..........A", ".LL......LL."]),
        4: (15, -3, [".A.", "AAA", ".S."]),
        5: (14, -2, ["AA.A", "..S."]),
        6: (13, -2, [".AA.", "AAAA"]),
        7: (13, -4, [".aaaa.", "a....a", ".aaaa."]),
    },
}

# Tails per stage: variant -> (dx0, dy0 from the tail anchor, rows). Babies have none.
TAILS = {
    ADULT: {
        1: (-1, -2, [".BBB.",                      # puff (5px, darker than belly)
                     "BLBBB",
                     "BBBBS",
                     "BBBSS",
                     ".SSS."]),
        2: (0, -5, ["..BBBB.",                     # curly: full spiral
                    ".B....B",
                    ".B.BB.B",
                    ".B.B..B",
                    "BB..BB.",
                    "B......"]),
        3: (0, -6, [".....AAA",                    # long, with a tuft
                    ".....AAA",
                    ".....AAA",
                    "....BB..",
                    "...BB...",
                    "..BB....",
                    "BBB.....",
                    "BB......"]),
        4: (0, -6, ["....A",                       # flame: accent tip over a base core
                    "...AA",
                    "..ABA",
                    ".ABBA",
                    "ABBB.",
                    "BBB..",
                    "BB..."]),
        5: (0, -6, [".....A",                      # lightning
                    "...AAA",
                    "...AA.",
                    ".AAA..",
                    ".AA...",
                    ".AA...",
                    "AA...."]),
    },
    TEEN: {  # stubs
        1: (-1, -1, ["BBB", "BBS", ".S."]),
        2: (0, -2, [".BB", "B.B", "BB."]),
        3: (0, -2, ["..A", ".B.", "B.."]),
        4: (0, -2, [".A", "BA", "B."]),
        5: (0, -2, ["..A", ".A.", "AA."]),
    },
}


@dataclass
class Px:
    role: str
    solid: bool          # participates in outline
    knock: bool = False  # eye pixel: transparent in silhouette mode


def put(canvas, x, y, role, solid=True, knock=False):
    if 0 <= x < S and 0 <= y < S:
        canvas[(x, y)] = Px(role, solid, knock)


def stamp(canvas, x0, y0, rows):
    for (x, y, ch) in sprite(rows):
        put(canvas, x0 + x, y0 + y, ROLE[ch], ch != "a")


def draw_head(canvas, v, a, stage):
    part = HEADS.get(stage, {}).get(v)
    if part:
        x0, dy0, rows = part
        stamp(canvas, x0, a["top"] + dy0, rows)


def draw_tail(canvas, v, a, stage):
    part = TAILS.get(stage, {}).get(v)
    if part:
        dx0, dy0, rows = part
        tx, ty = a["tail"]
        stamp(canvas, tx + dx0, ty + dy0, rows)


# Spots sit on a fixed grid around (16, mid_y); each must fit fully on the body
# and stay off the face. At most 4, taken in table order.
SPOT_GRID = [(-7, -2), (5, -3), (-3, 2), (4, 3), (-8, 4), (0, 6), (6, -7), (-5, 7)]


def apply_pattern(canvas, mask, v, a):
    top, bottom = a["top"], a["bottom"]
    if v == 1:  # belly
        cy = a["mid_y"] + (bottom - a["mid_y"]) * 0.45
        for p in pts(ellipse(16, cy, 5, (bottom - top) * 0.28)):
            if p in mask:
                canvas[p] = Px("light", True)
    elif v == 2:  # spots
        spots = 0
        for dx, dy in SPOT_GRID:
            if spots == 4:
                break
            x, y = 16 + dx, a["mid_y"] + dy
            if y <= a["eye_y"] + 2 and -7 <= dx <= 5:
                continue
            if all((x + i, y + j) in mask for i in (0, 1) for j in (0, 1)):
                for i in (0, 1):
                    for j in (0, 1):
                        canvas[(x + i, y + j)] = Px("accent", True)
                spots += 1
    elif v == 3:  # stripes (two-pixel bands, below the face)
        for (x, y) in pts(mask):
            if y > a["eye_y"] + 3 and (y - top) % 5 in (0, 1):
                canvas[(x, y)] = Px("accent", True)
    elif v == 4:  # two-tone cap
        for (x, y) in pts(mask):
            if y < top + (bottom - top) * 0.3:
                canvas[(x, y)] = Px("accent", True)
    elif v == 5:  # freckles: 3 accent dots per cheek
        for dx, dy in ((0, 0), (2, 0), (1, 1)):
            x, y = 16 + a["eye_dx"] + 1 + dx, a["eye_y"] + 3 + dy
            for px in (x, 31 - x):
                if (px, y) in mask:
                    canvas[(px, y)] = Px("accent", True)


EGG_SPOTS = [(12, 14), (18, 12), (16, 18), (11, 21), (19, 22), (15, 25)]
EGG_FRECKLES = [(13, 14), (18, 13), (20, 18), (11, 19), (16, 22), (19, 25)]


def egg_pattern(canvas, mask, v):
    """The egg shows the creature's pattern on its shell."""
    if v == 1:  # belly: pale lower shell
        for (x, y) in pts(mask):
            if y >= 22:
                canvas[(x, y)] = Px("light", True)
    elif v == 2:  # spots
        for (x, y) in EGG_SPOTS:
            for i in (0, 1):
                for j in (0, 1):
                    if (x + i, y + j) in mask:
                        canvas[(x + i, y + j)] = Px("accent", True)
    elif v == 3:  # zig-zag band
        for (x, y) in pts(mask):
            z = (x // 2) % 2
            if y in (18 + z, 19 + z, 23 + z):
                canvas[(x, y)] = Px("accent", True)
    elif v == 4:  # cap
        for (x, y) in pts(mask):
            if y < 16:
                canvas[(x, y)] = Px("accent", True)
    elif v == 5:  # freckles
        for p in EGG_FRECKLES:
            if p in mask:
                canvas[p] = Px("accent", True)


def shade_body(canvas, mask):
    p = pts(mask)
    xs = [x for x, _ in p]
    ys = [y for _, y in p]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    for (x, y) in p:
        # lower-right rim shading
        if (x + 1, y + 1) not in mask or (x + 1, y) not in mask and y > cy:
            if x >= cx - 1 or y >= cy + 2:
                if canvas[(x, y)].role == "base":
                    canvas[(x, y)] = Px("shade", True)
    # highlight: the upper-left tangent point = middle of the points with minimal
    # x + y (sorted by x, then y), offset inwards.
    best = min(x + y for x, y in p)
    ties = [q for q in p if q[0] + q[1] == best]
    x, y = ties[(len(ties) - 1) // 2]
    for q in ((x + 2, y + 2), (x + 3, y + 2), (x + 2, y + 3)):
        if q in mask and canvas[q].role == "base":
            canvas[q] = Px("white", True)


def eye_layout(v, a):
    """(sprite, x0 of the right eye, top y, width, height, dx used)."""
    spr = EYES[v]
    w = max(x for x, _, _ in spr) + 1
    h = max(y for _, y, _ in spr) + 1
    dx = max(a["eye_dx"], w // 2 + 1)
    return spr, 16 + dx - w // 2, a["eye_y"] - h // 2, w, h, dx


def draw_eyes(canvas, v, a):
    spr, x0, y0, w, h, dx = eye_layout(v, a)
    if v == 7:  # cyclops: one centred eye (x 13..18)
        for (x, y, ch) in spr:
            put(canvas, 13 + x, y0 + y, ROLE[ch], knock=True)
        return
    for (x, y, ch) in spr:
        put(canvas, x0 + x, y0 + y, ROLE[ch], knock=True)
        lx = 31 - (x0 + x) if EYE_MIRROR[v] else 31 - (x0 + w - 1) + x
        put(canvas, lx, y0 + y, ROLE[ch], knock=True)


def draw_face(canvas, mask, eyes, mood, a):
    """Mood mouth + blush (colour mode only)."""
    spr, x0, y0, w, h, dx = eye_layout(eyes, a)
    my = y0 + h + (1 if h >= 3 else 2)
    mx, mouth = MOODS.get(mood, MOODS[0])
    for (x, y, ch) in mouth:
        put(canvas, mx + x, my + y, ROLE[ch])
    by = a["eye_y"] + 2
    bx = 16 + dx + (w + 1) // 2 + 1 if eyes != 7 else 21
    for x in (bx, 31 - bx):
        if (x, by) in mask:
            put(canvas, x, by, "blush")


def outline(canvas):
    solid = sorted(p for p, px in canvas.items() if px.solid and px.role != "outline")
    out = set()
    for (x, y) in solid:
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) not in canvas and 0 <= nx < S and 0 <= ny < S:
                out.add((nx, ny))
    for p in sorted(out):
        canvas[p] = Px("outline", False)


def draw_aura(v, seed):
    if v == 0:
        return []
    rnd = Mulberry(seed * 7 + v)
    extra = []
    if v == 1:  # sparkles
        for _ in range(5):
            x, y = rnd.randrange(1, S - 1), rnd.randrange(1, 14)
            extra += [(x, y, "white"), (x - 1, y, "accent"), (x + 1, y, "accent"),
                      (x, y - 1, "accent"), (x, y + 1, "accent")]
    elif v == 2:  # glow ring (drawn behind), dashed: 3 dots on, 2 off
        for a in range(0, 360, 9):
            if (a // 9) % 5 >= 3:
                continue
            r = 14.5
            x = round(16 + r * math.cos(math.radians(a)))
            y = round(18 + r * 0.85 * math.sin(math.radians(a)))
            extra.append((x, y, "light"))
    elif v == 3:  # tiny hearts
        heart = [(0, 0), (2, 0), (0, 1), (1, 1), (2, 1), (1, 2)]
        for _ in range(3):
            x, y = rnd.randrange(2, S - 4), rnd.randrange(1, 10)
            extra += [(x + dx, y + dy, "blush") for dx, dy in heart]
    return extra


@dataclass
class Pheno:
    body: int
    eyes: int
    head: int
    pattern: int
    tail: int
    palette: int
    aura: int
    shift: int = 0
    seed: int = 0
    mood: int = 0    # 0 neutral (small smile), 1 "o", 2 hungry wobble
    stage: int = 3   # 0 egg, 1 baby, 2 teen, 3 adult


def build(p: Pheno, silhouette: bool = False) -> dict:
    """The role canvas: {(x, y): Px}."""
    stage = p.stage
    mask = body_mask(p.body, stage)
    canvas: dict = {}
    if stage == EGG:
        for pt in pts(mask):
            canvas[pt] = Px("base", True)
        egg_pattern(canvas, mask, p.pattern)
        shade_body(canvas, mask)
        outline(canvas)
        return canvas
    a = anchors(mask)
    draw_tail(canvas, p.tail, a, stage)
    for pt in pts(mask):
        canvas[pt] = Px("base", True)
    draw_head(canvas, p.head, a, stage)
    for pt in pts(mask):  # body over head base so ears tuck behind
        canvas.setdefault(pt, Px("base", True))
    apply_pattern(canvas, mask, p.pattern, a)
    shade_body(canvas, mask)
    outline(canvas)
    draw_eyes(canvas, p.eyes, a)
    if not silhouette:
        draw_face(canvas, mask, p.eyes, p.mood, a)
    return canvas


def render_raw(p: Pheno, silhouette: bool = False) -> Image.Image:
    canvas = build(p, silhouette)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = img.load()
    if silhouette:  # one colour, knocked-out eyes, no aura
        for (x, y), v in canvas.items():
            if not v.knock:
                px[x, y] = (255, 255, 255, 255)
        return img
    pal = palette(p.palette, p.shift)
    if p.stage == ADULT:
        for (x, y, role) in draw_aura(p.aura, p.seed):
            if 0 <= x < S and 0 <= y < S and (x, y) not in canvas:
                px[x, y] = (*pal[role], 255)
    for (x, y), v in canvas.items():
        px[x, y] = (*pal[v.role], 255)
    return img


def render(p: Pheno, scale: int = 8, silhouette: bool = False) -> Image.Image:
    return render_raw(p, silhouette).resize((S * scale, S * scale), Image.NEAREST)


# ---------------------------------------------------------------- app icon
ICON_BG = (0x5B, 0x3F, 0xD6)
# 22 x 28 egg for the icon (rows 2..29)
ICON_EGG = (2, [2, 4, 5, 6, 7, 7, 8, 8, 9, 9, 9, 10, 10, 10, 10, 11, 11, 11, 11, 11, 11, 10,
                10, 10, 9, 8, 7, 4])
# zig-zag crack: x offset of the crack column per row (relative to x=16)
ICON_CRACK = [0, 0, -1, -1, 0, 1, 1, 0, -1, -2, -1, 0, 1, 2, 1, 0, -1, -2, -1, 0, 1, 1, 0, -1,
              -1, 0, 0, 0]


def render_icon(left: int = 3, right: int = 7, size: int = 1024) -> Image.Image:
    y0, halves = ICON_EGG
    mask = rows_mask(y0, halves)
    crack = {}
    for i, k in enumerate(halves):
        crack[y0 + i] = 16 + ICON_CRACK[i]
    canvas = {}
    for (x, y) in pts(mask):
        canvas[(x, y)] = Px("L" if x < crack[y] else "R", True)
    # shading per half, with the palettes of both parents
    pl, pr = palette(left), palette(right)
    img = Image.new("RGBA", (S, S), (*ICON_BG, 255))
    px = img.load()
    xs = [x for x, _ in pts(mask)]
    cx, cy = (min(xs) + max(xs)) / 2, y0 + len(halves) / 2
    for (x, y) in pts(mask):
        side = canvas[(x, y)].role
        pal = pl if side == "L" else pr
        role = "base"
        if (x + 1, y + 1) not in mask or ((x + 1, y) not in mask and y > cy):
            if x >= cx - 1 or y >= cy + 2:
                role = "shade"
        px[x, y] = (*pal[role], 255)
    # pattern hints: spots on the left half, zig-zag stripe on the right half
    for (x, y) in [(10, 13), (11, 13), (10, 14), (11, 14), (12, 24), (13, 24), (12, 25), (13, 25),
                   (7, 20), (8, 20), (7, 21), (8, 21)]:
        if (x, y) in mask and x < crack[y] - 1:
            px[x, y] = (*pl["accent"], 255)
    for (x, y) in pts(mask):
        z = (x // 2) % 2
        if x > crack[y] + 1 and y in (14 + z, 15 + z):
            px[x, y] = (*pr["accent"], 255)
    # highlight
    for (x, y) in [(10, 6), (11, 6), (9, 7), (9, 8)]:
        px[x, y] = (255, 255, 255, 255)
    # crack: dark zig-zag line, 1px, plus a 1px light gap on the right edge
    dark = (34, 22, 70, 255)
    for y in range(y0, y0 + len(halves)):
        c = crack[y]
        px[c, y] = dark
        if y > y0 and crack[y - 1] != c:  # keep the line connected
            step = 1 if crack[y - 1] > c else -1
            for xx in range(c + step, crack[y - 1], step):
                px[xx, y] = dark
    # outline
    for (x, y) in pts(mask):
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) not in mask:
                px[nx, ny] = dark
    # sparkles
    for (sx, sy) in [(27, 6), (4, 26)]:
        px[sx, sy] = (255, 255, 255, 255)
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            px[sx + d[0], sy + d[1]] = (0xFF, 0xE0, 0x66, 255)
    return img.resize((size, size), Image.NEAREST).convert("RGB")


# ---------------------------------------------------------------- sheets
def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


def random_pheno(rnd: random.Random, i: int) -> Pheno:
    # Picks phenotypes for review sheets / golden cases only (not part of rendering).
    return Pheno(body=rnd.randrange(6), eyes=rnd.choice([0, 1, 1, 2, 3, 4, 5, 6]),
                 head=rnd.randrange(7), pattern=rnd.randrange(6), tail=rnd.randrange(6),
                 palette=rnd.randrange(16), aura=rnd.choice([0, 0, 0, 1, 2, 3]), seed=i)


BG = (246, 243, 236)
CARD = (255, 255, 255)
EDGE = (225, 220, 208)
INK = (110, 104, 92)


def card(d, x, y, w, h, fill=CARD):
    d.rounded_rectangle([x - 6, y - 6, x + w + 6, y + h + 6], 14, fill=fill, outline=EDGE)


def grid_sheet(path, items, cols, scale=6, labels=None, row_labels=None, bg=BG, fill=CARD,
               silhouette=False, label_w=0):
    cs = S * scale
    cell = cs + 24
    lab_h = 26 if labels else 0
    rows = (len(items) + cols - 1) // cols
    w = 24 + label_w + cols * cell
    h = 24 + rows * (cell + lab_h)
    img = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(img)
    small = font(16)
    for i, p in enumerate(items):
        x = 24 + label_w + (i % cols) * cell
        y = 24 + (i // cols) * (cell + lab_h)
        card(d, x, y, cs, cs, fill)
        if p is not None:
            spr = render(p, scale, silhouette=silhouette)
            img.paste(spr, (x, y), spr)
        if labels:
            d.text((x + cs / 2, y + cs + 16), labels[i], fill=INK, font=small, anchor="mm")
    if row_labels:
        for r, t in enumerate(row_labels):
            d.text((24, 24 + r * (cell + lab_h) + cs / 2), t, fill=INK, font=small, anchor="lm")
    img.save(path)


def sheet(path: str, n: int = 24, cols: int = 6, seed: int = 7, scale: int = 6):
    rnd = random.Random(seed)
    grid_sheet(path, [random_pheno(rnd, i) for i in range(n)], cols, scale)


def stages_sheet(path: str, seed: int = 7, scale: int = 5):
    rnd = random.Random(seed)
    ps = [random_pheno(rnd, i) for i in range(24)]
    chosen = [ps[i] for i in (0, 4, 7, 10, 14, 20)]
    items, labels = [], []
    for p in chosen:
        for st, name in ((0, "яйце"), (1, "малюк"), (2, "підліток"), (3, "дорослий")):
            items.append(Pheno(**{**p.__dict__, "stage": st}))
            labels.append(name)
    grid_sheet(path, items, 8, scale, labels)


EYE_NAMES = ["dots", "big", "sleepy", "happy", "sparkle", "oval", "star", "cyclops"]
MOOD_NAMES = ["smile", "o", "hungry"]


def eyes_moods_sheet(path: str, scale: int = 5):
    items, labels = [], []
    bodies = [0, 1, 2, 3, 5, 4, 0, 1]
    pals = [0, 1, 2, 3, 4, 12, 7, 15]
    for e in range(8):
        for m in range(3):
            items.append(Pheno(body=bodies[e], eyes=e, head=0, pattern=0, tail=0,
                               palette=pals[e], aura=0, mood=m))
            labels.append(f"{EYE_NAMES[e]} · {MOOD_NAMES[m]}")
    grid_sheet(path, items, 6, scale, labels)


def silhouettes_sheet(path: str, seed: int = 11, scale: int = 5):
    rnd = random.Random(seed)
    items = []
    for i in range(16):
        p = random_pheno(rnd, 40 + i)
        p.body = i % 6
        if i >= 12:
            p.stage = (0, 1, 2, 2)[i - 12]
        items.append(p)
    grid_sheet(path, items, 8, scale, bg=(20, 18, 28), fill=(38, 36, 52), silhouette=True)


def mix(a: Pheno, b: Pheno, rnd: random.Random, seed: int) -> Pheno:
    pick = lambda x, y: x if rnd.random() < 0.5 else y  # noqa: E731
    return Pheno(body=pick(a.body, b.body), eyes=pick(a.eyes, b.eyes), head=pick(a.head, b.head),
                 pattern=pick(a.pattern, b.pattern), tail=pick(a.tail, b.tail),
                 palette=pick(a.palette, b.palette), aura=pick(a.aura, b.aura), seed=seed)


def breed_sheet(path: str, rows: int = 3, seed: int = 21, scale: int = 6):
    """Parent + parent = hybrid & its twin (paletteShift 1)."""
    rnd = random.Random(seed)
    cs = S * scale
    gap = 56
    w = 24 + 4 * cs + 3 * gap + 24
    h = 24 + rows * (cs + 40) + 8
    bg = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(bg)
    f = font(44)
    small = font(18)
    for r in range(rows):
        a = random_pheno(rnd, 100 + r)
        b = random_pheno(rnd, 200 + r)
        c = mix(a, b, rnd, 300 + r)
        twin = Pheno(**{**c.__dict__, "shift": 1})
        y = 24 + r * (cs + 40)
        items = [(a, "твій"), (b, "друга"), (c, "гібрид"), (twin, "близнюк друга")]
        for i, (p, label) in enumerate(items):
            x = 24 + i * (cs + gap)
            card(d, x, y, cs, cs, CARD if i < 2 else (232, 240, 255))
            img = render(p, scale)
            bg.paste(img, (x, y), img)
            d.text((x + cs / 2, y + cs + 18), label, fill=INK, font=small, anchor="mm")
        for i, sym in enumerate(["+", "=", "&"]):
            x = 24 + (i + 1) * (cs + gap) - gap / 2
            d.text((x, y + cs / 2), sym, fill=(150, 142, 128), font=f, anchor="mm")
    bg.save(path)


if __name__ == "__main__":
    outdir = sys.argv[1] if len(sys.argv) > 1 else "out"
    sheet(f"{outdir}/sheet.png")
    stages_sheet(f"{outdir}/stages.png")
    eyes_moods_sheet(f"{outdir}/eyes_moods.png")
    silhouettes_sheet(f"{outdir}/silhouettes.png")
    breed_sheet(f"{outdir}/twins.png", rows=4)
    breed_sheet(f"{outdir}/breeding.png")
    render_icon().save(f"{outdir}/app-icon.png")
    print("saved", outdir)
