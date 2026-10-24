"""Golden render vectors: phenotype -> 32x32 RGBA pixels (hex), for the TS and Swift ports.

Covers every variant of every gene, palette shifts, all moods, all growth stages
(with every body / head / tail / pattern at each stage) and the silhouette mode.
Each case: {"pheno": {...}, "silhouette": bool, "sha256", "rgba_hex"}.
"""
import hashlib
import json
import random

from render import (S, Pheno, random_pheno, render_raw, render_room, render_jump_rope,
                    render_glyph, GLYPHS, JR_FRAMES)

cases = []  # (pheno, silhouette)
rnd = random.Random(99)
# every variant of every gene at least once
for gene, n in [("body", 6), ("eyes", 8), ("head", 8), ("pattern", 6), ("tail", 6),
                ("palette", 16), ("aura", 4)]:
    for v in range(n):
        p = random_pheno(rnd, len(cases))
        setattr(p, gene, v)
        cases.append((p, False))
for i in range(20):  # twins
    p = random_pheno(rnd, 500 + i)
    p.shift = 1 + i % 2
    cases.append((p, False))
for e in range(8):  # moods x eyes
    for m in range(3):
        p = random_pheno(rnd, 600 + e * 3 + m)
        p.eyes, p.mood = e, m
        cases.append((p, False))
for st in range(3):  # stages: every body, head, tail and pattern at each young stage
    for v in range(8):
        p = random_pheno(rnd, 700 + st * 10 + v)
        p.stage = st
        p.body, p.head = v % 6, v
        p.tail, p.pattern = v % 6, (v + 3) % 6
        p.mood = v % 3
        cases.append((p, False))
for i in range(24):  # silhouettes: every body at every stage
    p = random_pheno(rnd, 800 + i)
    p.body, p.stage = i % 6, i // 6
    p.head, p.tail, p.eyes = i % 8, i % 6, (i * 3) % 8
    cases.append((p, True))
# ---- living world (appended; the cases above are unchanged v2)
lw = random.Random(2026)
for st in (3, 2, 1, 0):  # every weather at every stage
    for w in range(6):
        p = random_pheno(lw, 900 + st * 10 + w)
        p.stage, p.weather, p.body, p.eyes = st, w, (w + st) % 6, (0, 1, 3, 7, 5, 4)[w]
        cases.append((p, False))
for it in range(1, 10):  # every care item, adult + teen + baby, with and without weather
    for k, st in enumerate((3, 2, 1)):
        p = random_pheno(lw, 1000 + it * 10 + k)
        p.stage, p.item, p.body = st, it, (it + k) % 6
        p.weather = (0, 1, 2, 2, 2, 3, 3, 5, 0, 0)[it] if k != 1 else (it * 2) % 6
        cases.append((p, False))
for al in range(1, 4):  # widget-alive frames
    for k, st in enumerate((3, 2, 1, 3)):
        p = random_pheno(lw, 1100 + al * 10 + k)
        p.stage, p.alive, p.body = st, al, (al + k) % 6
        if k == 3:
            p.eyes, p.weather = 7, 1
        cases.append((p, False))
for i in range(6):  # silhouettes ignore living-world layers
    p = random_pheno(lw, 1200 + i)
    p.weather, p.item, p.alive = i, i + 1, i % 4
    cases.append((p, True))

out = []
for p, sil in cases:
    raw = render_raw(p, silhouette=sil).tobytes()
    out.append({"pheno": p.__dict__, "silhouette": sil,
                "sha256": hashlib.sha256(raw).hexdigest(), "rgba_hex": raw.hex()})

# ---- scenes: rooms (64x48), jump rope (64x48), glyphs (16x16)
scenes = []


def scene_case(kind, params, img):
    raw = img.tobytes()
    scenes.append({"kind": kind, **params, "width": img.size[0], "height": img.size[1],
                   "sha256": hashlib.sha256(raw).hexdigest(), "rgba_hex": raw.hex()})


sr = random.Random(4242)
for scene in range(7):
    for tod in (0, 1):
        for w in ((0, 1) if tod == 0 else (0, 3)):
            a, b = random_pheno(sr, 1300 + len(scenes)), random_pheno(sr, 1400 + len(scenes))
            a.stage = (3, 2, 1, 3)[len(scenes) % 4]
            b.eyes = 7 if len(scenes) % 5 == 0 else b.eyes
            furn = [1, 1, 1, 1, 1, 1] if len(scenes) % 3 else [1, 0, 1, 0, 1, 0]
            scene_case("room", {"pair": [a.__dict__, b.__dict__], "scene": scene,
                                "time_of_day": tod, "weather": w, "furniture": furn},
                       render_room((a, b), scene, tod, w, tuple(furn)))
for w in (2, 4, 5):
    a, b = random_pheno(sr, 1500 + w), random_pheno(sr, 1600 + w)
    scene_case("room", {"pair": [a.__dict__, b.__dict__], "scene": 2, "time_of_day": 0,
                        "weather": w, "furniture": [1, 1, 1, 1, 1, 1]},
               render_room((a, b), 2, 0, w))
for k, st in enumerate((3, 3, 2, 1)):
    p = random_pheno(sr, 1700 + k)
    p.stage = st
    if k == 1:
        p.eyes = 7
    for f in range(JR_FRAMES):
        scene_case("jumprope", {"pheno": p.__dict__, "frame": f}, render_jump_rope(p, f))
for g in range(len(GLYPHS)):
    scene_case("glyph", {"scene": g}, render_glyph(g))

json.dump({"size": S, "note": "RGBA row-major, scale 1", "cases": out, "scenes": scenes},
          open("golden/renders.json", "w"))
print(len(out), "cases,", len(scenes), "scenes")
