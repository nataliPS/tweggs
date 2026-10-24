import { test } from "node:test";
import assert from "node:assert/strict";
import {
  HATCH_RUSH_COST, HATCH_RUSH_DAILY_MAX, GENE_HINT_COST, SHOP_PRICE_MIN, SHOP_PRICE_MAX,
  PITY_THRESHOLD, GEN_BADGES, FREE_SLOTS, CLUB_SLOTS,
  pairingCanProduce, carrierHint, genBadges, pityHintActive, breed, express, SEASON_1,
  type Genome,
} from "../src/index.ts";

const base = (): Genome => Array.from({ length: 8 }, () => [0, 0]);
const withGene = (g: number, pair: [number, number]): Genome => { const x = base(); x[g] = pair; return x; };

test("economy constants (retro G6-G8)", () => {
  assert.equal(HATCH_RUSH_COST, 30);
  assert.equal(HATCH_RUSH_DAILY_MAX, 1);
  assert.equal(GENE_HINT_COST, 20);
  assert.deepEqual([SHOP_PRICE_MIN, SHOP_PRICE_MAX], [100, 300]);
  assert.equal(PITY_THRESHOLD, 15);
  assert.deepEqual(GEN_BADGES, [5, 10]);
  assert.equal(FREE_SLOTS, 8);
  assert.equal(CLUB_SLOTS, 30);
});

test("pairingCanProduce: recessive needs a copy from each parent", () => {
  // palette night (12, dom 3) is recessive to mint (0, dom 5)
  const carrier = withGene(5, [0, 12]);
  const plain = withGene(5, [0, 0]);
  assert.equal(pairingCanProduce(carrier, carrier, 5, 12), true);
  assert.equal(pairingCanProduce(carrier, plain, 5, 12), false);
  assert.equal(pairingCanProduce(plain, plain, 5, 12), false);
  // mint is expressed by any pair containing it
  assert.equal(pairingCanProduce(carrier, plain, 5, 0), true);
  // night beats tangerine (13, dom 2)
  assert.equal(pairingCanProduce(withGene(5, [12, 0]), withGene(5, [13, 13]), 5, 12), true);
});

test("pairingCanProduce agrees with brute-force breeding (mutation-free)", () => {
  const a: Genome = [[0, 1], [6, 0], [0, 4], [1, 2], [4, 3], [12, 9], [0, 1], [2, 6]];
  const b: Genome = [[2, 3], [0, 6], [1, 2], [0, 4], [2, 4], [0, 12], [2, 0], [1, 8]];
  const seen = new Set<string>();
  for (let i = 0; i < 2000; i++) {
    const r = breed({ parentA: { id: "a", genome: a }, parentB: { id: "b", genome: b }, nonce: "n" + i, unlockedMutations: [] });
    express(r.genome).forEach((v, g) => seen.add(`${g}:${v}`));
  }
  for (const e of SEASON_1.entries) {
    assert.equal(pairingCanProduce(a, b, e.gene, e.variant), seen.has(`${e.gene}:${e.variant}`), `${e.gene}:${e.variant}`);
  }
});

test("carrierHint: either copy, ascending indices", () => {
  const col = [withGene(4, [4, 0]), withGene(4, [0, 0]), withGene(4, [1, 4]), withGene(4, [4, 4])];
  assert.deepEqual(carrierHint(col, { gene: 4, variant: 4 }), [0, 2, 3]);
  assert.deepEqual(carrierHint(col, { gene: 4, variant: 1 }), [2]);
  assert.deepEqual(carrierHint([], { gene: 4, variant: 4 }), []);
});

test("pity hint threshold", () => {
  assert.equal(pityHintActive(14), false);
  assert.equal(pityHintActive(15), true);
});

test("genBadges ladder", () => {
  assert.deepEqual(genBadges(0), []);
  assert.deepEqual(genBadges(4), []);
  assert.deepEqual(genBadges(5), [5]);
  assert.deepEqual(genBadges(9), [5]);
  assert.deepEqual(genBadges(10), [5, 10]);
  assert.deepEqual(genBadges(99), [5, 10]);
});
