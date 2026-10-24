"""Golden render vectors: phenotype -> 32x32 RGBA pixels (hex), for the TS and Swift ports.

Covers every variant of every gene, palette shifts, all moods, all growth stages
(with every body / head / tail / pattern at each stage) and the silhouette mode.
Each case: {"pheno": {...}, "silhouette": bool, "sha256", "rgba_hex"}.
"""
import hashlib
import json
import random

from render import S, Pheno, random_pheno, render_raw

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

out = []
for p, sil in cases:
    raw = render_raw(p, silhouette=sil).tobytes()
    out.append({"pheno": p.__dict__, "silhouette": sil,
                "sha256": hashlib.sha256(raw).hexdigest(), "rgba_hex": raw.hex()})
json.dump({"size": S, "note": "RGBA row-major, scale 1", "cases": out},
          open("golden/renders.json", "w"))
print(len(out), "cases")
