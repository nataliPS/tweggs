// Domain services behind the callable functions (docs/backend-spec.md, genome-spec §7).
// Pure: depend only on engine-ts (via ./engine.ts) and injected ports. No Firebase imports here.

import {
  breed, comboKeyOfGenome, dailySurprise, fnv1a32, generation, hex8, rarity, sortMutations, starter,
  type BreedResult, type Mutation, type Souvenir,
} from "./engine.ts";
import {
  DELETED_UID, MAX_OFFERS_PER_DAY, MAX_PREVIEWS_PER_DAY, MIN_BREED_STAGE, OFFER_TTL_MS, PREVIEW_TTL_MS,
  SPEC_VERSION, STARTERS, STREAK_UNLOCKS,
} from "./config.ts";
import { DomainError, fail } from "./errors.ts";
import { atLeast, stageOf } from "./growth.ts";
import {
  creatureFactory, id64, loadOwnedCreature, loadPlayer, requireSocial, requireString, requireUid,
} from "./guards.ts";
import { checkName } from "./nameFilter.ts";
import { createSocialServices, type SocialConfig } from "./social.ts";
import { BULK_CHUNK, type Repository, type Tx } from "./repository.ts";
import { addDays, utcDay } from "./time.ts";
import {
  normalizeAgeBand, type AgeBand, type BreedDoc, type ChildPreview, type CreatureDoc, type OfferDoc, type PlayerDoc,
} from "./types.ts";

export interface Deps {
  repo: Repository;
  /** Server clock, epoch ms. */
  now: () => number;
  /** Unguessable random token (crypto.randomUUID in prod). Used for nonces and offer ids. */
  randomToken: () => string;
  /** Signs a creature at birth (HMAC with a server secret in prod). */
  sign: (payload: string) => string;
  /** Friends-graph gating (duoMinAgeBand, duoFramingMinBand); defaults in social.ts. */
  social?: Partial<SocialConfig>;
}

// MARK: helpers

export function starterCreatureId(uid: string, slot: number): string {
  return id64("s_", "starter|" + uid + "|" + slot);
}

/** One breed doc per (offer, acceptor creature): the doc id IS the binding (spec §7.1). */
export function breedDocId(offerId: string, acceptorCreatureId: string): string {
  return id64("b_", offerId + "|" + acceptorCreatureId);
}

function twinId(child: BreedResult, breedId: string, shift: number): string {
  return child.id + hex8(fnv1a32(breedId + "|twin|" + shift)) + hex8(fnv1a32("twin|" + shift + "|" + breedId));
}

function requireBreedable(c: CreatureDoc, now: number): void {
  if (!atLeast(stageOf(c, now), MIN_BREED_STAGE)) fail("failed-precondition", "too-young");
}

/** Today's limits, reset on a new UTC day. */
function limitsFor(p: PlayerDoc, day: string): PlayerDoc["limits"] {
  return p.limits.dayUTC === day ? { ...p.limits } : { dayUTC: day, offers: 0, previews: 0 };
}

function offerIsLive(o: OfferDoc, now: number): boolean {
  return o.status === "open" && now < o.expiresAt;
}

function previewFrom(result: BreedResult): ChildPreview {
  return {
    id: result.id,
    genome: result.genome,
    mutation: result.mutation,
    paletteShift: result.paletteShift,
    comboKey: comboKeyOfGenome(result.genome),
    rarity: rarity(result.genome),
  };
}

function computeBreed(parentOffer: CreatureDoc, parentMine: CreatureDoc, nonce: string, mutations: Mutation[]): BreedResult {
  return breed({
    parentA: { id: parentOffer.id, genome: parentOffer.genome, owner: parentOffer.ownerUid },
    parentB: { id: parentMine.id, genome: parentMine.genome, owner: parentMine.ownerUid },
    nonce,
    unlockedMutations: mutations,
  });
}

// MARK: public result shapes (JSON-safe; returned to the client as-is)

