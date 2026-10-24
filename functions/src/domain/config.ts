// Server-owned balance values for the backend (live-ops values move to Remote Config later, T5).
// Values that the client also uses (slots, sinks, pity) live in engine-ts/src/economy.ts.

import { DAY_MS, HOUR_MS } from "./time.ts";
import type { Mutation } from "./engine.ts";

/** Bumped whenever breeding rules change; a preview made under another version is burned on commit. */
export const SPEC_VERSION = "0.1";

/** genome-spec §7.2 */
export const MAX_PREVIEWS_PER_DAY = 10;
export const MAX_OFFERS_PER_DAY = 20;
/** backend-spec: offers expire 72 h after creation. */
export const OFFER_TTL_MS = 72 * HOUR_MS;
/** Previews older than this are burned by the hourly job even if the offer is still open. */
export const PREVIEW_TTL_MS = 24 * HOUR_MS;

/** Growth (App/Shared/Engine/CareEngine.swift): hatch = bornAt + 1 d unless hatched early; teen +2 d; adult +6 d. */
export const HATCH_AFTER_MS = 1 * DAY_MS;
export const TEEN_AFTER_HATCH_MS = 2 * DAY_MS;
export const ADULT_AFTER_HATCH_MS = 6 * DAY_MS;
/** Retro G4: teens can breed (day 3); adults remain day 7. */
export const MIN_BREED_STAGE = "teen" as const;

/**
 * Starters persisted by registerPlayer (retro T2/G4). Ids/genomes match the app's CreatureFactory
 * ("s_" + hex8(fnv1a32("starter|uid|slot")), genome = starter(uid, slot)).
 * - slot 0: onboarding egg, hatched at registration (tap-to-hatch) -> teen on day 3.
 * - slot 1: second starter as an egg laid at registration -> natural hatch = baby on day 2.
 */
export const STARTERS: readonly { slot: number; name: string; hatchedAtRegistration: boolean }[] = [
  { slot: 0, name: "Mixy", hatchedAtRegistration: true },
  { slot: 1, name: "Pip", hatchedAtRegistration: false },
];

/**
 * Streak unlocks (retro "simple table"): reaching `days` consecutive UTC check-ins permanently
 * unlocks the mutation-only variant. Unlocks are never revoked when a streak breaks.
 */
export const STREAK_UNLOCKS: readonly { days: number; mutation: Mutation }[] = [
  { days: 3, mutation: { gene: 5, variant: 15 } }, // palette ghost
  { days: 7, mutation: { gene: 1, variant: 7 } }, // eyes cyclops
  { days: 14, mutation: { gene: 4, variant: 5 } }, // tail lightning
  { days: 21, mutation: { gene: 2, variant: 7 } }, // head halo
  { days: 30, mutation: { gene: 6, variant: 3 } }, // aura hearts
];

/** Creature names (retro C3). */
export const NAME_MIN = 1;
export const NAME_MAX = 16;

/** Placeholder written to combos/{key}.discovererUid after the discoverer deleted their account. */
export const DELETED_UID = "deleted";
