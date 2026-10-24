"""Mixlings pixel creature renderer (prototype).

Composes a 32x32 creature from part variants:
body, eyes, head, pattern, tail, palette, aura (+ paletteShift).
Used to approve the art style; the same part data will be exported
to JSON and re-implemented in Swift for the app and widgets.
"""
from __future__ import annotations

import colorsys
import math
import random
import sys
from dataclasses import dataclass

from PIL import Image, ImageDraw, ImageFont

S = 32  # canvas size


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


# base, shade, accent, light(belly)
PALETTES = [
    ("#7ED4A6", "#4FA77E", "#FFCB5C", "#C9F2DA"),  # mint
    ("#F7A6C4", "#D2759A", "#7CC6FE", "#FFD9E7"),  # bubblegum
    ("#8FB8FF", "#5C86D6", "#FF9F68", "#D4E3FF"),  # sky
    ("#FFD36E", "#E0A93D", "#FF6F91", "#FFF0C2"),  # sunny
    ("#C3A6FF", "#9479D9", "#7EF0C8", "#E7DCFF"),  # lavender
    ("#FF9B7A", "#D9704F", "#6EE7F2", "#FFD3C4"),  # coral
    ("#9BE15D", "#6DB33A", "#FF7AD9", "#DDF7C4"),  # lime
    ("#6FD6E8", "#3FA8BC", "#FFE066", "#CDF4FA"),  # aqua
    ("#E8E2D0", "#BDB4A0", "#FF8A5B", "#FFFFFF"),  # cream
    ("#A0A8B8", "#727B8E", "#FFD166", "#D9DEE7"),  # stone
    ("#FF7AA2", "#D24F79", "#FFE27A", "#FFC6D7"),  # rose
    ("#5E6BFF", "#3C46C9", "#FF9EE5", "#B9BFFF"),  # cobalt
    ("#3D3D4E", "#26262F", "#7DF9FF", "#6A6A82"),  # night (rare)
    ("#FFB347", "#D98A1F", "#8E7CFF", "#FFE0B0"),  # tangerine
    ("#B8F2E6", "#7FC7B8", "#FF8FAB", "#E6FBF6"),  # seafoam
    ("#F2F2F2", "#C9C9D6", "#FFB3F0", "#FFFFFF"),  # ghost (rare)
]


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
        amt = 0.035 * shift
        base, shade, light = (shift_hue(c, amt) for c in (base, shade, light))
    outline = darken(shade, 0.45)
    lum = 0.299 * base[0] + 0.587 * base[1] + 0.114 * base[2]
    dark = lum < 90
    if dark:  # dark creatures get glowing eyes and a lighter outline
        outline = (18, 18, 24)
    return {
        "base": base, "shade": shade, "accent": accent, "light": light,
        "outline": outline,
        "eye": accent if dark else (34, 30, 46),
        "white": (255, 255, 255),
        "blush": (255, 140, 160),
    }


# ---------------------------------------------------------------- bodies
def ellipse(cx, cy, rx, ry):
    return {(x, y) for x in range(S) for y in range(S)
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0}


def rrect(x0, y0, x1, y1, r):
    pts = set()
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            cx = min(max(x, x0 + r), x1 - r)
            cy = min(max(y, y0 + r), y1 - r)
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 0.5:
                pts.add((x, y))
    return pts


def body_mask(v: int) -> set:
    if v == 0:   # round
        m = ellipse(16, 20, 9.5, 8.5)
    elif v == 1:  # bean (tall)
        m = ellipse(16, 19, 7.5, 10.5)
    elif v == 2:  # pear
        m = ellipse(16, 15, 6.5, 6) | ellipse(16, 22, 9.5, 7)
    elif v == 3:  # block
        m = rrect(7, 11, 24, 28, 5)
    elif v == 4:  # drop
        m = set()
        for y in range(9, 29):
            t = (y - 9) / 19
            w = 9.5 * math.sin(math.pi * min(1.0, t * 0.62 + 0.08)) ** 0.9
            for x in range(S):
                if abs(x + 0.5 - 16) <= w:
                    m.add((x, y))
    else:        # mochi (wide)
        m = ellipse(16, 22, 11.5, 6.5)
    # little feet
    bottom = max(y for _, y in m)
    for fx in (11, 12, 19, 20):
        if (fx, bottom) in m:
            m.add((fx, bottom + 1))
    return m


