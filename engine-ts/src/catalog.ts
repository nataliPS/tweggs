// Gene / variant tables (spec §1). This file is the single source of truth:
// MixlingsKit/Sources/MixlingsGenome/Catalog.swift is GENERATED from it by
// scripts/gen-swift-catalog.ts. Never edit the Swift copy by hand.

export type Rarity = 0 | 1 | 2 | 3; // 0 common, 1 uncommon, 2 rare, 3 legendary

export interface VariantDef {
  readonly name: string;
  /** 1..9, higher wins expression. */
  readonly dominance: number;
  readonly rarity: Rarity;
  /** Never rolled for starters; only enters via mutation. */
  readonly mutationOnly: boolean;
}

export interface GeneDef {
  readonly key: GeneKey;
  readonly variants: readonly VariantDef[];
}

export const GENE_KEYS = ["body", "eyes", "head", "pattern", "tail", "palette", "aura", "temper"] as const;
export type GeneKey = (typeof GENE_KEYS)[number];
export const GENE_COUNT = GENE_KEYS.length; // 8

// Compact row form: [name, dominance, rarity, mutationOnly]
type Row = readonly [string, number, Rarity, boolean];
const C = 0, U = 1, R = 2, L = 3;

function gene(key: GeneKey, rows: readonly Row[]): GeneDef {
  return {
    key,
    variants: rows.map(([name, dominance, rarity, mutationOnly]) => ({ name, dominance, rarity, mutationOnly })),
  };
}

export const CATALOG: readonly GeneDef[] = [
  // Names and indices match the approved art renderer (art/render.py).
  gene("body", [
    ["round", 6, C, false],
    ["bean", 5, C, false],
    ["pear", 4, C, false],
    ["block", 3, U, false],
    ["drop", 7, L, true],
    ["mochi", 4, U, false],
  ]),
  gene("eyes", [
    ["dots", 6, C, false],
    ["big", 5, C, false],
    ["sleepy", 4, C, false],
    ["happy", 5, C, false],
    ["sparkle", 3, U, false],
    ["oval", 4, C, false],
    ["star", 3, R, false],
    ["cyclops", 7, L, true],
  ]),
  gene("head", [
    ["none", 3, C, false],
    ["catears", 5, C, false],
    ["bunnyears", 5, C, false],
    ["horns", 6, U, false],
    ["antenna", 4, C, false],
    ["leaf", 3, U, false],
    ["crest", 2, R, false],
    ["halo", 7, L, true],
  ]),
  gene("pattern", [
    ["plain", 4, C, false],
    ["belly", 5, C, false],
    ["spots", 5, U, false],
    ["stripes", 3, C, false],
    ["cap", 7, L, true],
    ["freckles", 2, R, false],
  ]),
  gene("tail", [
    ["none", 3, C, false],
    ["puff", 4, C, false],
    ["curly", 5, C, false],
    ["long", 4, U, false],
    ["flame", 3, R, false],
    ["lightning", 7, L, true],
  ]),
  gene("palette", [
    ["mint", 5, C, false],
    ["bubblegum", 5, C, false],
    ["sky", 6, C, false],
    ["sunny", 4, C, false],
    ["lavender", 4, C, false],
    ["coral", 6, C, false],
    ["lime", 3, C, false],
    ["aqua", 3, C, false],
    ["cream", 5, U, false],
    ["stone", 6, U, false],
    ["rose", 4, U, false],
    ["cobalt", 3, U, false],
    ["night", 4, R, false],
    ["tangerine", 2, R, false],
    ["seafoam", 4, U, false],
    ["ghost", 7, L, true],
  ]),
  gene("aura", [
    ["none", 4, C, false],
    ["sparkle", 3, U, false],
    ["glow", 2, R, false],
    ["hearts", 7, L, true],
  ]),
  gene("temper", [
    ["calm", 5, C, false],
    ["playful", 6, C, false],
    ["shy", 4, C, false],
    ["brave", 5, C, false],
    ["grumpy", 4, C, false],
    ["curious", 3, U, false],
    ["sneaky", 3, U, false],
    ["dreamy", 2, U, false],
    ["noble", 2, R, false],
    ["chaotic", 7, L, true],
  ]),
];

/** Prototype variant counts per gene, in gene order (spec §1). */
export const VARIANT_COUNTS: readonly number[] = CATALOG.map((g) => g.variants.length);
