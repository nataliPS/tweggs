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

// MARK: friends graph (backend-spec "Friends graph"; living-world-spec §10–12). Live-ops values -> Remote Config later.

/** Invites (friend / duo / crew) are single use and expire 24 h after creation. */
export const INVITE_TTL_MS = 24 * HOUR_MS;
export const MAX_INVITES_PER_DAY = 20;
/** Lock Screen pokes / hugs (§13): max 3 per sender per server UTC day. */
export const MAX_POKES_PER_DAY = 3;
export const POKE_EMOTES: readonly string[] = ["wave", "hug", "heart", "star", "laugh", "sleepy"];

/**
 * Duo age gate (§11, coordinator decision 2026-10-24): Duo for everyone 13+ (under13 stays offline).
 * If either member is below DUO_FRAMING_MIN_BAND (i.e. under 16) the framing is forced to "bestFriends";
 * otherwise members choose "duo" (default) or "bestFriends". No romantic framing exists.
 */
export const DUO_MIN_AGE_BAND = "13to15" as const;
export const DUO_FRAMING_MIN_BAND = "16to17" as const;
/** One-sided unlink: re-linking the SAME two people is blocked for 7 days. */
export const DUO_RELINK_COOLDOWN_MS = 7 * DAY_MS;
export const DUO_ANNIVERSARY_DAYS: readonly number[] = [7, 30, 100, 365];
/** A partner's unanswered morning wave can be waved back for this long (server clock, never exposed). */
export const WAVE_BACK_WINDOW_MS = 24 * HOUR_MS;
/** A local day sent by the client must be within this distance of server time (UTC-12 .. UTC+14). */
export const LOCAL_DAY_SKEW_MS = 14 * HOUR_MS;
/** Fridge notes: emote + pixel prop only, no free text; max 3 per member per server UTC day. */
export const MAX_NOTES_PER_DAY = 3;
export const NOTE_EMOTES: readonly string[] = ["heart", "smile", "laugh", "hug", "star", "sun", "moon", "sleepy"];
export const NOTE_PROPS: readonly string[] = ["cake", "flower", "umbrella", "tea", "pizza", "balloon", "book", "gift"];
export const NOTES_SHOWN = 9;

/** House: each member decorates only their own slots. */
export const HOUSE_SLOTS: readonly string[] = ["s1", "s2", "s3", "s4", "s5", "s6"];
export const MAX_PAINTINGS = 50;

export const CREW_MIN = 3;
export const CREW_MAX = 5;
export const ROLL_CALL_EMOTES: readonly string[] = ["wave", "salute", "dance", "star", "heart", "sleepy"];

/** Visits (§10): friends only, 1–3 days, one at a time per creature, at most 3 guests per host. */
export const VISIT_MIN_DAYS = 1;
export const VISIT_MAX_DAYS = 3;
export const MAX_GUESTS_PER_HOST = 3;
export const BOND_MAX_LEVEL = 5;
/** Bond level at which the app suggests "They became friends — breed them?". */
export const BOND_SUGGEST_BREED_LEVEL = 2;
export const VISIT_SOUVENIRS: readonly string[] = [
  "souvenir_seashell", "souvenir_postcard", "souvenir_bracelet", "souvenir_flag", "souvenir_pressed_flower", "souvenir_snow_globe",
];
/** Fallback display name for an unnamed creature in diary lines. */
export const UNNAMED_CREATURE = "Little one";
