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
    # state eyes (living world, not genes): never chosen by the genome
    8: sprite(["..K", "KK.", "..K"]),                     # squint > < (heat)
    9: sprite(["K..K", ".KK."]),                          # closed, asleep (night)
}
EYE_MIRROR = {0: False, 1: False, 2: True, 3: True, 4: False, 5: False, 6: False, 7: False,
              8: True, 9: True}

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


def stamp_blown(canvas, x0, y0, rows, ref_y):
    """Wind: rows above ref_y lean right by (ref_y - y + 1) // 2."""
    for (x, y, ch) in sprite(rows):
        yy = y0 + y
        dx = (ref_y - yy + 1) // 2 if yy < ref_y else 0
        put(canvas, x0 + x + dx, yy, ROLE[ch], ch != "a")


def draw_head(canvas, v, a, stage, wind=False):
    part = HEADS.get(stage, {}).get(v)
    if part:
        x0, dy0, rows = part
        if wind:
            stamp_blown(canvas, x0, a["top"] + dy0, rows, a["top"])
        else:
            stamp(canvas, x0, a["top"] + dy0, rows)


def draw_tail(canvas, v, a, stage, wind=False):
    part = TAILS.get(stage, {}).get(v)
    if part:
        dx0, dy0, rows = part
        tx, ty = a["tail"]
        if wind:
            stamp_blown(canvas, tx + dx0, ty + dy0, rows, ty)
        else:
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
    if v in (7, 10):  # cyclops (open / closed): one centred eye (x 13..18)
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
    bx = 16 + dx + (w + 1) // 2 + 1 if eyes not in (7, 10) else 21
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
    weather: int = 0  # living world: 0 none, 1 rain, 2 heat, 3 snow, 4 wind, 5 night
    item: int = 0     # care item: 0 none, 1 umbrella, 2 bottle, 3 fan, 4 sun hat, 5 scarf,
    #                   6 beanie, 7 blanket, 8 jump rope, 9 juice box
    alive: int = 0    # widget-alive frame: 0 none, 1 charging, 2 low power, 3 morning


def build(p: Pheno, silhouette: bool = False, face=None) -> dict:
    """The role canvas: {(x, y): Px}. `face` = (eyes, mood) override (scenes)."""
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
    eyes, mood, wind = p.eyes, p.mood, False
    if face is not None:
        eyes, mood = face
    elif not silhouette:  # living-world state layers (colour mode only)
        eyes, mood = state_face(p)
        wind = state_weather(p)[0] == WIND
    draw_tail(canvas, p.tail, a, stage, wind)
    for pt in pts(mask):
        canvas[pt] = Px("base", True)
    draw_head(canvas, p.head, a, stage, wind)
    for pt in pts(mask):  # body over head base so ears tuck behind
        canvas.setdefault(pt, Px("base", True))
    apply_pattern(canvas, mask, p.pattern, a)
    shade_body(canvas, mask)
    outline(canvas)
    draw_eyes(canvas, eyes, a)
    if not silhouette:
        draw_face(canvas, mask, eyes, mood, a)
    return canvas


def creature_layers(p: Pheno, face=None, plain: bool = False, aura: bool = True) -> list:
    """Colour creature as an ordered paint list [(x, y, rgb)] in 32x32 coordinates
    (later entries win). `plain`: no living-world layers (scenes pass their own `face`)."""
    canvas = build(p, False, face)
    behind, front = [], []
    if not plain:
        canvas, behind, front = living(p, canvas)
    pal = palette(p.palette, p.shift)
    out = []
    if p.stage == ADULT and aura:
        for (x, y, role) in draw_aura(p.aura, p.seed):
            if 0 <= x < S and 0 <= y < S and (x, y) not in canvas:
                out.append((x, y, pal[role]))
    for (x, y, rgb) in behind:
        if 0 <= x < S and 0 <= y < S and (x, y) not in canvas:
            out.append((x, y, rgb))
    for (x, y) in pts(set(canvas)):
        out.append((x, y, pal[canvas[(x, y)].role]))
    for (x, y, rgb) in front:
        if 0 <= x < S and 0 <= y < S:
            out.append((x, y, rgb))
    return out


def render_raw(p: Pheno, silhouette: bool = False) -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = img.load()
    if silhouette:  # one colour, knocked-out eyes, no aura
        for (x, y), v in build(p, True).items():
            if not v.knock:
                px[x, y] = (255, 255, 255, 255)
        return img
    for (x, y, rgb) in creature_layers(p):
        px[x, y] = (*rgb, 255)
    return img


def render(p: Pheno, scale: int = 8, silhouette: bool = False) -> Image.Image:
    return render_raw(p, silhouette).resize((S * scale, S * scale), Image.NEAREST)


# ---------------------------------------------------------------- living world
# docs/living-world-spec.md §1 weather, §8 jump rope, §9 pair life, §13 alive.
# Everything below is explicit tables + integer maths (no floats, no RNG except
# Mulberry), so the TS / Swift ports stay pixel-identical.
NONE, RAIN, HEAT, SNOW, WIND, NIGHT = 0, 1, 2, 3, 4, 5
I_UMBRELLA, I_BOTTLE, I_FAN, I_HAT, I_SCARF, I_BEANIE, I_BLANKET, I_ROPE, I_JUICE = range(1, 10)
A_CHARGING, A_LOWPOWER, A_MORNING = 1, 2, 3
EYE_SQUINT, EYE_CLOSED, EYE_CLOSED_CYCLOPS = 8, 9, 10
EYES[EYE_CLOSED_CYCLOPS] = sprite(["K....K", ".KKKK."])
EYE_MIRROR[EYE_CLOSED_CYCLOPS] = False

# One colour table for all props (chars are shared by every living-world sprite).
LW = {
    "o": (52, 40, 70),    # ink outline
    "w": (255, 255, 255), "k": (92, 80, 112),
    "r": (255, 107, 122), "R": (214, 72, 98),
    "y": (255, 214, 90), "Y": (232, 170, 52),
    "b": (112, 172, 255), "B": (70, 118, 222),
    "c": (196, 232, 255), "t": (150, 200, 255), "q": (170, 196, 230),
    "g": (126, 212, 140), "G": (72, 160, 102),
    "n": (196, 138, 86), "N": (146, 96, 58),
    "p": (176, 146, 255), "P": (124, 98, 214),
    "s": (244, 214, 156), "S": (208, 172, 108),
    "e": (226, 224, 236), "E": (150, 148, 170),
    "m": (255, 176, 204), "M": (230, 120, 160),
    "l": (255, 244, 200),
    "T": (214, 120, 80), "U": (170, 88, 60),
}


def lw_sprite(x0, y0, rows, out, cmap=None):
    """Append (x, y, rgb) for every non-'.' char of an ASCII sprite."""
    cm = cmap or LW
    for (x, y, ch) in sprite(rows):
        out.append((x0 + x, y0 + y, cm[ch]))


