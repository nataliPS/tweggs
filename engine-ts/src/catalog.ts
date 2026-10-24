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
  gene("body", [
    ["bean", 5, C, false],
    ["round", 6, C, false],
    ["tall", 4, C, false],
    ["blob", 3, U, false],
    ["star", 2, R, false],
    ["crystal", 7, L, true],
  ]),
  gene("eyes", [
    ["dot", 6, C, false],
    ["wide", 5, C, false],
    ["sleepy", 4, C, false],
    ["happy", 5, C, false],
    ["cyclops", 2, U, false],
    ["heart", 3, C, false],
    ["starry", 2, R, false],
    ["void", 8, L, true],
  ]),
  gene("head", [
    ["none", 3, C, false],
    ["ears", 5, C, false],
    ["horns", 6, C, false],
    ["antenna", 4, C, false],
    ["crest", 4, U, false],
    ["leaf", 3, U, false],
    ["crown", 2, R, false],
    ["flamehorns", 8, L, true],
  ]),
  gene("pattern", [
    ["plain", 4, C, false],
    ["spots", 5, C, false],
    ["stripes", 5, C, false],
    ["belly", 3, U, false],
    ["freckles", 2, R, false],
    ["galaxy", 7, L, true],
  ]),
  gene("tail", [
    ["none", 3, C, false],
    ["nub", 4, C, false],
    ["curl", 5, C, false],
    ["fluff", 4, U, false],
    ["spikes", 2, R, false],
    ["comet", 8, L, true],
  ]),
  gene("palette", [
    ["mint", 5, C, false],
    ["peach", 5, C, false],
    ["sky", 6, C, false],
    ["lilac", 4, C, false],
    ["lemon", 4, C, false],
    ["coral", 6, C, false],
    ["moss", 3, C, false],
    ["slate", 3, C, false],
    ["berry", 5, U, false],
    ["ocean", 6, U, false],
    ["sunset", 4, U, false],
    ["frost", 3, U, false],
    ["ember", 2, R, false],
    ["midnight", 2, R, false],
    ["gold", 8, L, true],
    ["prism", 9, L, true],
  ]),
  gene("aura", [
    ["none", 4, C, false],
    ["sparkle", 3, U, false],
    ["glow", 2, R, false],
    ["storm", 7, L, true],
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
    ["chaotic", 8, L, true],
  ]),
];

/** Prototype variant counts per gene, in gene order (spec §1). */
export const VARIANT_COUNTS: readonly number[] = CATALOG.map((g) => g.variants.length);
