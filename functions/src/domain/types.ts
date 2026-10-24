// Firestore document shapes (docs/backend-spec.md "Collections"). Timestamps are epoch ms.

import type { AppliedMutation, Genome, Mutation, RarityResult } from "./engine.ts";

export const AGE_BANDS = ["under13", "13to17", "18plus"] as const;
export type AgeBand = (typeof AGE_BANDS)[number];

export interface DailyLimits {
  dayUTC: string;
  offers: number;
  previews: number;
}

export interface PlayerDoc {
  uid: string;
  displayName: string;
  createdAt: number;
  ageBand: AgeBand;
  /** Server-owned (spec §7.3), sorted by gene then variant. */
  unlockedMutations: Mutation[];
  streak: { count: number; lastDayUTC: string | null };
  limits: DailyLimits;
  sparks: number;
  lastSurpriseDayUTC: string | null;
  cosmetics: string[];
}

export type CreatureOrigin = "starter" | "bred";

export interface CreatureDoc {
  id: string;
  ownerUid: string;
  name: string;
  genome: Genome;
  generation: number;
  /** Ordered parent ids (spec §4.1), empty for starters. */
  parentIds: string[];
  comboKey: string;
  /** Global serial within comboKey (bred only), null for starters. */
  serial: number | null;
  discoveredFirst: boolean;
  paletteShift: number;
  origin: CreatureOrigin;
  bornAt: number;
  /** Set when the egg hatched early; otherwise hatch = bornAt + 1 day. */
  hatchedAt: number | null;
  specVersion: string;
  createdAt: number;
  sig: string;
}

export type OfferStatus = "open" | "used" | "expired" | "cancelled";

export interface OfferDoc {
  id: string;
  creatorUid: string;
  parentCreatureId: string;
  createdAt: number;
  expiresAt: number;
  status: OfferStatus;
}

export interface ChildPreview {
  id: string;
  genome: Genome;
  mutation: AppliedMutation | null;
  paletteShift: Record<string, number>;
  comboKey: string;
  rarity: RarityResult;
}

export type BreedStatus = "preview" | "committed" | "burned";

export interface BreedDoc {
  id: string;
  offerId: string;
  offerCreatorUid: string;
  acceptorUid: string;
  acceptorCreatureId: string;
  nonce: string;
  /** Snapshot of the acceptor's server-owned mutations at preview time (commit reuses it: no reroll). */
  unlockedMutations: Mutation[];
  previewChild: ChildPreview;
  status: BreedStatus;
  specVersion: string;
  createdAt: number;
  committedAt: number | null;
  childIds: string[];
}

export interface ComboDoc {
  comboKey: string;
  /** null = nobody yet; DELETED_UID after the discoverer deleted their account. */
  discovererUid: string | null;
  firstAt: number;
  count: number;
}