def anchors(mask: set) -> dict:
    ys = [y for x, y in mask if x == 16]
    top = min(ys)
    bottom = max(y for _, y in mask)
    h = bottom - top
    eye_y = top + max(3, round(h * 0.38))
    row = [x for x, y in mask if y == eye_y]
    half = (max(row) - min(row)) / 2
    eye_dx = max(2, min(4, round(half * 0.42)))
    tail_y = top + round(h * 0.68)
    tail_x = max(x for x, y in mask if y == tail_y) + 1
    return {"top": top, "bottom": bottom, "eye_y": eye_y, "eye_dx": eye_dx,
            "tail": (tail_x, tail_y), "mid_y": top + h // 2}


# ---------------------------------------------------------------- sprites
# ASCII sprites: '.' empty, roles: B base, S shade, A accent, L light,
# K eye, W white, O outline-forced
def sprite(rows):
    out = []
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                out.append((x, y, ch))
    return out


EYES = {
    0: sprite(["KK", "KK"]),                       # dots
    1: sprite([".KK.", "KWKK", "KKKK", ".KK."]),    # big round
    2: sprite(["KKK"]),                             # sleepy
    3: sprite([".K.", "K.K"]),                      # happy ^
    4: sprite(["KKK", "KWK", "KKK"]),               # sparkle
    5: sprite(["KK", "WK", "KK"]),                  # oval
    6: sprite([".K.", "KAK", ".K."]),               # star
    7: None,                                         # cyclops (special)
}
CYCLOPS = sprite([".KKKK.", "KWWKKK", "KWKKKK", "KKKKKK", ".KKKK."])

ROLE = {"B": "base", "S": "shade", "A": "accent", "L": "light",
        "K": "eye", "W": "white", "O": "outline"}


@dataclass
class Px:
    role: str
    solid: bool  # participates in outline


def put(canvas, x, y, role, solid=True):
    if 0 <= x < S and 0 <= y < S:
        canvas[(x, y)] = Px(role, solid)


def draw_head(canvas, v, a):
    t = a["top"]
    if v == 1:  # cat ears
        for side in (-1, 1):
            cx = 16 + side * 5
            for i in range(4):
                for dx in range(-(3 - i), (3 - i) + 1):
                    put(canvas, cx + dx, t - i + 1, "base")
            put(canvas, cx, t, "accent")
            put(canvas, cx, t - 1, "accent")
    elif v == 2:  # bunny ears
        for side in (-1, 1):
            cx = 16 + side * 4
            for i in range(7):
                for dx in (-1, 0, 1):
                    put(canvas, cx + dx, t - i + 1, "base")
                if 1 <= i <= 5:
                    put(canvas, cx, t - i + 1, "light")
    elif v == 3:  # horns: thick base curving outward to a point
        for side in (-1, 1):
            rows = [(0, (3, 4, 5, 6)), (-1, (4, 5, 6)), (-2, (5, 6, 7)),
                    (-3, (6, 7)), (-4, (7, 8)), (-5, (8,))]
            for dy, xs in rows:
                for dx in xs:
                    put(canvas, 16 + side * dx, t + dy, "light" if dy > -2 else "accent")
    elif v == 4:  # antenna
        for i in range(1, 5):
            put(canvas, 16, t - i, "shade")
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if abs(dx) + abs(dy) < 2:
                    put(canvas, 16 + dx, t - 6 + dy, "accent")
    elif v == 5:  # leaf sprout
        put(canvas, 16, t - 1, "shade")
        put(canvas, 16, t - 2, "shade")
        for p in [(-1, -3), (-2, -3), (-2, -4), (-3, -4), (-1, -4)]:
            put(canvas, 16 + p[0], t + p[1], "accent")
        for p in [(1, -2), (2, -3), (2, -2), (3, -3), (1, -3)]:
            put(canvas, 16 + p[0], t + p[1], "accent")
    elif v == 6:  # crest spikes
        for i, dx in enumerate((-4, 0, 4)):
            hgt = 3 if dx else 4
            for k in range(hgt):
                for w in range(-(hgt - 1 - k) // 2 - 1 + 1, (hgt - 1 - k) // 2 + 1):
                    put(canvas, 16 + dx + w, t - k, "accent")
    elif v == 7:  # halo (floating)
        for x in range(11, 22):
            if x in (11, 21):
                continue
            put(canvas, x, t - 5, "accent", solid=False)
            put(canvas, x, t - 3, "accent", solid=False)
        put(canvas, 11, t - 4, "accent", solid=False)
        put(canvas, 21, t - 4, "accent", solid=False)


def thick(canvas, tx, ty, pts, role):
    """Stamp a 2px-thick stroke so diagonal tails don't break into checkers."""
    for dx, dy in pts:
        put(canvas, tx + dx, ty + dy, role)
        put(canvas, tx + dx, ty + dy + 1, role)


def draw_tail(canvas, v, a):
    tx, ty = a["tail"]
    if v == 1:  # puff
        for p in ellipse(tx + 1.5, ty + 0.5, 2.4, 2.4):
            put(canvas, *p, "light")
    elif v == 2:  # curly
        thick(canvas, tx, ty, [(0, 0), (1, 0), (2, -1), (3, -2), (3, -3), (2, -4), (1, -4)], "base")
    elif v == 3:  # long, with a tuft
        thick(canvas, tx, ty, [(0, 0), (1, 0), (2, -1), (3, -2), (4, -3), (5, -4)], "base")
        for p in ellipse(tx + 6.5, ty - 4.5, 1.6, 1.6):
            put(canvas, *p, "accent")
    elif v == 4:  # flame
        pts = [(0, 0), (1, 0), (1, -1), (2, -1), (2, -2), (3, -2), (2, -3), (3, -4), (1, -2),
               (0, -1), (3, -3), (4, -3), (3, -5)]
        for dx, dy in pts:
            put(canvas, tx + dx, ty + dy, "accent")
    elif v == 5:  # lightning
        pts = [(0, 0), (1, 0), (1, -1), (2, -1), (2, -2), (1, -2), (1, -3), (2, -3), (3, -3),
               (3, -4), (4, -4), (4, -5), (3, -5), (5, -5), (5, -6)]
        for dx, dy in pts:
            put(canvas, tx + dx, ty + dy, "accent")


def apply_pattern(canvas, mask, v, a, seed):
    rnd = Mulberry(seed * 2654435761)
    top, bottom = a["top"], a["bottom"]
    if v == 1:  # belly
        cy = a["mid_y"] + (bottom - a["mid_y"]) * 0.45
        for p in ellipse(16, cy, 5, (bottom - top) * 0.28):
            if p in mask:
                canvas[p] = Px("light", True)
    elif v == 2:  # spots
        spots = 0
        tries = 0
        while spots < 4 and tries < 60:
            tries += 1
            x, y = rnd.choice(sorted(mask))
            if y <= a["eye_y"] + 1 and abs(x - 16) < 6:
                continue
            ok = all((x + dx, y + dy) in mask for dx in (0, 1) for dy in (0, 1))
            if ok:
                for dx in (0, 1):
                    for dy in (0, 1):
                        canvas[(x + dx, y + dy)] = Px("accent", True)
                spots += 1
    elif v == 3:  # stripes (two-pixel bands, below the face)
        for (x, y) in mask:
            if y > a["eye_y"] + 3 and (y - top) % 5 in (0, 1):
                canvas[(x, y)] = Px("accent", True)
    elif v == 4:  # two-tone cap
        for (x, y) in mask:
            if y < top + (bottom - top) * 0.3:
                canvas[(x, y)] = Px("accent", True)
    elif v == 5:  # freckles
        for dx in (-1, 1):
            for k in (0, 2):
                p = (16 + dx * (a["eye_dx"] + 1 + k // 2), a["eye_y"] + 2 + (k % 2))
                if p in mask:
                    canvas[p] = Px("shade", True)


HIGHLIGHT_ANCHOR = [(9, 14), (13, 9), (10, 12), (9, 12), (13, 9), (6, 18)]


def shade_body(canvas, mask, body_variant):
    xs = [x for x, _ in mask]
    ys = [y for _, y in mask]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    for (x, y) in mask:
        # lower-right rim shading
        if (x + 1, y + 1) not in mask or (x + 1, y) not in mask and y > cy:
            if x >= cx - 1 or y >= cy + 2:
                if canvas[(x, y)].role == "base":
                    canvas[(x, y)] = Px("shade", True)
    # highlight upper-left
    # Highlight anchor per body variant: an explicit art constant, identical in the
    # TS and Swift ports (previously picked by CPython set order among ties).
    tl = [HIGHLIGHT_ANCHOR[body_variant]]
    for (x, y) in tl:
        for p in ((x + 2, y + 2), (x + 3, y + 2), (x + 2, y + 3)):
            if p in mask and canvas[p].role == "base":
                canvas[p] = Px("white", True)


def draw_eyes(canvas, v, a):
    ey, dx = a["eye_y"], a["eye_dx"]
    if v == 7:
        for (x, y, ch) in CYCLOPS:
            put(canvas, 16 - 3 + x, ey - 2 + y, ROLE[ch])
        return
    spr = EYES[v]
    w = max(x for x, _, _ in spr) + 1
    h = max(y for _, y, _ in spr) + 1
    for side in (-1, 1):
        cx = 16 + side * dx
        x0 = cx - (w // 2) if side < 0 else cx - (w - 1) // 2
        for (x, y, ch) in spr:
            xx = x if side > 0 else (w - 1 - x)
            put(canvas, x0 + xx, ey - h // 2 + y, ROLE[ch])
    # blush
    for side in (-1, 1):
        put(canvas, 16 + side * (dx + 2), ey + 2, "blush")


def outline(canvas):
    solid = {p for p, px in canvas.items() if px.solid and px.role != "outline"}
    out = set()
    for (x, y) in solid:
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) not in canvas and 0 <= nx < S and 0 <= ny < S:
                out.add((nx, ny))
    for p in out:
        canvas[p] = Px("outline", False)


def draw_aura(img_px, v, pal, seed):
    if v == 0:
        return []
    rnd = Mulberry(seed * 7 + v)
    extra = []
    if v == 1:  # sparkles
        for _ in range(5):
            x, y = rnd.randrange(1, S - 1), rnd.randrange(1, 14)
            extra += [(x, y, "white"), (x - 1, y, "accent"), (x + 1, y, "accent"),
                      (x, y - 1, "accent"), (x, y + 1, "accent")]
    elif v == 2:  # glow ring (drawn behind)
        for a in range(0, 360, 9):
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


def render(p: Pheno, scale: int = 8) -> Image.Image:
    pal = palette(p.palette, p.shift)
    mask = body_mask(p.body)
    a = anchors(mask)
    canvas: dict = {}
    draw_tail(canvas, p.tail, a)
    for pt in mask:
        canvas[pt] = Px("base", True)
    draw_head(canvas, p.head, a)
    for pt in mask:  # body over head base so ears tuck behind
        canvas.setdefault(pt, Px("base", True))
    apply_pattern(canvas, mask, p.pattern, a, p.seed)
    shade_body(canvas, mask, p.body)
    outline(canvas)
    draw_eyes(canvas, p.eyes, a)

    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = img.load()
    behind = draw_aura(px, p.aura, pal, p.seed)
    for (x, y, role) in behind:
        if 0 <= x < S and 0 <= y < S and (x, y) not in canvas:
            c = pal[role]
            px[x, y] = (*c, 170 if p.aura == 2 else 255)
    for (x, y), v in canvas.items():
        px[x, y] = (*pal[v.role], 255)
    return img.resize((S * scale, S * scale), Image.NEAREST)


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
    return Pheno(body=rnd.randrange(6), eyes=rnd.choice([0, 1, 1, 2, 3, 4, 5, 6]),
                 head=rnd.randrange(7), pattern=rnd.randrange(6), tail=rnd.randrange(6),
                 palette=rnd.randrange(16), aura=rnd.choice([0, 0, 0, 1, 2, 3]), seed=i)


def sheet(path: str, n: int = 24, cols: int = 6, seed: int = 7, scale: int = 6):
    rnd = random.Random(seed)
    cell = S * scale + 24
    w, h = cols * cell + 24, ((n + cols - 1) // cols) * cell + 24
    bg = Image.new("RGB", (w, h), (246, 243, 236))
    d = ImageDraw.Draw(bg)
    for i in range(n):
        p = random_pheno(rnd, i)
        img = render(p, scale)
        x = 24 + (i % cols) * cell
        y = 24 + (i // cols) * cell
        d.rounded_rectangle([x - 6, y - 6, x + S * scale + 6, y + S * scale + 6], 14,
                            fill=(255, 255, 255), outline=(225, 220, 208))
        bg.paste(img, (x, y), img)
    bg.save(path)


def mix(a: Pheno, b: Pheno, rnd: random.Random, seed: int) -> Pheno:
    pick = lambda x, y: x if rnd.random() < 0.5 else y  # noqa: E731
    return Pheno(body=pick(a.body, b.body), eyes=pick(a.eyes, b.eyes), head=pick(a.head, b.head),
                 pattern=pick(a.pattern, b.pattern), tail=pick(a.tail, b.tail),
                 palette=pick(a.palette, b.palette), aura=pick(a.aura, b.aura), seed=seed)


def breed_sheet(path: str, rows: int = 3, seed: int = 21, scale: int = 6):
    """Demo of the breeding idea: parent + parent = hybrid (and its twin)."""
    rnd = random.Random(seed)
    cs = S * scale
    gap = 56
    w = 24 + 4 * cs + 3 * gap + 24
    h = 24 + rows * (cs + 40) + 8
    bg = Image.new("RGB", (w, h), (246, 243, 236))
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
            fill = (255, 255, 255) if i < 2 else (232, 240, 255)
            d.rounded_rectangle([x - 6, y - 6, x + cs + 6, y + cs + 6], 14, fill=fill,
                                outline=(225, 220, 208))
            img = render(p, scale)
            bg.paste(img, (x, y), img)
            d.text((x + cs / 2, y + cs + 18), label, fill=(110, 104, 92), font=small, anchor="mm")
        for i, sym in enumerate(["+", "=", "&"]):
            x = 24 + (i + 1) * (cs + gap) - gap / 2
            d.text((x, y + cs / 2), sym, fill=(150, 142, 128), font=f, anchor="mm")
    bg.save(path)


if __name__ == "__main__":
    outdir = sys.argv[1] if len(sys.argv) > 1 else "."
    sheet(f"{outdir}/sheet.png")
    breed_sheet(f"{outdir}/breeding.png")
    print("saved", outdir)
