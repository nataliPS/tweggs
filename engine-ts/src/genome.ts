// Genome logic (spec §2, §4, §5, §6).

import { CATALOG, GENE_COUNT, type Rarity } from "./catalog.ts";
import { fnv1a32, hex8 } from "./hash.ts";
import { mulberry32 } from "./rng.ts";

/** One gene: two alleles (variant indices). */
export type GenePair = [number, number];
/** 8 genes in catalog order. */
export type Genome = GenePair[];

export interface Parent {
  id: string;
  genome: Genome;
  /** Player who owns this parent. Used only for paletteShift keys; defaults to `id`. */
  owner?: string;
}

export interface Mutation {
  gene: number;
  variant: number;
}

export interface AppliedMutation extends Mutation {
  /** Which allele slot (0|1) was overwritten. */
  allele: number;
}

export interface BreedInput {
  parentA: Parent;
  parentB: Parent;
  nonce: string;
  unlockedMutations: Mutation[];
}

export interface BreedResult {
  id: string;
  genome: Genome;
  /** seed as 8-char hex (debug / server logs). */
  seedHex: string;
  /** Mutation applied, or null. */
  mutation: AppliedMutation | null;
  /** owner -> shift (0 for owner of ordered parentA, 1 for owner of parentB). */
  paletteShift: Record<string, number>;
}

export type RarityTier = "common" | "uncommon" | "rare" | "legendary";

export interface RarityResult {
  score: number;
  tier: RarityTier;
}

export class GenomeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GenomeError";
  }
}

const utf8 = new TextEncoder();

/** Byte-wise (UTF-8) lexicographic compare. Returns <0, 0, >0. */
export function compareIds(a: string, b: string): number {
  const x = utf8.encode(a);
  const y = utf8.encode(b);
  const n = Math.min(x.length, y.length);
  for (let i = 0; i < n; i++) {
    if (x[i] !== y[i]) return x[i] - y[i];
  }
  return x.length - y.length;
}

export function validateGenome(genome: Genome): void {
  if (!Array.isArray(genome) || genome.length !== GENE_COUNT) {
    throw new GenomeError(`genome must have ${GENE_COUNT} genes`);
  }
  for (let g = 0; g < GENE_COUNT; g++) {
    const pair = genome[g];
    if (!Array.isArray(pair) || pair.length !== 2) throw new GenomeError(`gene ${g} must have 2 alleles`);
    const count = CATALOG[g].variants.length;
    for (const v of pair) {
      if (!Number.isInteger(v) || v < 0 || v >= count) {
        throw new GenomeError(`gene ${g} allele ${v} out of range 0..${count - 1}`);
      }
    }
  }
}

function validateMutation(m: Mutation): void {
  if (!Number.isInteger(m.gene) || m.gene < 0 || m.gene >= GENE_COUNT) {
    throw new GenomeError(`mutation gene ${m.gene} out of range`);
  }
  const count = CATALOG[m.gene].variants.length;
  if (!Number.isInteger(m.variant) || m.variant < 0 || m.variant >= count) {
    throw new GenomeError(`mutation variant ${m.variant} out of range for gene ${m.gene}`);
  }
}

/** Expressed variant of a single gene: higher dominance wins, tie -> lower index. */
export function expressGene(gene: number, pair: GenePair): number {
  const [a, b] = pair;
  const da = CATALOG[gene].variants[a].dominance;
  const db = CATALOG[gene].variants[b].dominance;
  if (da > db) return a;
  if (db > da) return b;
  return a < b ? a : b;
}

/** Phenotype: one expressed variant index per gene. */
export function express(genome: Genome): number[] {
  validateGenome(genome);
  const out: number[] = [];
  for (let g = 0; g < GENE_COUNT; g++) out.push(expressGene(g, genome[g]));
  return out;
}

export function tierForScore(score: number): RarityTier {
  if (score <= 2) return "common";
  if (score <= 5) return "uncommon";
  if (score <= 8) return "rare";
  return "legendary";
}

export function rarity(genome: Genome): RarityResult {
  const expressed = express(genome);
  let score = 0;
  for (let g = 0; g < GENE_COUNT; g++) score += CATALOG[g].variants[expressed[g]].rarity as Rarity;
  return { score, tier: tierForScore(score) };
}

/** Breeding seed (spec §4.2). Parent ids must already be ordered. */
export function breedSeed(idA: string, idB: string, nonce: string): number {
  return fnv1a32(idA + "|" + idB + "|" + nonce);
}

/** Child id (spec §4.6). */
export function childId(seed: number): string {
  return "c_" + hex8(fnv1a32(hex8(seed) + "|child"));
}

/** Sort by gene, then variant (spec says input is pre-sorted; we enforce it). */
export function sortMutations(list: readonly Mutation[]): Mutation[] {
  return list
    .map((m) => ({ gene: m.gene, variant: m.variant }))
    .sort((x, y) => (x.gene !== y.gene ? x.gene - y.gene : x.variant - y.variant));
}

export const MUTATION_CHANCE = 0.15;

export function breed(input: BreedInput): BreedResult {
  let pa = input.parentA;
  let pb = input.parentB;
  validateGenome(pa.genome);
  validateGenome(pb.genome);
  const cmp = compareIds(pa.id, pb.id);
  if (cmp === 0) throw new GenomeError("cannot breed a creature with itself");
  // 1. order parents
  if (cmp > 0) {
    const t = pa;
    pa = pb;
    pb = t;
  }
  const mutations = sortMutations(input.unlockedMutations ?? []);
  mutations.forEach(validateMutation);

  // 2. seed
  const seed = breedSeed(pa.id, pb.id, input.nonce);
  const rng = mulberry32(seed);

  // 3. inheritance
  const genome: Genome = [];
  for (let g = 0; g < GENE_COUNT; g++) {
    const fromA = pa.genome[g][rng.int(2)];
    const fromB = pb.genome[g][rng.int(2)];
    genome.push([fromA, fromB]);
  }

  // 4. mutation (roll is always drawn)
  let mutation: AppliedMutation | null = null;
  const roll = rng.float();
  if (mutations.length > 0 && roll < MUTATION_CHANCE) {
    const m = mutations[rng.int(mutations.length)];
    const allele = rng.int(2);
    genome[m.gene][allele] = m.variant;
    mutation = { gene: m.gene, variant: m.variant, allele };
  }

  // 5. palette shift (first assignment wins if both parents share an owner)
  const ownerA = pa.owner ?? pa.id;
  const ownerB = pb.owner ?? pb.id;
  const paletteShift: Record<string, number> = { [ownerA]: 0 };
  if (ownerB !== ownerA) paletteShift[ownerB] = 1;

  // 6. id
  return { id: childId(seed), genome, seedHex: hex8(seed), mutation, paletteShift };
}

/** Starter creature (spec §6). `slot` is a non-negative integer, formatted in decimal. */
export function starter(playerId: string, slot: number): Genome {
  if (!Number.isInteger(slot) || slot < 0) throw new GenomeError(`slot must be a non-negative integer`);
  const rng = mulberry32(fnv1a32("starter|" + playerId + "|" + String(slot)));
  const genome: Genome = [];
  for (let g = 0; g < GENE_COUNT; g++) {
    const pool: number[] = [];
    CATALOG[g].variants.forEach((v, i) => {
      if (!v.mutationOnly) pool.push(i);
    });
    const a = pool[rng.int(pool.length)];
    const b = pool[rng.int(pool.length)];
    genome.push([a, b]);
  }
  return genome;
}
