// Firestore document shapes (docs/backend-spec.md "Collections"). Timestamps are epoch ms.

import type { AppliedMutation, Genome, Mutation, RarityResult } from "./engine.ts";

/** Ordered youngest → oldest (gating compares positions). */
export const AGE_BANDS = ["under13", "13to15", "16to17", "18plus"] as const;
export type AgeBand = (typeof AGE_BANDS)[number];
/** Pre-split bands still accepted from old clients / stored docs. "13to17" maps conservatively to 13to15. */
export const LEGACY_AGE_BANDS: Readonly<Record<string, AgeBand>> = { "13to17": "13to15" };

/** Current band for a client value or stored doc (legacy-mapped), or null if unknown. */
export function normalizeAgeBand(v: unknown): AgeBand | null {
  if (typeof v !== "string") return null;
  if ((AGE_BANDS as readonly string[]).includes(v)) return v as AgeBand;
  return LEGACY_AGE_BANDS[v] ?? null;
}

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
  /** Social caps per server UTC day (friends graph). Absent until the first social call. */
  social?: { dayUTC: string; pokes: number; invites: number };
}

/** "duo" = duo creature or a twin made from it on unlink; "mascot" = crew mascot or a leaver's copy. */
export type CreatureOrigin = "starter" | "bred" | "duo" | "mascot";

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
  /** Co-owned creatures (duo creature, crew mascot): ownerUid is "duo:<id>" / "crew:<id>". */
  coOwnerUids?: string[];
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

// MARK: friends graph (backend-spec "Friends graph"; living-world-spec §10–12)

export type InviteKind = "friend" | "duo" | "crew";

/** invites/{code}. Single use, 24 h. Never client-readable (the code is the secret). */
export interface InviteDoc {
  code: string;
  creatorUid: string;
  kind: InviteKind;
  /** Duo: the creator's parent for the duo creature. Crew: the creator's gene-relay donor. */
  creatorCreatureId: string | null;
  createdAt: number;
  expiresAt: number;
  usedBy: string | null;
  /** Duo invites: the creator's preferred framing (applied only if both members are 16+). */
  framing?: DuoFraming;
}

/** friends/{uid}/list/{friendUid} — one edge per direction, written together. */
export interface FriendDoc {
  uid: string;
  friendUid: string;
  since: number;
  nickname?: string;
}

export interface VisitDiary {
  title: string;
  lines: string[];
}

export type VisitStatus = "active" | "returned";

/** visits/{id}. Readable by owner and host. */
export interface VisitDoc {
  id: string;
  visitorCreatureId: string;
  ownerUid: string;
  hostUid: string;
  hostCreatureId: string | null;
  start: number;
  end: number;
  status: VisitStatus;
  diary: VisitDiary | null;
  souvenirId: string | null;
}

/** away/{creatureId}: server-only marker while a creature visits; rules use it to let the host read the creature. */
export interface AwayDoc {
  creatureId: string;
  hostUid: string;
  visitId: string;
}

/** bonds/{id}: friendship level between two creatures (raised by visits). */
export interface BondDoc {
  id: string;
  creatureIds: string[];
  ownerUids: string[];
  level: number;
  visits: number;
}

export type GroupStatus = "forming" | "active" | "ended";
/** §11 framing. Never romantic. "bestFriends" is forced when any member is under 16. */
export const DUO_FRAMINGS = ["duo", "bestFriends"] as const;
export type DuoFraming = (typeof DUO_FRAMINGS)[number];

/** duos/{id}. Members read; functions write. Holds NO per-member presence/time data. */
export interface DuoDoc {
  id: string;
  members: string[];
  status: "active" | "ended";
  framing: DuoFraming;
  createdAt: number;
  creatureId: string | null;
  /** "Days we both waved" — only ever increases. */
  daysBothWaved: number;
}

/** duoPrivate/{id}: server-only bookkeeping (local wave days, note caps). Never client-readable. */
export interface DuoPrivateDoc {
  id: string;
  /** Last wave per member: client local day, server time, and whether it was answered. Never leaves the server. */
  waves: Record<string, { day: string; at: number; paired: boolean } | null>;
  notes: Record<string, { day: string; count: number }>;
  noteSeq: number;
  paletteShift: Record<string, number>;
}

export interface Painting {
  id: string;
  seed: number;
  day: string;
}

/** duos/{id}/house/state and crews/{id}/house/state. slots[uid][s1..s6] = cosmetic id | null. */
export interface HouseDoc {
  slots: Record<string, Record<string, string | null>>;
  paintings: Painting[];
}

/** duos/{id}/notes/{noteId}: fridge note (emote + prop only, no free text). */
export interface NoteDoc {
  id: string;
  byUid: string;
  emote: string;
  prop: string;
  /** Per-duo order (no timestamps or days: notes must not reveal when a partner was active). */
  seq: number;
}

/** crews/{id}. Members read; functions write. */
export interface CrewDoc {
  id: string;
  members: string[];
  status: GroupStatus;
  createdAt: number;
  /** Gene-relay donor creature per member (join order = members order). */
  donors: Record<string, string>;
  mascotId: string | null;
  rollCall: { day: string; emotes: Record<string, string> };
}

/** links/{uid}: which duo / crew the player is in (self-readable; used by rules). */
export interface LinksDoc {
  uid: string;
  duoId: string | null;
  crewId: string | null;
}

/** cooldowns/{pairKey}: re-link cooldown after an unlink. Server-only. */
export interface CooldownDoc {
  id: string;
  until: number;
}

/** pokes/{id}: recipient reads. No timestamp or day. */
export interface PokeDoc {
  id: string;
  toUid: string;
  fromUid: string;
  emote: string;
}

/** gallery/{uid}/items/{id}: owner-only keepsakes (paintings, house memories). */
export interface GalleryDoc {
  id: string;
  kind: "painting" | "house-memory";
  group: "duo" | "crew";
  seed: number | null;
  /** House memory: "mine" / "theirs" rooms (no uids). */
  rooms: Record<string, Record<string, string | null>> | null;
  day: string;
}
