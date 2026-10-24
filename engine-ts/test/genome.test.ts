import { test } from "node:test";
import assert from "node:assert/strict";
import {
  CATALOG, GENE_COUNT, VARIANT_COUNTS,
  breed, express, expressGene, rarity, starter, tierForScore, childId, breedSeed, compareIds,
  fnv1a32, hex8, type Genome, type Mutation,
} from "../src/index.ts";

const g1: Genome = [[0, 1], [2, 3], [0, 4], [1, 2], [0, 3], [5, 9], [0, 1], [2, 6]];
const g2: Genome = [[2, 3], [0, 6], [1, 2], [0, 4], [2, 4], [0, 12], [2, 0], [1, 8]];

test("catalog has spec variant counts and valid fields", () => {
  assert.deepEqual(VARIANT_COUNTS, [6, 8, 8, 6, 6, 16, 4, 10]);
  for (const gene of CATALOG) {
    const mut = gene.variants.filter((v) => v.mutationOnly);
    assert.ok(mut.length >= 1 && mut.length <= 2, `${gene.key} mutationOnly count`);
    for (const v of mut) assert.ok(v.rarity >= 2, `${gene.key}.${v.name} mutationOnly must be rare+`);
    for (const v of gene.variants) {
      assert.ok(Number.isInteger(v.dominance) && v.dominance >= 1 && v.dominance <= 9);
      assert.ok([0, 1, 2, 3].includes(v.rarity));
      assert.match(v.name, /^[a-z]+$/);
    }
    assert.equal(new Set(gene.variants.map((v) => v.name)).size, gene.variants.length);
  }
  for (const gi of [2, 3, 4, 6]) {
    const v0 = CATALOG[gi].variants[0];
    assert.ok(["none", "plain"].includes(v0.name) && v0.rarity === 0 && !v0.mutationOnly);
  }
});

test("expression: higher dominance wins, tie -> lower index, order independent", () => {
  // body: round(6) vs bean(5) -> round
  assert.equal(expressGene(0, [0, 1]), 0);
  assert.equal(expressGene(0, [1, 0]), 0);
  // palette mint(5) vs bubblegum(5) tie -> 0
  assert.equal(expressGene(5, [1, 0]), 0);
  assert.equal(expressGene(5, [0, 1]), 0);
  // homozygous
  assert.equal(expressGene(3, [4, 4]), 4);
  for (let g = 0; g < GENE_COUNT; g++) {
    const n = CATALOG[g].variants.length;
    for (let a = 0; a < n; a++)
      for (let b = 0; b < n; b++) {
        const e = expressGene(g, [a, b]);
        assert.equal(e, expressGene(g, [b, a]));
        const da = CATALOG[g].variants[a].dominance, db = CATALOG[g].variants[b].dominance;
        assert.equal(e, da === db ? Math.min(a, b) : da > db ? a : b);
      }
  }
  assert.equal(express(g1).length, 8);
  assert.throws(() => express([[0, 0]] as Genome));
  assert.throws(() => express(g1.map((p, i) => (i === 0 ? [0, 99] : p)) as Genome));
});

test("retro G2/G3 dominance values", () => {
  const dom = (g: number, name: string) => CATALOG[g].variants.find((v) => v.name === name)!.dominance;
  assert.equal(dom(5, "night"), 4);
  assert.equal(dom(1, "star"), 3);
  assert.equal(dom(4, "flame"), 3);
  for (const gene of CATALOG) for (const v of gene.variants) if (v.mutationOnly) assert.equal(v.dominance, 7, `${gene.key}.${v.name}`);
});

test("rarity tiers boundaries", () => {
  // G1: common <=1, uncommon 2..3, rare 4..6, legendary >=7
  assert.equal(tierForScore(0), "common");
  assert.equal(tierForScore(1), "common");
  assert.equal(tierForScore(2), "uncommon");
  assert.equal(tierForScore(3), "uncommon");
  assert.equal(tierForScore(4), "rare");
  assert.equal(tierForScore(6), "rare");
  assert.equal(tierForScore(7), "legendary");
  assert.equal(tierForScore(24), "legendary");
  const allCommon: Genome = Array.from({ length: 8 }, () => [0, 0]);
  assert.deepEqual(rarity(allCommon), { score: 0, tier: "common" });
  // every gene homozygous for its legendary variant
  const allLegend: Genome = CATALOG.map((g) => {
    const i = g.variants.findIndex((v) => v.rarity === 3);
    return [i, i];
  });
  assert.deepEqual(rarity(allLegend), { score: 24, tier: "legendary" });
});