export interface PreviewResult {
  breedId: string;
  nonce: string;
  child: ChildPreview;
  /** Caller's twin palette shift. */
  myPaletteShift: number;
  /** false when the stored preview was returned again (no reroll, cap not charged). */
  fresh: boolean;
  previewsLeftToday: number;
}

export interface CommitResult {
  breedId: string;
  /** Caller's twin first, then the friend's twin. */
  creatures: CreatureDoc[];
  serial: number;
  discoveredFirst: boolean;
  /** true when this breed had already been committed (idempotent retry). */
  replay: boolean;
}

export interface SurpriseResult {
  day: string;
  souvenir: Souvenir;
  alreadyClaimed: boolean;
  sparks: number;
}

export interface StreakResult {
  day: string;
  count: number;
  alreadyCheckedIn: boolean;
  newlyUnlocked: Mutation[];
  unlockedMutations: Mutation[];
}

export interface DeleteResult {
  creatures: number;
  offers: number;
  breeds: number;
  combosAnonymized: number;
}

/** Mutations unlocked by a streak of `count` days (STREAK_UNLOCKS table). */
export function unlocksForStreak(count: number): Mutation[] {
  return sortMutations(STREAK_UNLOCKS.filter((u) => count >= u.days).map((u) => u.mutation));
}

// MARK: services