def row_ext(mask, y):
    xs = [x for x, yy in pts(mask) if yy == y]
    return (min(xs), max(xs)) if xs else (16, 15)


# --- weather particles (world coordinates, drawn behind the creature)
RAIN_DROPS = [(2, 3), (7, 9), (12, 1), (27, 4), (22, 0), (29, 12), (3, 17), (25, 18),
              (18, 6), (5, 24), (28, 23), (10, 13)]
SNOW_FLAKES = [(3, 4), (10, 1), (27, 3), (22, 9), (29, 15), (2, 13), (6, 21), (27, 24),
               (17, 2)]
WIND_LINES = [(0, 8, 6), (1, 15, 4), (0, 21, 5), (2, 26, 3)]  # x, y, length
SHEEN = [(-6, -4), (5, -6), (7, 3), (-8, 3)]                   # rel. (16, mid_y)

ZZZ_ROWS = ["pppp...", "..p....", ".p.....", "pppp...", "....ppp", ".....p.", "....ppp"]
BANG = [".ooooo.", "owwrwwo", "owwrwwo", "owwrwwo", "owwwwwo", "owwrwwo", ".ooooo.",
        "..oo...", ".o....."]
BOLT = [".oooo", "oyyo.", "oyyoo", ".oyyo", "..oyo", "..oo."]
SWEAT = [".o..", "oco.", "otco", ".oo."]
SUN = ["...y...", ".y.y.y.", "..yyy..", "yyyYyyy", "..yyy..", ".y.y.y.", "...y..."]
MOON = [".yy.", "yy..", "yy..", ".yy."]
LEAF = [".g", "gG", "G."]
FLAKE = [".w.", "wqw", ".w."]

# --- care items (body coordinates; x0 / y0 are resolved from anchors)
UMBRELLA = ["........oo........",
            "......orryyo......",
            "....orrryyyyyo....",
            "..orrrryyyyyyrro..",
            ".orrrrryyyyyyrrro.",
            "oRRRRRRYYYYYYRRRRo",
            ".oooo..oooo..oooo."]
BOTTLE = [".oo.", "oBBo", ".oo.", "otto", "otco", "otto", "oooo"]
FAN = [".ooooooo.",
       "orrwrrwro",
       "orwrrwrro",
       ".orrwrro.",
       "..orrro..",
       "...oro...",
       "....o....",
       "....N....",
       "....N...."]
SUN_HAT = ["....oooooooo....",
           "...osssssssso...",
           "...orrrrrrrro...",
           "oooosssssssoooo.",
           "osssssssssssssso",
           ".oooooooooooooo."]
BEANIE = [".....oo.....",
          "....owwo....",
          "...oorroo...",
          "..orrrrrro..",
          ".orrrrrrrro.",
          ".owRwRwRwRo.",
          ".oooooooooo."]
JUICE = ["w.......",
         ".w......",
         "..oooooo",
         "..oggggo",
         "..ogwwgo",
         "..ogwwgo",
         "..oGGGGo",
         "..oooooo"]
HANDLE = ["oo", "yo", "yo", "oo"]


def state_weather(p):
    """Effective (weather, item) after the widget-alive override (§13)."""
    w, it = p.weather, p.item
    if p.alive == A_CHARGING:
        it = I_JUICE
    elif p.alive == A_LOWPOWER:
        w, it = NIGHT, I_BLANKET
    return w, it


def state_face(p):
    """(eyes, mood) after weather / alive expressions."""
    w, _ = state_weather(p)
    cyc = p.eyes == 7
    if w == NIGHT:
        return (EYE_CLOSED_CYCLOPS if cyc else EYE_CLOSED), 0
    if p.alive == A_MORNING:
        return (7 if cyc else 3), 1
    if p.alive == A_CHARGING:
        return (7 if cyc else 3), 0
    if w == HEAT:
        return (7 if cyc else EYE_SQUINT), 1
    if w == RAIN:
        return (7 if cyc else 3), 0
    if w == SNOW:
        return p.eyes, 2
    return p.eyes, p.mood


def rope_arc(x0, x1, hy, apex, out, rgb):
    """Integer parabola from (x0, hy) to (x1, hy) through apex at the middle,
    gaps filled vertically so the rope reads as one line."""
    half = (x1 - x0) // 2
    cx = x0 + half
    prev = None
    for x in range(x0, x1 + 1):
        d = x - cx
        y = hy + ((apex - hy) * (half * half - d * d)) // (half * half)
        out.append((x, y, rgb))
        if prev is not None and abs(y - prev) > 1:
            step = 1 if y > prev else -1
            for yy in range(prev + step, y, step):
                out.append((x, yy, rgb))
        prev = y


