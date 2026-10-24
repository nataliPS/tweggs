// Collecting features (spec §8): combo keys, generations, seasons, daily surprise.
// Pure and deterministic. Mirrored line by line by
// MixlingsKit/Sources/MixlingsGenome/Collecting.swift; golden vectors cover both.
//
// Design rules (founder-approved): no paid randomness and no real-money resale, ever.
// The daily surprise is free, once per local day, and has no purchase path.

import { fnv1a32 } from "./hash.ts";
import { mulberry32 } from "./rng.ts";
import { CATALOG } from "./catalog.ts";
import { express, type Genome } from "./genome.ts";

/** Genes that are drawn (body, eyes, head, pattern, tail, palette, aura). Temper is not part of the look. */
export const VISIBLE_GENE_COUNT = 7;

/**
 * Stable key of what a creature LOOKS like: the 7 visible expressed variants joined by "-",
 * e.g. "0-1-2-3-4-5-6". Palette shift (twins) and temper are deliberately excluded.
 * `expressed` must have at least 7 entries (output of `express`).
 */
export function comboKey(expressed: readonly number[]): string {
  if (expressed.length < VISIBLE_GENE_COUNT) throw new RangeError("comboKey: need 7 expressed genes");
  return expressed.slice(0, VISIBLE_GENE_COUNT).map((v) => String(v)).join("-");
}

export function comboKeyOfGenome(genome: Genome): string {
  return comboKey(express(genome));
}

/** Generation: 0 with no known parents (starters, onboarding egg), else max(parent gens) + 1. */
export function generation(parentGenerations: readonly number[]): number {
  if (parentGenerations.length === 0) return 0;
  return Math.max(...parentGenerations) + 1;
}

// MARK: Seasons

export interface SeasonEntry {
  readonly gene: number;
  readonly variant: number;
}

export interface Season {
  /** Stable id, also the localization key stem in the app ("season.<id>.name"). */
  readonly id: string;
  /** Inclusive local-day bounds, "yyyy-MM-dd". */
  readonly startDay: string;
  readonly endDay: string;
  readonly entries: readonly SeasonEntry[];
}

/**
 * Season 1 "Перша весна" / "First Spring": 12 non-mutation variants,
 * 5 common, 4 uncommon, 3 rare. TODO(content): confirm real dates before launch.
 */
export const SEASON_1: Season = {
  id: "s1",
  startDay: "2026-10-01",
  endDay: "2027-05-31",
  entries: [
    { gene: 2, variant: 1 },  // head catears      common
    { gene: 3, variant: 1 },  // pattern belly     common
    { gene: 5, variant: 0 },  // palette mint      common
    { gene: 4, variant: 1 },  // tail puff         common
    { gene: 1, variant: 3 },  // eyes happy        common
    { gene: 2, variant: 5 },  // head leaf         uncommon
    { gene: 3, variant: 2 },  // pattern spots     uncommon
    { gene: 2, variant: 3 },  // head horns        uncommon
    { gene: 6, variant: 1 },  // aura sparkle      uncommon
    { gene: 4, variant: 4 },  // tail flame        rare
    { gene: 1, variant: 6 },  // eyes star         rare
    { gene: 5, variant: 12 }, // palette night     rare
  ],
};

export const SEASONS: readonly Season[] = [SEASON_1];

/** Per entry: true if any of the given expressed phenotypes shows that variant. */
export function seasonProgress(season: Season, expressedList: readonly (readonly number[])[]): boolean[] {
  return season.entries.map((e) => expressedList.some((x) => x[e.gene] === e.variant));
}

export function isSeasonActive(season: Season, day: string): boolean {
  return day >= season.startDay && day <= season.endDay;
}

// MARK: Daily surprise

export type Souvenir = { kind: "sparks"; amount: number } | { kind: "cosmetic"; id: string };

/** Placeholder cosmetic ids. TODO(art): real cosmetics. */
export const SURPRISE_COSMETICS: readonly string[] = ["flower_crown", "tiny_scarf", "star_pin", "bow_tie"];
export const SURPRISE_SPARKS_MIN = 5;
export const SURPRISE_SPARKS_MAX = 25;
/** Out of 100: rolls below this give sparks, the rest a cosmetic. */
export const SURPRISE_SPARKS_CHANCE = 80;

/**
 * Free daily surprise for `playerId` on local day `day` ("yyyy-MM-dd").
 * rng = mulberry32(fnv1a32("surprise|" + playerId + "|" + day));
 * roll = rng.int(100); roll < 80 -> sparks 5 + rng.int(21) (5..25), else cosmetic[rng.int(count)].
 */
export function dailySurprise(playerId: string, day: string): Souvenir {
  const rng = mulberry32(fnv1a32("surprise|" + playerId + "|" + day));
  const roll = rng.int(100);
  if (roll < SURPRISE_SPARKS_CHANCE) {
    return { kind: "sparks", amount: SURPRISE_SPARKS_MIN + rng.int(SURPRISE_SPARKS_MAX - SURPRISE_SPARKS_MIN + 1) };
  }
  return { kind: "cosmetic", id: SURPRISE_COSMETICS[rng.int(SURPRISE_COSMETICS.length)] };
}

/** Internal sanity helper used by tests: variant definition of an entry. */
export function seasonEntryVariant(e: SeasonEntry) {
  return CATALOG[e.gene].variants[e.variant];
}
