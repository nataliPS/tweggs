// Economy constants and pairing-guidance helpers (spec §9; retro 2026-10-24 G6/G7/G8).
// Pure and deterministic. Mirrored by MixlingsKit/Sources/MixlingsGenome/Economy.swift.
//
// Design rules (founder-approved): sparks are earned only (never sold), no paid randomness.
// Every sink below buys certainty or cosmetics, never a re-roll.

import { expressGene, type Genome } from "./genome.ts";
import type { SeasonEntry } from "./collecting.ts";

/** G6: hatch-rush skips 1 day of growth for this many sparks. */
export const HATCH_RUSH_COST = 30;
/** G6: max hatch-rushes per player per local day. */
export const HATCH_RUSH_DAILY_MAX = 1;
/** G6: gene hint (which of your pairings can produce a missing season entry). */
export const GENE_HINT_COST = 20;
/** G6: cosmetic shop item price range in sparks, inclusive. */
export const SHOP_PRICE_MIN = 100;
export const SHOP_PRICE_MAX = 300;
/** G7: breeds in a row without a new season entry before previews highlight carrier parents. */
export const PITY_THRESHOLD = 15;
/** G8: generation ladder badges. */
export const GEN_BADGES: readonly number[] = [5, 10];
/** Collection slots: free players / club members. */
export const FREE_SLOTS = 8;
export const CLUB_SLOTS = 30;

/**
 * True if some child of `a` x `b` (one allele from each parent, mutation ignored)
 * would EXPRESS `variant` at `gene`. Genomes are assumed valid.
 */
export function pairingCanProduce(a: Genome, b: Genome, gene: number, variant: number): boolean {
  for (const x of a[gene]) {
    for (const y of b[gene]) {
      if (expressGene(gene, [x, y]) === variant) return true;
    }
  }
  return false;
}

/** Indices (ascending) of creatures in `collection` that carry the entry's allele in either copy. */
export function carrierHint(collection: readonly Genome[], entry: SeasonEntry): number[] {
  const out: number[] = [];
  collection.forEach((g, i) => {
    if (g[entry.gene][0] === entry.variant || g[entry.gene][1] === entry.variant) out.push(i);
  });
  return out;
}

/** G7: whether the pity hint is active after `breedsWithoutNewEntry` consecutive breeds. */
export function pityHintActive(breedsWithoutNewEntry: number): boolean {
  return breedsWithoutNewEntry >= PITY_THRESHOLD;
}

/** G8: badges (generation thresholds) earned by a creature of `generation`, ascending. */
export function genBadges(generation: number): number[] {
  return GEN_BADGES.filter((b) => generation >= b);
}