test("breed is symmetric under parent swap", () => {
  const muts: Mutation[] = [{ gene: 0, variant: 5 }, { gene: 6, variant: 3 }];
  for (let i = 0; i < 200; i++) {
    const a = { id: "m_alpha" + i, genome: g1, owner: "p1" };
    const b = { id: "m_beta" + i, genome: g2, owner: "p2" };
    const x = breed({ parentA: a, parentB: b, nonce: "n" + i, unlockedMutations: muts });
    const y = breed({ parentA: b, parentB: a, nonce: "n" + i, unlockedMutations: muts });
    assert.deepEqual(x, y);
  }
});

test("breed: child alleles come from respective ordered parents; id/seed per spec", () => {
  const r = breed({ parentA: { id: "zz", genome: g1 }, parentB: { id: "aa", genome: g2 }, nonce: "N", unlockedMutations: [] });
  // after ordering, A = "aa" (g2), B = "zz" (g1)
  for (let g = 0; g < 8; g++) {
    assert.ok(g2[g].includes(r.genome[g][0]));
    assert.ok(g1[g].includes(r.genome[g][1]));
  }
  const seed = fnv1a32("aa|zz|N");
  assert.equal(r.seedHex, hex8(seed));
  assert.equal(r.id, "c_" + hex8(fnv1a32(hex8(seed) + "|child")));
  assert.equal(r.id, childId(breedSeed("aa", "zz", "N")));
  assert.deepEqual(r.paletteShift, { aa: 0, zz: 1 });
  assert.throws(() => breed({ parentA: { id: "x", genome: g1 }, parentB: { id: "x", genome: g2 }, nonce: "", unlockedMutations: [] }));
});

test("compareIds is byte-wise UTF-8", () => {
  assert.ok(compareIds("a", "b") < 0);
  assert.ok(compareIds("ab", "a") > 0);
  assert.ok(compareIds("Z", "a") < 0);
  // U+FF5E (EF BD 9E) vs U+1F600 (F0 9F 98 80): UTF-16 order says emoji first, UTF-8 says FF5E first
  assert.ok(compareIds("～", "\u{1f600}") < 0);
});

test("mutation happens only when unlocked list non-empty", () => {
  let mutated = 0;
  const N = 2000;
  for (let i = 0; i < N; i++) {
    const base = { parentA: { id: "a", genome: g1 }, parentB: { id: "b", genome: g2 }, nonce: "k" + i };
    const none = breed({ ...base, unlockedMutations: [] });
    assert.equal(none.mutation, null);
    const withM = breed({ ...base, unlockedMutations: [{ gene: 7, variant: 9 }] });
    // inheritance part identical, mutation only touches the chosen allele
    if (withM.mutation) {
      mutated++;
      assert.equal(withM.genome[7][withM.mutation.allele], 9);
      const expected = none.genome.map((p) => [...p]);
      expected[7][withM.mutation.allele] = 9;
      assert.deepEqual(withM.genome, expected);
    } else {
      assert.deepEqual(withM.genome, none.genome);
    }
  }
  const rate = mutated / N;
  assert.ok(rate > 0.06 && rate < 0.14, `mutation rate ${rate}`);
});

test("unsorted unlockedMutations are normalised (sorted by gene, variant)", () => {
  const base = { parentA: { id: "a", genome: g1 }, parentB: { id: "b", genome: g2 } };
  const sorted: Mutation[] = [{ gene: 0, variant: 5 }, { gene: 1, variant: 7 }, { gene: 5, variant: 14 }, { gene: 5, variant: 15 }];
  const shuffled = [sorted[3], sorted[0], sorted[2], sorted[1]];
  for (let i = 0; i < 300; i++) {
    assert.deepEqual(
      breed({ ...base, nonce: "s" + i, unlockedMutations: sorted }),
      breed({ ...base, nonce: "s" + i, unlockedMutations: shuffled }),
    );
  }
});

test("starter never contains mutationOnly variants and is deterministic", () => {
  for (let p = 0; p < 100; p++) {
    for (let slot = 0; slot < 5; slot++) {
      const s = starter("player_" + p, slot);
      assert.deepEqual(s, starter("player_" + p, slot));
      s.forEach((pair, g) => pair.forEach((v) => assert.equal(CATALOG[g].variants[v].mutationOnly, false)));
    }
  }
  assert.notDeepEqual(starter("p", 0), starter("p", 1));
});