def item_layer(p, it, mask, a, front, behind):
    top, bottom, mid = a["top"], a["bottom"], a["mid_y"]
    lx, rx = row_ext(mask, mid)
    if it == I_UMBRELLA:  # tilted to the right, handle in the right paw
        y0 = max(0, top - 11)
        lw_sprite(10, y0, UMBRELLA, front)
        hx = min(rx, 24)
        for y in range(y0 + 6, mid + 2):
            front.append((hx, y, LW["N"]))
        front += [(hx - 1, mid + 2, LW["N"]), (hx - 2, mid + 1, LW["N"])]
    elif it == I_BOTTLE:
        lw_sprite(rx - 1, mid - 2, BOTTLE, front)
    elif it == I_FAN:
        lw_sprite(max(0, lx - 7), mid - 7, FAN, front)
    elif it == I_HAT:
        lw_sprite(8, top - 4, SUN_HAT, front)
    elif it == I_BEANIE:
        lw_sprite(10, top - 4, BEANIE, front)
    elif it == I_SCARF:
        sy = a["eye_y"] + 5
        for y in (sy, sy + 1):
            l, r = row_ext(mask, y)
            for x in range(l - 1, r + 2):
                ch = "w" if (x + y) % 4 == 0 else ("R" if y == sy + 1 else "r")
                front.append((x, y, LW[ch]))
            front += [(l - 2, y, LW["o"]), (r + 2, y, LW["o"])]
        l, r = row_ext(mask, sy + 1)
        for x in range(l - 1, r + 2):
            front.append((x, sy + 2, LW["o"]))
        tx = r - 4
        tail = ["orro", "orwo", "orro", "orRo"][:max(1, min(4, bottom - sy - 2))] + ["oooo"]
        for i, row in enumerate(tail):  # tail clipped to the body (short on babies)
            lw_sprite(tx, sy + 2 + i, [row], front)
    elif it == I_BLANKET:
        y0 = mid + 2
        for y in range(y0, bottom + 3):
            l, r = (lx - 2, rx + 2)
            for x in range(l, r + 1):
                if y == y0 or x in (l, r) or y == bottom + 2:
                    if not (y == y0 and x in (l, r)):
                        front.append((x, y, LW["o"]))
                    continue
                ch = "p" if ((x - l) // 3 + (y - y0) // 3) % 2 == 0 else "P"
                if y == y0 + 1:
                    ch = "w"
                front.append((x, y, LW[ch]))
    elif it == I_ROPE:
        hl, hr = lx - 3, rx + 2
        lw_sprite(hl, mid - 1, HANDLE, front)
        lw_sprite(hr, mid - 1, HANDLE, front)
        rope_arc(hl, hr + 1, mid - 1, 0, behind, LW["M"])
    elif it == I_JUICE:  # straw tip at the right corner of the mouth
        lw_sprite(18, mouth_y(p, a), JUICE, front)


def mouth_y(p, a):
    eyes, _ = state_face(p)
    spr, x0, y0, w, h, dx = eye_layout(eyes, a)
    return y0 + h + (1 if h >= 3 else 2)


def shift_canvas(canvas, dx, dy):
    out = {}
    for (x, y) in sorted(canvas):
        nx, ny = x + dx, y + dy
        if 0 <= nx < S and 0 <= ny < S:
            out[(nx, ny)] = canvas[(x, y)]
    return out


def stretch_canvas(canvas, ref_y):
    """Morning stretch: rows <= ref_y move up one, row ref_y is kept twice."""
    out = {}
    for (x, y) in sorted(canvas):
        if y >= ref_y:
            out[(x, y)] = canvas[(x, y)]
    for (x, y) in sorted(canvas):
        if y <= ref_y and y - 1 >= 0:
            out[(x, y - 1)] = canvas[(x, y)]
    return out


def living(p: Pheno, canvas: dict):
    """Weather / care item / alive layers: (canvas, behind, front)."""
    w, it = state_weather(p)
    if w == NONE and it == 0 and p.alive == 0:
        return canvas, [], []
    behind, front = [], []
    # world particles
    if w == RAIN:
        for (x, y) in RAIN_DROPS:
            if it == I_UMBRELLA and 4 <= x <= 28 and y <= 20:
                continue
            behind += [(x, y, LW["c"]), (x, y + 1, LW["t"]), (x, y + 2, LW["b"])]
    elif w == SNOW:
        for (x, y) in SNOW_FLAKES:
            lw_sprite(x - 1, y - 1, FLAKE, behind)
    elif w == WIND:
        for (x, y, n) in WIND_LINES:
            for i in range(n):
                behind.append((x + i, y, LW["q"]))
        lw_sprite(27, 5, LEAF, behind)
    elif w == HEAT:
        lw_sprite(0, 0, SUN, behind)
    elif w == NIGHT and it != I_BLANKET:
        lw_sprite(1, 1, MOON, behind)
    if p.stage == EGG:  # eggs only get the weather around them
        if w == NIGHT:
            lw_sprite(22, 3, ZZZ_ROWS, front)
        return canvas, behind, front
    mask = body_mask(p.body, p.stage)
    a = anchors(mask)
    body_front, body_behind = [], []
    item_layer(p, it, mask, a, body_front, body_behind)
    lx, rx = row_ext(mask, a["mid_y"])
    if w == RAIN:
        for (dx, dy) in SHEEN:
            x, y = 16 + dx, a["mid_y"] + dy
            if (x, y) in mask and (x, y + 1) in mask:
                body_front += [(x, y, LW["w"]), (x, y + 1, LW["t"])]
    elif w == HEAT:
        lw_sprite(16 + a["eye_dx"] + 3, a["eye_y"] - 6, SWEAT, body_front)
    elif w == SNOW and it != I_BEANIE and it != I_HAT:
        for x in range(12, 20):
            ys = [y for xx, y in pts(mask) if xx == x]
            if ys:
                body_front.append((x, min(ys), LW["w"]))
                if 14 <= x <= 17:
                    body_front.append((x, min(ys) + 1, LW["w"]))
    if w == NIGHT:
        lw_sprite(22, max(0, a["top"] - 8), ZZZ_ROWS, front)
    if p.alive == A_CHARGING:
        lw_sprite(25, max(0, a["top"] - 6), BOLT, front)
    if p.alive == A_MORNING:
        lw_sprite(24, max(0, a["top"] - 9), BANG, front)
    # pose
    dx = dy = 0
    if w == RAIN:
        dy = -1
        b = a["bottom"] + 1
        for x in range(lx - 1, rx + 2):
            behind.append((x, b + 1, LW["t"]))
        for x in range(lx + 1, rx):
            behind.append((x, b + 2, LW["c"]))
        behind += [(lx - 3, b - 1, LW["t"]), (lx - 4, b - 2, LW["c"]),
                   (rx + 3, b - 1, LW["t"]), (rx + 4, b - 2, LW["c"])]
    elif w == SNOW:
        dx = 1
        for y in (a["mid_y"] - 1, a["mid_y"] + 1):
            behind += [(lx - 2, y, LW["q"]), (rx + 4, y, LW["q"])]
        behind += [(lx - 3, a["mid_y"], LW["q"]), (rx + 5, a["mid_y"], LW["q"])]
    if p.alive == A_MORNING and w != NIGHT:
        dx = dy = 0  # the stretch replaces the weather pose
        canvas = stretch_canvas(canvas, a["mid_y"])
        body_front = [(x, y - 1 if y <= a["mid_y"] else y, c) for (x, y, c) in body_front]
        front += [(lx - 2, a["top"] - 1, LW["q"]), (lx - 3, a["top"] - 2, LW["q"]),
                  (rx + 2, a["top"] - 1, LW["q"]), (rx + 3, a["top"] - 2, LW["q"])]
    elif dx or dy:
        canvas = shift_canvas(canvas, dx, dy)
    front = [(x + dx, y + dy, c) for (x, y, c) in body_front] + front
    behind = behind + [(x + dx, y + dy, c) for (x, y, c) in body_behind]
    return canvas, behind, front


# ---------------------------------------------------------------- scenes (64x48)
RW, RH = 64, 48
DAY, NIGHT_TIME = 0, 1
SC_CHESS, SC_PAINT, SC_CHAT, SC_NAP, SC_STARS, SC_BREAKFAST, SC_HOMEWORK = range(7)
SCENE_NAMES = ["chess", "painting", "chatting", "napping", "stargazing", "breakfast", "homework"]


class Img:
    """Opaque-or-empty RGB grid; every write is bounds-checked (portable)."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [None] * (w * h)

    def set(self, x, y, rgb, tint=None):
        if 0 <= x < self.w and 0 <= y < self.h:
            if tint is not None:
                rgb = tuple((rgb[i] * tint[i]) // 256 for i in range(3))
            self.px[y * self.w + x] = rgb

    def get(self, x, y):
        return self.px[y * self.w + x]

    def spr(self, x0, y0, rows, tint=None, cmap=None):
        cm = cmap or LW
        for (x, y, ch) in sprite(rows):
            self.set(x0 + x, y0 + y, cm[ch], tint)

    def creature(self, layers, ox, oy, mirror=False, tint=None):
        for (x, y, rgb) in layers:
            self.set(ox + (31 - x if mirror else x), oy + y, rgb, tint)

    def image(self) -> Image.Image:
        img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        p = img.load()
        for y in range(self.h):
            for x in range(self.w):
                c = self.px[y * self.w + x]
                if c is not None:
                    p[x, y] = (*c, 255)
        return img


NIGHT_TINT = (176, 168, 224)   # furniture & props at night (x/256 per channel)
CREATURE_NIGHT = (224, 220, 244)
ROOM = {  # day, night
    "wall": ((250, 236, 214), (78, 70, 118)),
    "stripe": ((242, 224, 198), (70, 63, 108)),
    "base": ((201, 162, 122), (52, 44, 82)),
    "floor": ((222, 170, 112), (104, 82, 120)),
    "plank": ((190, 136, 82), (84, 64, 100)),
    "floor_hi": ((234, 188, 132), (116, 94, 132)),
}
SKY = {  # (sky top, sky bottom) per window state
    "day": ((126, 200, 255), (176, 226, 255)),
    "night": ((24, 26, 72), (46, 44, 104)),
    "rain": ((126, 142, 172), (156, 170, 196)),
    "rain_night": ((36, 40, 70), (52, 56, 88)),
    "snow": ((176, 192, 216), (206, 216, 232)),
}
WALL_Y1, FLOOR_Y0 = 32, 34
WIN_X0, WIN_Y0, WIN_X1, WIN_Y1 = 24, 3, 39, 16
WIN_STARS = [(27, 6), (31, 9), (36, 5), (29, 13), (37, 11), (33, 7), (26, 10)]
WIN_RAIN = [(27, 5), (31, 8), (35, 6), (29, 11), (37, 12), (33, 13), (26, 13), (36, 9)]
WIN_SNOW = [(27, 6), (32, 5), (36, 8), (29, 10), (34, 12), (37, 14), (26, 14), (31, 13)]
CLOUD = [".ww..", "wwwww"]

# Furniture: 6 slots, each a table of variants (0 = empty, 1 = default).
PICTURE = ["oooooooooo",
           "onnnnnnnno",
           "onbbbbbyno",
           "onbbbbbbno",
           "onbbgbbbno",
           "onggGggbno",
           "onGgggGgno",
           "onnnnnnnno",
           "oooooooooo"]
SHELF = ["...gg.........",
         "..gGgg...o.oo.",
         "...gG...ono.oo",
         ".oooo..onoboro",
         ".oTTo..onoboro",
         ".oTUo..onoboro",
         "oooooooooooooo",
         "oNNNNNNNNNNNNo",
         "oooooooooooooo",
         ".oo.......oo..",
         ".o.........o.."]
PLANT = ["..g..g..",
         ".gGggGg.",
         "gGgGgGgg",
         ".gGggGgG",
         "gGgGgggG",
         ".gGgGgG.",
         "..gGgG..",
         "...GG...",
         ".oooooo.",
         ".oTTTTo.",
         ".oTTTUo.",
         "..oTUo..",
         "..oooo.."]
LAMP = ["..ooooo..",
        ".oyyyyyo.",
        ".oyyyyyo.",
        "oyyyyyyyo",
        "ooooooooo",
        "....o....",
        "....o....",
        "....o....",
        "....o....",
        "....o....",
        "....o....",
        "....o....",
        "....o....",
        "....o....",
        "....o....",
        "....o....",
        "....o....",
        "....o....",
        "....o....",
        "...ooo...",
        "..ooooo.."]
LAMP_LIT = {**LW, "y": LW["l"]}
BULBS = ["r", "y", "b", "g", "m"]

CHESS_TABLE = ["..o..........o..",
               ".owo........oko.",
               ".owo........oko.",
               "oooooooooooooooo",
               "owkwkwkwkwkwkwko",
               "okwkwkwkwkwkwkwo",
               "oooooooooooooooo",
               "onnnnnnnnnnnnnno",
               "oNNNNNNNNNNNNNNo",
               ".oooooooooooooo.",
               "..oNo......oNo..",
               "..oNo......oNo..",
               "..oNo......oNo..",
               "..ooo......ooo.."]
EASEL = ["......oo......",
         ".oooooooooooo.",
         ".owwwwwwwwwwo.",
         ".owwwwwwwwwwo.",
         ".owwwwwwwwwwo.",
         ".owwwwwwwwwwo.",
         ".owwwwwwwwwwo.",
         ".owwwwwwwwwwo.",
         ".oooooooooooo.",
         "oNNNNNNNNNNNNo",
         "..oNo...oNo...",
         "..oNo...oNo...",
         ".oNo.....oNo..",
         ".oNo.....oNo..",
         "oNo.......oNo.",
         "ooo.......ooo."]
EASEL_DABS = [(3, 3, 0), (4, 3, 0), (3, 4, 0), (7, 3, 1), (8, 3, 1), (8, 4, 1),
              (5, 5, 2), (6, 5, 2), (5, 6, 2), (9, 6, 3), (10, 6, 3), (4, 7, 3)]
PAINT_POT = [".oooo.", "obbrro", "oyyggo", ".oooo."]
BUBBLE = [".ooooooooo.",
          "owwwwwwwwwo",
          "owwwwwwwwwo",
          "owwwwwwwwwo",
          "owwwwwwwwwo",
          "owwwwwwwwwo",
          "owwwwwwwwwo",
          ".ooooooooo.",
          "..oo.......",
          "..o........"]
EMOTES = [
    [".r.r.", "rrrrr", "rrrrr", ".rrr.", "..r.."],     # heart
    ["..PP.", "..P.P", "..P..", "PPP..", "PPP.."],     # note
    ["..y..", ".yyy.", "yyyyy", ".y.y.", "y...y"],     # star
    ["k...k", ".....", "k...k", ".kkk.", "....."],     # laugh
    [".kkk.", "k...k", "...k.", "..k..", "..k.."],     # question
    ["g...g", ".g.g.", "..g..", ".g.g.", "g...g"],     # sparkle (cross)
]
NAP_BLANKET_Y = 33
TELESCOPE = ["......oo",
             ".....oko",
             "....okko",
             "...okko.",
             "..okko..",
             ".okko...",
             "okko....",
             "oko.....",
             ".ooN....",
             "..oNo...",
             "..oNo...",
             ".oN.No..",
             ".oN.No..",
             "oN...No.",
             "oo...oo."]
BREAKFAST_TABLE = ["................",
                   "..oo......oo....",
                   ".owwo....owwo...",
                   "oooooooooooooooo",
                   "orwrwrwrwrwrwrwo",
                   "owrwrwrwrwrwrwro",
                   "oooooooooooooooo",
                   ".oRo........oRo.",
                   ".oRo........oRo.",
                   ".oNo........oNo.",
                   ".oNo........oNo.",
                   ".oNo........oNo.",
                   ".ooo........ooo."]
PLATE_FOOD = ["..oooo..", ".oSssSo.", "oeeeeeeo", ".oooooo."]
EGG_PLATE = ["........", ".owwwo..", "oeewyweo", ".oooooo."]
CUP = ["w.w.", ".w..", "oooo", "obbo", "obbo", ".oo."]
DESK = ["......ooooo.....",
        "....oyyyyyo.....",
        "...oyyyyyyyo....",
        "...ooooooooo....",
        "oooooo..o.......",
        "owwkwwo.o..oo...",
        "owwkwwo.o.oko...",
        "oooooooooooooooo",
        "onnnnnnnnnnnnnno",
        "oNNNNNNNNNNNNNNo",
        ".oNo........oNo.",
        ".oNo........oNo.",
        ".oNo........oNo.",
        ".ooo........ooo."]
DESK_LIT = {**LW, "y": LW["l"]}


def sky_kind(tod, weather):
    night = tod == NIGHT_TIME or weather == NIGHT
    if weather == RAIN:
        return "rain_night" if night else "rain"
    if weather == SNOW:
        return "snow"
    return "night" if night else "day"


def draw_window(im, kind, weather):
    top, bot = SKY[kind]
    for y in range(WIN_Y0 + 1, WIN_Y1):
        c = top if y < (WIN_Y0 + WIN_Y1) // 2 else bot
        for x in range(WIN_X0 + 1, WIN_X1):
            im.set(x, y, c)
    if kind == "day":
        im.spr(27, 5, CLOUD)
        if weather == HEAT:
            im.spr(32, 4, ["..y..", ".yyy.", "yyyyy", ".yyy.", "..y.."])
        if weather == WIND:
            im.spr(33, 11, LEAF)
            im.spr(29, 8, [".g", "G."])
    elif kind in ("night",):
        for (x, y) in WIN_STARS:
            im.set(x, y, (255, 244, 200))
        im.spr(34, 9, MOON)
    elif kind.startswith("rain"):
        for (x, y) in WIN_RAIN:
            im.set(x, y, (200, 214, 236))
            im.set(x - 1, y + 1, (200, 214, 236))
    else:  # snow
        for (x, y) in WIN_SNOW:
            im.set(x, y, (255, 255, 255))
    frame = (255, 255, 255) if kind in ("day", "rain", "snow") else (196, 188, 228)
    mx, my = (WIN_X0 + WIN_X1) // 2, (WIN_Y0 + WIN_Y1) // 2
    for x in range(WIN_X0, WIN_X1 + 1):
        im.set(x, WIN_Y0, LW["o"])
        im.set(x, WIN_Y1, LW["o"])
        im.set(x, my, frame)
    for y in range(WIN_Y0, WIN_Y1 + 1):
        im.set(WIN_X0, y, LW["o"])
        im.set(WIN_X1, y, LW["o"])
        if WIN_Y0 < y < WIN_Y1:
            im.set(mx, y, frame)
    for x in range(WIN_X0 - 1, WIN_X1 + 2):  # sill
        im.set(x, WIN_Y1 + 1, LW["N"])
        im.set(x, WIN_Y1 + 2, LW["o"])


def draw_room_bg(im, night, lamp_on):
    k = 1 if night else 0
    for y in range(0, WALL_Y1 + 1):
        for x in range(RW):
            c = ROOM["stripe"][k] if x % 6 in (0, 1) else ROOM["wall"][k]
            im.set(x, y, c)
    for x in range(RW):
        im.set(x, WALL_Y1 + 1, ROOM["base"][k])
    for y in range(FLOOR_Y0, RH):
        for x in range(RW):
            c = ROOM["floor"][k]
            if (y - FLOOR_Y0) % 5 == 4 or (x + 7 * ((y - FLOOR_Y0) // 5)) % 21 == 0:
                c = ROOM["plank"][k]
            elif y == FLOOR_Y0:
                c = ROOM["floor_hi"][k]
            im.set(x, y, c)


def draw_furniture(im, slots, night):
    t = NIGHT_TINT if night else None
    if slots[5]:  # ceiling garland
        prev = None
        for x in range(2, 62):
            d = x - 32
            y = 1 + (3 * (900 - d * d)) // 900
            im.set(x, y, LW["N"], t)
            if prev is not None and y != prev:
                im.set(x, prev, LW["N"], t)
            prev = y
            if x % 6 == 5:
                c = LW[BULBS[(x // 6) % 5]]
                im.set(x, y + 1, c, None if night else t)
                im.set(x, y + 2, c if not night else LW["l"], None if night else t)
    if slots[0]:
        im.spr(4, 7, PICTURE, t)
    if slots[1]:
        im.spr(46, 6, SHELF, t)
    if slots[4]:  # rug (behind creatures)
        for y in range(39, 47):
            for x in range(10, 54):
                dx, dy = (x - 32) * 4, (y - 43) * 22
                r = dx * dx + dy * dy
                if r <= 88 * 88:
                    c = "M" if r > 74 * 74 else ("m" if (abs(x - 32) // 4) % 2 == 0 else "w")
                    im.set(x, y, LW[c], t)
    if slots[2]:
        im.spr(0, 27, PLANT, t)
    if slots[3]:
        if night:
            im.spr(55, 12, LAMP, None, LAMP_LIT)
        else:
            im.spr(55, 12, LAMP, t)


ROOM_CREATURE_Y = 12
LEFT_X, RIGHT_X = 0, 32


def scene_faces(scene, pa, pb):
    def f(p, eyes, mood):
        if p.eyes == 7 and eyes not in (7, EYE_CLOSED_CYCLOPS):
            eyes = 7
        if p.eyes == 7 and eyes == EYE_CLOSED:
            eyes = EYE_CLOSED_CYCLOPS
        return (eyes, mood)
    if scene == SC_CHESS:
        return f(pa, pa.eyes, 1), f(pb, pb.eyes, 0)
    if scene == SC_PAINT:
        return f(pa, 3, 0), f(pb, pb.eyes, 1)
    if scene == SC_CHAT:
        return f(pa, pa.eyes, 1), f(pb, 3, 0)
    if scene == SC_NAP:
        return f(pa, EYE_CLOSED, 0), f(pb, EYE_CLOSED, 0)
    if scene == SC_STARS:
        return f(pa, 4, 1), f(pb, 4, 1)
    if scene == SC_BREAKFAST:
        return f(pa, 3, 0), f(pb, 3, 0)
    return f(pa, pa.eyes, 0), f(pb, 2, 1)  # homework: one focused, one sleepy


def pair_seed(pa, pb, scene):
    return (pa.seed * 31 + pb.seed * 7 + scene * 101) & 0xFFFFFFFF


def draw_scene_props(im, scene, pa, pb, night):
    t = NIGHT_TINT if night else None
    if scene == SC_CHESS:
        im.spr(24, 30, CHESS_TABLE, t)
    elif scene == SC_PAINT:
        im.spr(25, 21, EASEL, t)
        cols = [palette(pa.palette, pa.shift)["base"], palette(pb.palette, pb.shift)["base"],
                palette(pa.palette, pa.shift)["accent"], palette(pb.palette, pb.shift)["accent"]]
        for (x, y, i) in EASEL_DABS:
            im.set(25 + x, 21 + y, cols[i], t)
        im.spr(36, 41, PAINT_POT, t)
    elif scene == SC_CHAT:
        rnd = Mulberry(pair_seed(pa, pb, scene))
        a, b = rnd.int(len(EMOTES)), rnd.int(len(EMOTES) - 1)
        if b >= a:
            b += 1
        im.spr(15, 2, BUBBLE, None)
        im.spr(18, 3, EMOTES[a], None)
        im.spr(38, 2, [r[::-1] for r in BUBBLE], None)
        im.spr(41, 3, EMOTES[b], None)
    elif scene == SC_NAP:
        for y in range(NAP_BLANKET_Y, 45):
            for x in range(4, 60):
                if y == NAP_BLANKET_Y or y == 44 or x in (4, 59):
                    if not ((y == NAP_BLANKET_Y or y == 44) and x in (4, 59)):
                        im.set(x, y, LW["o"], t)
                    continue
                c = "w" if y == NAP_BLANKET_Y + 1 else (
                    "p" if ((x - 4) // 4 + (y - NAP_BLANKET_Y) // 4) % 2 == 0 else "P")
                im.set(x, y, LW[c], t)
        im.spr(28, 20, ZZZ_ROWS)
    elif scene == SC_STARS:
        im.spr(28, 22, TELESCOPE, t)
    elif scene == SC_BREAKFAST:
        im.spr(24, 30, BREAKFAST_TABLE, t)
        im.spr(25, 29, PLATE_FOOD, t)
        im.spr(32, 29, EGG_PLATE, t)
    elif scene == SC_HOMEWORK:
        im.spr(24, 28, DESK, None, DESK_LIT if night else None)  # desk lamp: never tinted


def render_room(pair, scene: int, time_of_day: int = DAY, weather: int = NONE,
                furniture=(1, 1, 1, 1, 1, 1)) -> Image.Image:
    """64x48 cutaway room with the pair living a scene (§9). Opaque."""
    pa, pb = pair
    if scene == SC_STARS:
        time_of_day = NIGHT_TIME
    night = time_of_day == NIGHT_TIME or weather == NIGHT
    im = Img(RW, RH)
    draw_room_bg(im, night, bool(furniture[3]))
    draw_window(im, sky_kind(time_of_day, weather), weather)
    draw_furniture(im, furniture, night)
    fa, fb = scene_faces(scene, pa, pb)
    ct = CREATURE_NIGHT if night else None
    oy = ROOM_CREATURE_Y + (2 if scene == SC_NAP else 0)
    im.creature(creature_layers(pa, face=fa, plain=True, aura=False), LEFT_X, oy, True, ct)
    im.creature(creature_layers(pb, face=fb, plain=True, aura=False), RIGHT_X, oy, False, ct)
    draw_scene_props(im, scene, pa, pb, night)
    return im.image()


# ---------------------------------------------------------------- jump rope (§8)
# Frames 0..3: rope loop (overhead, front, under the feet, behind) with the creature
# jump synced (ground, rise, top, rise); 4: trip; 5: cheer.
JR_LOOP = [(0, 0), (1, 1), (2, 2), (3, 1)]   # (rope phase, jump pose)
JR_HEIGHT = [0, 2, 5]
JR_TRIP, JR_CHEER = 4, 5
JR_FRAMES = 6
YARD = {"sky0": (150, 214, 255), "sky1": (184, 230, 255), "sky2": (214, 242, 255),
        "fence": (255, 246, 228), "fence_s": (222, 204, 176), "grass": (132, 212, 120),
        "grass_d": (96, 178, 98), "grass_l": (170, 230, 150), "shadow": (92, 160, 92)}
YARD_GROUND = 40
YARD_CLOUDS = [(6, 5), (44, 9)]
YARD_TUFTS = [(4, 43), (13, 46), (22, 42), (40, 45), (51, 42), (59, 46), (33, 47)]
YARD_FLOWERS = [(8, 38, "r"), (56, 39, "y"), (47, 44, "m")]
BIG_CLOUD = ["..www...", ".wwwww..", "wwwwwwww"]
DIZZY = [".y.", "y.y", ".y."]
STARBURST = ["..y..", "..y..", "yyYyy", "..y..", "..y.."]


def draw_yard(im):
    for y in range(RH):
        for x in range(RW):
            if y < 14:
                c = YARD["sky0"]
            elif y < 24:
                c = YARD["sky1"]
            elif y < 30:
                c = YARD["sky2"]
            elif y < YARD_GROUND - 6:
                c = YARD["fence"] if (x % 6) in (1, 2, 3, 4) else YARD["sky2"]
                if y in (31, 32) and (x % 6) not in (1, 2, 3, 4):
                    c = YARD["fence_s"]
            elif y < YARD_GROUND - 2:
                c = YARD["grass_d"] if (x + y) % 3 == 0 else YARD["grass"]
            else:
                c = YARD["grass"] if y > YARD_GROUND - 2 else YARD["grass_l"]
            im.set(x, y, c)
    for x in range(RW):  # fence post tops
        if x % 6 in (2, 3):
            im.set(x, 29, YARD["fence"])
        if x % 6 == 4:
            for y in range(30, YARD_GROUND - 6):
                im.set(x, y, YARD["fence_s"])
    for (x, y) in YARD_CLOUDS:
        im.spr(x, y, BIG_CLOUD)
    im.spr(54, 2, SUN)
    for (x, y) in YARD_TUFTS:
        im.set(x, y, YARD["grass_d"])
        im.set(x + 1, y - 1, YARD["grass_d"])
        im.set(x + 2, y, YARD["grass_d"])
    for (x, y, c) in YARD_FLOWERS:
        im.spr(x - 1, y - 1, [".c.", "cyc", ".c."], cmap={**LW, "c": LW[c], "y": LW["y"] if c != "y" else LW["w"]})
        im.set(x, y + 1, LW["G"])


def render_jump_rope(p: Pheno, frame: int) -> Image.Image:
    """64x48 yard frame of the jump-rope mini-game."""
    im = Img(RW, RH)
    draw_yard(im)
    mask = body_mask(p.body, p.stage)
    a = anchors(mask)
    lx, rx = row_ext(mask, a["mid_y"])
    ox = 16
    base_oy = YARD_GROUND + 2 - (a["bottom"] + 1)
    if frame == JR_TRIP:
        phase, h, face = 2, 0, ((7 if p.eyes == 7 else EYE_SQUINT), 1)
    elif frame == JR_CHEER:
        phase, h, face = 0, 3, ((7 if p.eyes == 7 else 3), 1)
    else:
        phase, pose = JR_LOOP[frame % 4]
        h = JR_HEIGHT[pose]
        face = (p.eyes, 1 if pose == 2 else 0)
    oy = base_oy - h
    # ground shadow shrinks while airborne
    sw = (rx - lx) // 2 - h
    cx = ox + 16
    for x in range(cx - sw, cx + sw):
        im.set(x, YARD_GROUND + 2, YARD["shadow"])
    hl, hr = ox + lx - 3, ox + rx + 2
    hy = oy + a["mid_y"] - 1
    rope = LW["R"]
    behind, front = [], []
    if frame == JR_TRIP:  # rope tangled around the feet
        fy = YARD_GROUND + 1
        rope_arc(hl, hr + 1, hy + 2, fy + 2, front, rope)
        for (x, y) in [(cx - 6, fy - 1), (cx - 5, fy - 2), (cx + 4, fy - 1), (cx + 5, fy - 2)]:
            front.append((x, y, rope))
    elif phase == 0:
        rope_arc(hl, hr + 1, hy, max(1, oy + a["top"] - 8), front, rope)
    elif phase == 1:
        rope_arc(hl, hr + 1, hy, oy + a["mid_y"] + 5, front, rope)
    elif phase == 2:
        rope_arc(hl, hr + 1, hy, YARD_GROUND + 3, front, rope)
    else:
        rope_arc(hl, hr + 1, hy, max(1, oy + a["top"] - 5), behind, rope)
    behind = behind + [(x, y + 1, c) for (x, y, c) in behind]
    front = front + [(x, y + 1, c) for (x, y, c) in front]
    for (x, y, c) in behind:
        im.set(x, y, c)
    if frame == JR_TRIP:  # tilted: shift upper rows left by one
        layers = creature_layers(p, face=face, plain=True, aura=False)
        layers = [(x - 1 if y < a["mid_y"] else x, y, c) for (x, y, c) in layers]
        im.creature(layers, ox, oy)
        for (dx, dy) in [(-2, -4), (3, -6), (8, -4)]:
            im.spr(ox + 16 + dx - 1, oy + a["top"] + dy - 1, DIZZY)
    else:
        im.creature(creature_layers(p, face=face, plain=True, aura=False), ox, oy)
    for (x, y, c) in front:
        im.set(x, y, c)
    if frame != JR_TRIP:
        im.spr(hl, hy, HANDLE)
        im.spr(hr, hy, HANDLE)
    if frame == JR_CHEER:
        for (x, y) in [(6, 12), (52, 16), (10, 26), (49, 30)]:
            im.spr(x, y, STARBURST)
    return im.image()


# ---------------------------------------------------------------- lock-screen glyphs
# 16x16 one-colour scene glyphs (white on transparent), index = scene; 7 = jump rope.
GLYPHS = [
    ["................",  # chess knight
     "......XX........",
     ".....XXXX.......",
     "....XXXXXX......",
     "...XXX.XXXX.....",
     "..XXXXXXXXXX....",
     "..XXXXXXXXXX....",
     "...XX..XXXXX....",
     ".......XXXXX....",
     "......XXXXXX....",
     ".....XXXXXXX....",
     ".....XXXXXX.....",
     "....XXXXXXXX....",
     "...XXXXXXXXXX...",
     "...XXXXXXXXXX...",
     "................"],
    ["................",  # painting: easel + canvas
     ".......XX.......",
     "..XXXXXXXXXXXX..",
     "..X..........X..",
     "..X.XX.......X..",
     "..X.XX...XX..X..",
     "..X.....XXX..X..",
     "..X..XXX.....X..",
     "..X..........X..",
     "..XXXXXXXXXXXX..",
     "....XX....XX....",
     "....XX....XX....",
     "...XX......XX...",
     "...XX......XX...",
     "..XX........XX..",
     "................"],
    ["................",  # chatting: two bubbles
     ".XXXXXXXX.......",
     "XXXXXXXXXX......",
     "XX.X.X.XXX......",
     "XXXXXXXXXX......",
     ".XXXXXXXX.......",
     "..XX....XXXXXXX.",
     "..X....XXXXXXXXX",
     ".......XXX.X.XXX",
     ".......XXXXXXXXX",
     "........XXXXXXX.",
     "............XX..",
     ".............X..",
     "................",
     "................",
     "................"],
    ["................",  # napping: Zz + crescent pillow
     ".........XXXXX..",
     "............X...",
     "...........X....",
     "..........XXXXX.",
     "......XXX.......",
     ".......X........",
     "......XXX.......",
     "................",
     "................",
     "..XXXXXXXXXXXX..",
     ".XXXXXXXXXXXXXX.",
     ".XX..........XX.",
     ".XXXXXXXXXXXXXX.",
     "..XXXXXXXXXXXX..",
     "................"],
    ["................",  # stargazing: moon + stars
     "..........X.....",
     "....XXX...X.....",
     "...XXX..XXXXX...",
     "..XXX.....X.....",
     "..XXX.....X.....",
     "..XXX...........",
     "..XXXX.......X..",
     "...XXXXX.....X..",
     "....XXXX...XXXXX",
     ".............X..",
     "......X......X..",
     ".....XXX........",
     "......X.........",
     "................",
     "................"],
    ["................",  # breakfast: steaming cup
     "....X..X..X.....",
     ".....X..X..X....",
     "....X..X..X.....",
     "................",
     "..XXXXXXXXXX....",
     "..XXXXXXXXXXXXX.",
     "..XXXXXXXXXX..X.",
     "..XXXXXXXXXX..X.",
     "..XXXXXXXXXXXXX.",
     "..XXXXXXXXXX....",
     "...XXXXXXXX.....",
     "XXXXXXXXXXXXXXX.",
     ".XXXXXXXXXXXXX..",
     "................",
     "................"],
    ["................",  # homework: open book + pencil
     "............XX..",
     "...........XXX..",
     "..........XXX...",
     ".........XXX....",
     "........XXX.....",
     ".......XX.......",
     "................",
     ".XXXXX....XXXXX.",
     "XX...XX..XX...XX",
     "XX.XX.XXXX.XX.XX",
     "XX....XXXX....XX",
     "XX.XX.XXXX.XX.XX",
     "XXXXXXXXXXXXXXXX",
     ".......XX.......",
     "................"],
    ["................",  # jump rope
     ".....XXXXXX.....",
     "...XX......XX...",
     "..X..........X..",
     ".X....XXXX....X.",
     ".X...XXXXXX...X.",
     "XX...X.XX.X...XX",
     "XX...XXXXXX...XX",
     "XX...XXXXXX...XX",
     "X....XXXXXX....X",
     ".....XX..XX.....",
     "................",
     "...XXXXXXXXXX...",
     "................",
     "................",
     "................"],
]
GLYPH_SIZE = 16


def render_glyph(scene: int) -> Image.Image:
    img = Image.new("RGBA", (GLYPH_SIZE, GLYPH_SIZE), (0, 0, 0, 0))
    px = img.load()
    for (x, y, ch) in sprite(GLYPHS[scene]):
        px[x, y] = (255, 255, 255, 255)
    return img


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


WEATHER_NAMES = ["clear", "rain", "heat", "snow", "wind", "night"]
ITEM_NAMES = ["", "umbrella", "bottle", "fan", "sun hat", "scarf", "beanie", "blanket", "rope",
              "juice"]


def _review_six(seed=7):
    rnd = random.Random(seed)
    ps = [random_pheno(rnd, i) for i in range(24)]
    return [ps[i] for i in (0, 4, 7, 10, 14, 20)]


def weather_sheet(path: str, scale: int = 5):
    """6 creatures x 6 weather states, then every care item in its weather."""
    six = _review_six()
    items, labels = [], []
    for p in six:
        for w in range(6):
            items.append(Pheno(**{**p.__dict__, "weather": w}))
            labels.append(WEATHER_NAMES[w])
    pairs = [(RAIN, I_UMBRELLA), (HEAT, I_BOTTLE), (HEAT, I_FAN), (HEAT, I_HAT),
             (SNOW, I_SCARF), (SNOW, I_BEANIE), (NIGHT, I_BLANKET), (NONE, I_ROPE)]
    for i, (w, it) in enumerate(pairs):
        for j in range(3):
            p = six[(i + j * 2) % 6]
            items.append(Pheno(**{**p.__dict__, "weather": w, "item": it}))
            labels.append(ITEM_NAMES[it])
    items.append(Pheno(**{**six[0].__dict__, "stage": BABY, "weather": SNOW, "item": I_SCARF}))
    labels.append("baby scarf")
    items.append(Pheno(**{**six[2].__dict__, "stage": TEEN, "weather": RAIN, "item": I_UMBRELLA}))
    labels.append("teen umbrella")
    items.append(Pheno(**{**six[3].__dict__, "stage": EGG, "weather": SNOW}))
    labels.append("egg snow")
    items.append(Pheno(**{**six[4].__dict__, "stage": BABY, "weather": NIGHT}))
    labels.append("baby night")
    grid_sheet(path, items, 6, scale, labels)


def alive_sheet(path: str, scale: int = 5):
    six = _review_six()
    items, labels = [], []
    for p in six:
        for al, name in ((0, "idle"), (A_CHARGING, "charging"), (A_LOWPOWER, "low power"),
                         (A_MORNING, "morning")):
            items.append(Pheno(**{**p.__dict__, "alive": al}))
            labels.append(name)
    grid_sheet(path, items, 8, scale, labels)


def _paste_grid(path, imgs, cols, scale, labels=None, gap=12):
    w0, h0 = imgs[0].size
    cw, ch = w0 * scale, h0 * scale
    lab = 24 if labels else 0
    rows = (len(imgs) + cols - 1) // cols
    sheet = Image.new("RGB", (gap + cols * (cw + gap), gap + rows * (ch + gap + lab)), BG)
    d = ImageDraw.Draw(sheet)
    for i, im in enumerate(imgs):
        x, y = gap + (i % cols) * (cw + gap), gap + (i // cols) * (ch + gap + lab)
        big = im.resize((cw, ch), Image.NEAREST)
        sheet.paste(big, (x, y), big)
        if labels:
            d.text((x + cw / 2, y + ch + 12), labels[i], fill=INK, font=font(16), anchor="mm")
    sheet.save(path)


def rooms_sheet(path: str, scale: int = 4):
    six = _review_six()
    pairs = [(six[0], six[1]), (six[2], six[3]), (six[4], six[5])]
    imgs, labels = [], []
    for s in range(7):
        for tod, tn in ((DAY, "day"), (NIGHT_TIME, "night")):
            imgs.append(render_room(pairs[s % 3], s, tod))
            labels.append(f"{SCENE_NAMES[s]} · {tn}")
    for w in (RAIN, SNOW, HEAT, WIND):  # window weather
        imgs.append(render_room(pairs[w % 3], SC_CHAT if w != RAIN else SC_NAP, DAY, w))
        labels.append(f"window · {WEATHER_NAMES[w]}")
    _paste_grid(path, imgs, 4, scale, labels)


def jumprope_sheet(path: str, scale: int = 4):
    six = _review_six()
    names = ["rope over", "rope front", "rope under", "rope back", "trip", "cheer"]
    imgs, labels = [], []
    for p in (six[0], six[2], six[5]):
        for f in range(JR_FRAMES):
            imgs.append(render_jump_rope(p, f))
            labels.append(names[f])
    _paste_grid(path, imgs, 6, scale, labels)


def glyphs_sheet(path: str, scale: int = 8):
    imgs = [render_glyph(i) for i in range(len(GLYPHS))]
    names = SCENE_NAMES + ["jump rope"]
    w = 16 * scale
    gap = 20
    sheet = Image.new("RGB", (gap + len(imgs) * (w + gap), w + 2 * gap + 60 + w // 4 + gap),
                      (20, 18, 28))
    d = ImageDraw.Draw(sheet)
    for i, im in enumerate(imgs):
        x = gap + i * (w + gap)
        big = im.resize((w, w), Image.NEAREST)
        sheet.paste(big, (x, gap), big)
        d.text((x + w / 2, gap + w + 14), names[i], fill=(200, 196, 220), font=font(15), anchor="mm")
        small = im.resize((w // 4 * 1, w // 4), Image.NEAREST)  # ~actual lock-screen size
        sheet.paste(small, (x + w // 2 - w // 8, gap + w + 36), small)
    sheet.save(path)


if __name__ == "__main__":
    outdir = sys.argv[1] if len(sys.argv) > 1 else "out"
    sheet(f"{outdir}/sheet.png")
    stages_sheet(f"{outdir}/stages.png")
    eyes_moods_sheet(f"{outdir}/eyes_moods.png")
    silhouettes_sheet(f"{outdir}/silhouettes.png")
    breed_sheet(f"{outdir}/twins.png", rows=4)
    breed_sheet(f"{outdir}/breeding.png")
    render_icon().save(f"{outdir}/app-icon.png")
    weather_sheet(f"{outdir}/weather.png")
    alive_sheet(f"{outdir}/alive.png")
    rooms_sheet(f"{outdir}/rooms.png")
    jumprope_sheet(f"{outdir}/jumprope.png")
    glyphs_sheet(f"{outdir}/glyphs.png")
    print("saved", outdir)
