"""Golden render vectors: phenotype -> 32x32 RGBA pixels (hex), for the Swift port."""
import json, random, hashlib
from render import Pheno, render, random_pheno, S

def pixels(p):
    img = render(p, scale=1)
    data = img.tobytes()
    return data

cases = []
rnd = random.Random(99)
# every variant of every gene at least once
for gene, n in [("body",6),("eyes",8),("head",8),("pattern",6),("tail",6),("palette",16),("aura",4)]:
    for v in range(n):
        p = random_pheno(rnd, len(cases))
        setattr(p, gene, v)
        cases.append(p)
for i in range(20):
    p = random_pheno(rnd, 500 + i); p.shift = 1; cases.append(p)
out = []
for p in cases:
    raw = pixels(p)
    out.append({"pheno": p.__dict__, "sha256": hashlib.sha256(raw).hexdigest(),
                "rgba_hex": raw.hex()})
json.dump({"size": S, "note": "RGBA row-major, scale 1", "cases": out},
          open("golden/renders.json", "w"))
print(len(out), "cases")