export function createServices(deps: Deps) {
  const { repo, now, randomToken, sign } = deps;

  const newCreature = creatureFactory(sign);
  const social = createSocialServices(deps);

  return {
    ...social,

    /**
     * Creates the player and persists both starters server-side (retro T2), so later breeding
     * reads genomes from the registry instead of re-deriving them from a client-supplied id.
     * Idempotent: a second call returns the existing player and starters unchanged.
     */
    async registerPlayer(uidIn: string | null | undefined, input: { ageBand?: unknown; displayName?: unknown }) {
      const uid = requireUid(uidIn);
      // Old clients may still send "13to17": stored as 13to15 (conservative).
      const ageBand = normalizeAgeBand(input?.ageBand);
      if (ageBand === null) fail("invalid-argument", "bad-ageBand");
      let displayName = "";
      if (input?.displayName !== undefined && input.displayName !== "") {
        const v = checkName(input.displayName);
        if (!v.ok) fail("invalid-argument", "bad-displayName", v.reason);
        displayName = (v as { name: string }).name;
      }
      return repo.runTransaction(async (tx) => {
        const t = now();
        const existing = await tx.getPlayer(uid);
        const ids = STARTERS.map((s) => starterCreatureId(uid, s.slot));
        const found = await Promise.all(ids.map((id) => tx.getCreature(id)));
        if (existing) {
          return { player: existing, starters: found.filter((c): c is CreatureDoc => c !== null), created: false };
        }
        found.forEach((c) => {
          if (c && c.ownerUid !== uid) fail("internal", "starter-id-collision");
        });
        const player: PlayerDoc = {
          uid,
          displayName,
          createdAt: t,
          ageBand: ageBand as AgeBand,
          unlockedMutations: [],
          streak: { count: 0, lastDayUTC: null },
          limits: { dayUTC: utcDay(t), offers: 0, previews: 0 },
          sparks: 0,
          lastSurpriseDayUTC: null,
          cosmetics: [],
        };
        const starters = STARTERS.map((s, i) => {
          const genome = starter(uid, s.slot);
          return newCreature({
            id: ids[i],
            ownerUid: uid,
            name: s.name,
            genome,
            generation: 0,
            parentIds: [],
            comboKey: comboKeyOfGenome(genome),
            serial: null,
            discoveredFirst: false,
            paletteShift: 0,
            origin: "starter",
            bornAt: t,
            hatchedAt: s.hatchedAtRegistration ? t : null,
            createdAt: t,
          });
        });
        tx.setPlayer(player);
        starters.forEach((c) => tx.setCreature(c));
        return { player, starters, created: true };
      });
    },

    /** Breed offer for a friend (link). Caller's own teen-or-older creature; 20 per UTC day. */
    async createOffer(uidIn: string | null | undefined, input: { parentCreatureId?: unknown }) {
      const uid = requireUid(uidIn);
      const creatureId = requireString(input?.parentCreatureId, "parentCreatureId");
      return repo.runTransaction(async (tx) => {
        const t = now();
        const player = await loadPlayer(tx, uid);
        requireSocial(player);
        const creature = await loadOwnedCreature(tx, creatureId, uid);
        requireBreedable(creature, t);
        const limits = limitsFor(player, utcDay(t));
        if (limits.offers >= MAX_OFFERS_PER_DAY) fail("resource-exhausted", "offer-cap");
        limits.offers += 1;
        const offer: OfferDoc = {
          id: "o_" + randomToken().replace(/-/g, "").slice(0, 20),
          creatorUid: uid,
          parentCreatureId: creatureId,
          createdAt: t,
          expiresAt: t + OFFER_TTL_MS,
          status: "open",
        };
        if (await tx.getOffer(offer.id)) fail("internal", "offer-id-collision");
        tx.setPlayer({ ...player, limits });
        tx.setOffer(offer);
        return { offer, offersLeftToday: MAX_OFFERS_PER_DAY - limits.offers };
      });
    },

    /** Creator cancels an open offer; burns its open previews (spec §7.1 "Cancelling burns the offer"). */
    async cancelOffer(uidIn: string | null | undefined, input: { offerId?: unknown }) {
      const uid = requireUid(uidIn);
      const offerId = requireString(input?.offerId, "offerId");
      return repo.runTransaction(async (tx) => {
        const offer = await tx.getOffer(offerId);
        if (!offer) fail("not-found", "offer-not-found");
        const o = offer as OfferDoc;
        if (o.creatorUid !== uid) fail("permission-denied", "not-owner");
        if (o.status !== "open") fail("failed-precondition", "offer-" + o.status);
        const previews = (await tx.breedsByOffer(offerId, 500)).filter((b) => b.status === "preview");
        tx.setOffer({ ...o, status: "cancelled" });
        previews.forEach((b) => tx.setBreed({ ...b, status: "burned" }));
        return { offerId, burned: previews.length };
      });
    },

    /**
     * Single-use, bound preview (spec §7.1–7.4). One breed doc per (offer, my creature): asking again
     * returns the SAME nonce and child and does not count against the 10/day cap. Genomes come from
     * the registry and mutations from the caller's server record; nothing genetic is read from input.
     */
    async previewBreed(uidIn: string | null | undefined, input: { offerId?: unknown; myCreatureId?: unknown }): Promise<PreviewResult> {
      const uid = requireUid(uidIn);
      const offerId = requireString(input?.offerId, "offerId");
      const myCreatureId = requireString(input?.myCreatureId, "myCreatureId");
      return repo.runTransaction(async (tx) => {
        const t = now();
        const player = await loadPlayer(tx, uid);
        requireSocial(player);
        const offer = await tx.getOffer(offerId);
        if (!offer) fail("not-found", "offer-not-found");
        const o = offer as OfferDoc;
        if (o.creatorUid === uid) fail("permission-denied", "own-offer");
        if (!offerIsLive(o, t)) fail("failed-precondition", o.status === "open" ? "offer-expired" : "offer-" + o.status);
        const mine = await loadOwnedCreature(tx, myCreatureId, uid);
        const theirs = await tx.getCreature(o.parentCreatureId);
        if (!theirs || theirs.ownerUid !== o.creatorUid) fail("failed-precondition", "offer-parent-gone");
        const breedId = breedDocId(offerId, myCreatureId);
        const existing = await tx.getBreed(breedId);
        const limits = limitsFor(player, utcDay(t));

        if (existing) {
          if (existing.status !== "preview") fail("failed-precondition", "breed-" + existing.status);
          return {
            breedId,
            nonce: existing.nonce,
            child: existing.previewChild,
            myPaletteShift: existing.previewChild.paletteShift[uid] ?? 1,
            fresh: false,
            previewsLeftToday: MAX_PREVIEWS_PER_DAY - limits.previews,
          };
        }

        requireBreedable(mine, t);
        requireBreedable(theirs as CreatureDoc, t);
        if (limits.previews >= MAX_PREVIEWS_PER_DAY) fail("resource-exhausted", "preview-cap");
        limits.previews += 1;

        const nonce = randomToken();
        const mutations = sortMutations(player.unlockedMutations);
        const child = previewFrom(computeBreed(theirs as CreatureDoc, mine, nonce, mutations));
        const doc: BreedDoc = {
          id: breedId,
          offerId,
          offerCreatorUid: o.creatorUid,
          acceptorUid: uid,
          acceptorCreatureId: myCreatureId,
          nonce,
          unlockedMutations: mutations,
          previewChild: child,
          status: "preview",
          specVersion: SPEC_VERSION,
          createdAt: t,
          committedAt: null,
          childIds: [],
        };
        tx.setPlayer({ ...player, limits });
        tx.setBreed(doc);
        return {
          breedId,
          nonce,
          child,
          myPaletteShift: child.paletteShift[uid] ?? 1,
          fresh: true,
          previewsLeftToday: MAX_PREVIEWS_PER_DAY - limits.previews,
        };
      });
    },

    /**
     * Commit (spec §7.5) in one transaction: recompute with the stored nonce, create both twins,
     * serial = combos/{key}.count + 1, discoverer only if empty, offer -> used, sibling previews burned.
     * Retrying a committed breed returns the same creatures (replay: true).
     */
    async commitBreed(uidIn: string | null | undefined, input: { breedId?: unknown }): Promise<CommitResult> {
      const uid = requireUid(uidIn);
      const breedId = requireString(input?.breedId, "breedId");
      return repo.runTransaction(async (tx) => {
        const t = now();
        const b = await tx.getBreed(breedId);
        if (!b) fail("not-found", "breed-not-found");
        const bd = b as BreedDoc;
        if (bd.acceptorUid !== uid) fail("permission-denied", "not-acceptor");

        if (bd.status === "committed") {
          const kids = await Promise.all(bd.childIds.map((id) => tx.getCreature(id)));
          const creatures = kids.filter((c): c is CreatureDoc => c !== null);
          const mine = creatures.find((c) => c.ownerUid === uid) ?? creatures[0];
          return {
            breedId,
            creatures: mine ? [mine, ...creatures.filter((c) => c !== mine)] : [],
            serial: mine?.serial ?? 0,
            discoveredFirst: mine?.discoveredFirst ?? false,
            replay: true,
          };
        }
        if (bd.status !== "preview") fail("failed-precondition", "breed-" + bd.status);
        if (bd.specVersion !== SPEC_VERSION) fail("failed-precondition", "spec-changed");

        const offer = await tx.getOffer(bd.offerId);
        if (!offer) fail("failed-precondition", "offer-gone");
        const o = offer as OfferDoc;
        if (!offerIsLive(o, t)) fail("failed-precondition", o.status === "open" ? "offer-expired" : "offer-" + o.status);

        const mine = await tx.getCreature(bd.acceptorCreatureId);
        const theirs = await tx.getCreature(o.parentCreatureId);
        if (!mine || mine.ownerUid !== uid) fail("failed-precondition", "parent-gone");
        if (!theirs || theirs.ownerUid !== o.creatorUid) fail("failed-precondition", "offer-parent-gone");

        const result = computeBreed(theirs as CreatureDoc, mine as CreatureDoc, bd.nonce, bd.unlockedMutations);
        if (JSON.stringify(result.genome) !== JSON.stringify(bd.previewChild.genome) || result.id !== bd.previewChild.id) {
          fail("internal", "preview-mismatch");
        }
        const key = bd.previewChild.comboKey;
        const combo = await tx.getCombo(key);
        const siblings = (await tx.breedsByOffer(bd.offerId, 500)).filter((x) => x.id !== breedId && x.status === "preview");

        const serial = (combo?.count ?? 0) + 1;
        const discoveredFirst = !combo || combo.discovererUid === null;
        const gen = generation([(theirs as CreatureDoc).generation, (mine as CreatureDoc).generation]);
        const parentIds = [o.parentCreatureId, bd.acceptorCreatureId].sort((x, y) => (x < y ? -1 : x > y ? 1 : 0));

        const owners = [uid, o.creatorUid];
        const twinIds = owners.map((owner) => twinId(result, breedId, result.paletteShift[owner] ?? 0));
        for (const id of twinIds) if (await tx.getCreature(id)) fail("internal", "child-id-collision");

        const creatures = owners.map((owner, i) =>
          newCreature({
            id: twinIds[i],
            ownerUid: owner,
            name: "",
            genome: result.genome.map((p) => [p[0], p[1]]) as typeof result.genome,
            generation: gen,
            parentIds,
            comboKey: key,
            serial,
            discoveredFirst,
            paletteShift: result.paletteShift[owner] ?? 0,
            origin: "bred",
            bornAt: t,
            hatchedAt: null,
            createdAt: t,
          }),
        );

        creatures.forEach((c) => tx.setCreature(c));
        tx.setCombo({
          comboKey: key,
          discovererUid: discoveredFirst ? uid : (combo!.discovererUid),
          firstAt: combo?.firstAt ?? t,
          count: serial,
        });
        tx.setOffer({ ...o, status: "used" });
        tx.setBreed({ ...bd, status: "committed", committedAt: t, childIds: twinIds });
        siblings.forEach((s) => tx.setBreed({ ...s, status: "burned" }));
        return { breedId, creatures, serial, discoveredFirst, replay: false };
      });
    },

    /** Free daily surprise on the SERVER's UTC day (spec §8). Second claim the same day returns the same souvenir. */
    async claimDailySurprise(uidIn: string | null | undefined): Promise<SurpriseResult> {
      const uid = requireUid(uidIn);
      return repo.runTransaction(async (tx) => {
        const day = utcDay(now());
        const player = await loadPlayer(tx, uid);
        const souvenir = dailySurprise(uid, day);
        if (player.lastSurpriseDayUTC === day) {
          return { day, souvenir, alreadyClaimed: true, sparks: player.sparks };
        }
        const next: PlayerDoc = { ...player, lastSurpriseDayUTC: day, cosmetics: [...player.cosmetics] };
        if (souvenir.kind === "sparks") next.sparks += souvenir.amount;
        else if (!next.cosmetics.includes(souvenir.id)) next.cosmetics.push(souvenir.id);
        tx.setPlayer(next);
        return { day, souvenir, alreadyClaimed: false, sparks: next.sparks };
      });
    },

    /** Server-UTC streak check-in. Consecutive day -> +1, gap -> 1. Unlocks (STREAK_UNLOCKS) are permanent. */
    async checkInStreak(uidIn: string | null | undefined): Promise<StreakResult> {
      const uid = requireUid(uidIn);
      return repo.runTransaction(async (tx) => {
        const day = utcDay(now());
        const player = await loadPlayer(tx, uid);
        const unlocked = sortMutations(player.unlockedMutations);
        if (player.streak.lastDayUTC === day) {
          return { day, count: player.streak.count, alreadyCheckedIn: true, newlyUnlocked: [], unlockedMutations: unlocked };
        }
        const count = player.streak.lastDayUTC !== null && addDays(player.streak.lastDayUTC, 1) === day
          ? player.streak.count + 1
          : 1;
        const has = new Set(unlocked.map((m) => m.gene + ":" + m.variant));
        const newlyUnlocked = unlocksForStreak(count).filter((m) => !has.has(m.gene + ":" + m.variant));
        const all = sortMutations([...unlocked, ...newlyUnlocked]);
        tx.setPlayer({ ...player, streak: { count, lastDayUTC: day }, unlockedMutations: all });
        return { day, count, alreadyCheckedIn: false, newlyUnlocked, unlockedMutations: all };
      });
    },

    /** Rename (retro C3: names reach friends, so they pass the filter). */
    async renameCreature(uidIn: string | null | undefined, input: { id?: unknown; name?: unknown }) {
      const uid = requireUid(uidIn);
      const id = requireString(input?.id, "id");
      const verdict = checkName(input?.name);
      if (!verdict.ok) fail("invalid-argument", "bad-name", verdict.reason);
      const name = (verdict as { name: string }).name;
      return repo.runTransaction(async (tx) => {
        const c = await loadOwnedCreature(tx, id, uid);
        tx.setCreature({ ...c, name });
        return { id, name };
      });
    },

    /**
     * Account deletion (Apple 5.1.1(v), retro C4). Removes the player, their creatures, offers, previews
     * and breeds they took part in as acceptor; anonymizes combos they discovered; purges reports/blocks.
     * Friends keep their own twins. Runs in chunks; the adapter deletes the Auth user afterwards.
     */
    async deleteAccount(uidIn: string | null | undefined): Promise<DeleteResult> {
      const uid = requireUid(uidIn);
      const total: DeleteResult = { creatures: 0, offers: 0, breeds: 0, combosAnonymized: 0 };
      // Friends graph first: unlink duo (partner keeps a twin), leave crew, end visits, drop edges.
      await social.purgeAccount(uid);
      for (;;) {
        const done = await repo.runTransaction(async (tx) => {
          const creatures = await tx.creaturesByOwner(uid, BULK_CHUNK);
          // Few offers per chunk: each pulls its breeds too, and Firestore caps a transaction at 500 writes.
          const offers = await tx.offersByCreator(uid, 10);
          const asAcceptor = await tx.breedsByAcceptor(uid, BULK_CHUNK);
          const onMyOffers: BreedDoc[] = [];
          for (const o of offers) onMyOffers.push(...(await tx.breedsByOffer(o.id, BULK_CHUNK)));
          const combos = await tx.combosByDiscoverer(uid, BULK_CHUNK);
          // Friends' previews on my offers die with the offer; committed breeds keep the friend's twin.
          const breedIds = new Set([...asAcceptor.map((b) => b.id), ...onMyOffers.map((b) => b.id)]);
          creatures.forEach((c) => tx.deleteCreature(c.id));
          offers.forEach((o) => tx.deleteOffer(o.id));
          breedIds.forEach((id) => tx.deleteBreed(id));
          combos.forEach((c) => tx.setCombo({ ...c, discovererUid: DELETED_UID }));
          total.creatures += creatures.length;
          total.offers += offers.length;
          total.breeds += breedIds.size;
          total.combosAnonymized += combos.length;
          return creatures.length + offers.length + breedIds.size + combos.length === 0;
        });
        if (done) break;
      }
      await repo.runTransaction(async (tx) => {
        if (await tx.getPlayer(uid)) tx.deletePlayer(uid);
      });
      await repo.purgeSocial(uid);
      return total;
    },

    /** Hourly job: expire offers past 72 h (+ burn their previews), burn previews older than 24 h. */
    async sweep(): Promise<{ expiredOffers: number; burnedPreviews: number }> {
      const t = now();
      let expiredOffers = 0;
      let burnedPreviews = 0;
      for (;;) {
        const n = await repo.runTransaction(async (tx) => {
          const offers = await tx.openOffersExpiredBy(t, BULK_CHUNK);
          const previews: BreedDoc[] = [];
          for (const o of offers) previews.push(...(await tx.breedsByOffer(o.id, 500)).filter((b) => b.status === "preview"));
          offers.forEach((o) => tx.setOffer({ ...o, status: "expired" }));
          previews.forEach((b) => tx.setBreed({ ...b, status: "burned" }));
          expiredOffers += offers.length;
          burnedPreviews += previews.length;
          return offers.length;
        });
        if (n === 0) break;
      }
      for (;;) {
        const n = await repo.runTransaction(async (tx) => {
          const stale = await tx.previewsCreatedBy(t - PREVIEW_TTL_MS, BULK_CHUNK);
          stale.forEach((b) => tx.setBreed({ ...b, status: "burned" }));
          burnedPreviews += stale.length;
          return stale.length;
        });
        if (n === 0) break;
      }
      return { expiredOffers, burnedPreviews };
    },
  };
}

export type Services = ReturnType<typeof createServices>;
export { DomainError };
export { creatureSigPayload } from "./guards.ts";
