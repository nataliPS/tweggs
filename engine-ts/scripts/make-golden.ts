// Generates golden/vectors.json (consumed by engine-ts tests and MixlingsKit tests)
// and copies it into MixlingsKit/Tests/MixlingsGenomeTests/Resources/.
// Usage: npm run golden

import { mkdirSync, writeFileSync, copyFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  CATALOG, GENE_COUNT, GENE_KEYS, breed, express, rarity, starter, fnv1a32, hex8, mulberry32,
  type Genome, type Mutation, type BreedInput,
} from "../src/index.ts";

const here = dirname(fileURLToPath(import.meta.url));
const outPath = resolve(here, "../golden/vectors.json");
const swiftRes = resolve(here, "../../MixlingsKit/Tests/MixlingsGenomeTests/Resources/vectors.json");

// Case generation uses its own fixed-seed rng so the file is reproducible.
const gen = mulberry32(fnv1a32("mixlings-golden-v1"));
const pick = <T>(xs: readonly T[]): T => xs[gen.int(xs.length)];

function randomGenome(allowMutationOnly: boolean): Genome {
  const g: Genome = [];
  for (let i = 0; i < GENE_COUNT; i++) {
    const pool = CATALOG[i].variants.map((v, idx) => ({ v, idx })).filter((x) => allowMutationOnly || !x.v.mutationOnly);
    g.push([pick(pool).idx, pick(pool).idx]);
  }
  return g;
}

const allMutations: Mutation[] = [];
CATALOG.forEach((gene, gi) => gene.variants.forEach((v, vi) => { if (v.mutationOnly) allMutations.push({ gene: gi, variant: vi }); }));

function randomUnlocked(): Mutation[] {
  const n = 1 + gen.int(4);
  const set = new Map<string, Mutation>();
  for (let i = 0; i < n; i++) { const m = pick(allMutations); set.set(`${m.gene}:${m.variant}`, m); }
  return [...set.values()].sort((a, b) => a.gene - b.gene || a.variant - b.variant);
}

const ID_STYLES = [
  () => "m_" + hex8(gen.next()),
  () => "mx-" + gen.int(100000),
  () => "Creature" + gen.int(50),
  () => pick(["ž", "é", "日本", "🐣", "ß", "Ω"]) + gen.int(1000),
  () => "m_" + gen.int(10),
];
const randomId = () => pick(ID_STYLES)();

const breeding: unknown[] = [];
let mutatedCount = 0;
for (let i = 0; breeding.length < 50; i++) {
  const withMut = i % 2 === 1;
  let idA = randomId(), idB = randomId();
  while (idB === idA) idB = randomId();
  const ownerA = "player_" + gen.int(1000);
  const ownerB = i % 10 === 7 ? ownerA : "player_" + (1000 + gen.int(1000)); // some same-owner cases
  let nonce = pick(["", "n", "nonce-" + gen.int(1e6), hex8(gen.next()) + hex8(gen.next()), "ü-" + gen.int(99)]);
  const unlockedMutations = withMut ? randomUnlocked() : [];
  const input: BreedInput = {
    parentA: { id: idA, genome: randomGenome(i % 5 === 0), owner: ownerA },
    parentB: { id: idB, genome: randomGenome(i % 7 === 0), owner: ownerB },
    nonce,
    unlockedMutations,
  };
  // Guarantee a healthy share of actually-mutated vectors: for every 4th mutation case, search a nonce that mutates.
  if (withMut && i % 4 === 1) {
    for (let k = 0; k < 500; k++) {
      input.nonce = nonce + "#" + k;
      if (breed(input).mutation) break;
    }
  }
  const r = breed(input);
  if (r.mutation) mutatedCount++;
  breeding.push({
    name: `breed_${String(breeding.length).padStart(2, "0")}`,
    input,
    expected: {
      id: r.id,
      seedHex: r.seedHex,
      genome: r.genome,
      expressed: express(r.genome),
      rarity: rarity(r.genome),
      mutation: r.mutation,
      paletteShift: r.paletteShift,
    },
  });
}

const starters: unknown[] = [];
for (let i = 0; i < 20; i++) {
  const playerId = i < 3 ? ["", "p", "игрок"][i] : "player_" + hex8(gen.next());
  const slot = i % 4;
  const genome = starter(playerId, slot);
  starters.push({ name: `starter_${String(i).padStart(2, "0")}`, input: { playerId, slot }, expected: { genome, expressed: express(genome), rarity: rarity(genome) } });
}

const hashes = ["", "a", "foobar", "|", "a|b|n", "é", "日本語", "🐣", "starter|p|0"].map((input) => ({ input, value: fnv1a32(input), hex: hex8(fnv1a32(input)) }));

const rngSeqs = [0, 42, 0xdeadbeef].map((seed) => {
  const r = mulberry32(seed);
  const next = Array.from({ length: 10 }, () => r.next());
  const r2 = mulberry32(seed);
  const int7 = Array.from({ length: 10 }, () => r2.int(7));
  const r3 = mulberry32(seed);
  const float = Array.from({ length: 5 }, () => r3.float());
  return { seed, next, int7, float };
});

const vectors = {
  specVersion: "0.1",
  generator: "engine-ts/scripts/make-golden.ts",
  catalog: CATALOG.map((g, i) => ({ index: i, key: GENE_KEYS[i], variants: g.variants })),
  hashes,
  rng: rngSeqs,
  breeding,
  starters,
};

mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(vectors, null, 2) + "\n");
mkdirSync(dirname(swiftRes), { recursive: true });
copyFileSync(outPath, swiftRes);
console.log(`wrote ${outPath}\n  breeding=${breeding.length} (mutated=${mutatedCount}) starters=${starters.length}\ncopied -> ${swiftRes}`);
