import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { CATALOG, GENE_KEYS, breed, express, rarity, starter, fnv1a32, mulberry32 } from "../src/index.ts";

const v = JSON.parse(readFileSync(new URL("../golden/vectors.json", import.meta.url), "utf8"));

test("golden: catalog snapshot matches CATALOG (regenerate with npm run golden)", () => {
  assert.deepEqual(v.catalog, CATALOG.map((g, i) => ({ index: i, key: GENE_KEYS[i], variants: g.variants })));
});

test("golden: hashes and rng", () => {
  for (const h of v.hashes) assert.equal(fnv1a32(h.input), h.value);
  for (const s of v.rng) {
    const r = mulberry32(s.seed);
    assert.deepEqual(Array.from({ length: s.next.length }, () => r.next()), s.next);
  }
});

test("golden: breeding cases", () => {
  assert.equal(v.breeding.length, 50);
  for (const c of v.breeding) {
    const r = breed(c.input);
    assert.deepEqual(
      { id: r.id, seedHex: r.seedHex, genome: r.genome, expressed: express(r.genome), rarity: rarity(r.genome), mutation: r.mutation, paletteShift: r.paletteShift },
      c.expected,
      c.name,
    );
  }
});

test("golden: starter cases", () => {
  assert.equal(v.starters.length, 20);
  for (const c of v.starters) assert.deepEqual(starter(c.input.playerId, c.input.slot), c.expected.genome, c.name);
});
