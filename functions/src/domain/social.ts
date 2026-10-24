// Friends graph: invites, friendships, visits, Duo, Crew, pokes (backend-spec "Friends graph";
// living-world-spec §10 visits, §11 Duo, §12 Crew, §13 pokes). Pure: engine-ts + Repository port only.
//
// PRIVACY (§11 RED LINES): nothing here stores or returns another user's location, weather, time zone,
// local day, online / last-seen / opened-app status, read receipts, steps or wake data, and no
// relationship score. Per-member wave days live in server-only `duoPrivate/{id}`. Unlink and leave are
// quiet: no doc records who ended a link. Diaries carry creature names only.

import { breed, comboKeyOfGenome, fnv1a32, generation, hex8, mulberry32, type Genome } from "./engine.ts";
import {
  BOND_MAX_LEVEL, BOND_SUGGEST_BREED_LEVEL, CREW_MAX, CREW_MIN, DUO_ANNIVERSARY_DAYS, DUO_FRAMING_MIN_BAND,
  DUO_MIN_AGE_BAND, DUO_RELINK_COOLDOWN_MS, HOUSE_SLOTS, INVITE_TTL_MS, LOCAL_DAY_SKEW_MS, MAX_GUESTS_PER_HOST,
  MAX_INVITES_PER_DAY, MAX_NOTES_PER_DAY, MAX_PAINTINGS, MAX_POKES_PER_DAY, MIN_BREED_STAGE, NOTE_EMOTES, NOTE_PROPS,
  NOTES_SHOWN, POKE_EMOTES, ROLL_CALL_EMOTES, UNNAMED_CREATURE, VISIT_MAX_DAYS, VISIT_MIN_DAYS, VISIT_SOUVENIRS,
  WAVE_BACK_WINDOW_MS,
} from "./config.ts";
import { fail } from "./errors.ts";
import { atLeast, stageOf } from "./growth.ts";
import {
  bandAtLeast, creatureFactory, id64, loadOwnedCreature, requireSocial, requireString, requireUid,
} from "./guards.ts";
import { BULK_CHUNK, type Repository, type Tx } from "./repository.ts";
import { DAY_MS, HOUR_MS, utcDay } from "./time.ts";
import type {
  AgeBand, AwayDoc, BondDoc, CooldownDoc, CreatureDoc, CrewDoc, DuoDoc, DuoFraming, DuoPrivateDoc, FriendDoc, GalleryDoc,
  HouseDoc, InviteDoc, InviteKind, LinksDoc, NoteDoc, PlayerDoc, PokeDoc, VisitDiary, VisitDoc,
} from "./types.ts";

// MARK: config + paths

export interface SocialConfig {
  /** Youngest band allowed into a Duo (default 13to15; under13 is always offline). */
  duoMinAgeBand: AgeBand;
  /** If any member is below this band (under 16), framing is forced to "bestFriends". */
  duoFramingMinBand: AgeBand;
}

export const DEFAULT_SOCIAL_CONFIG: SocialConfig = {
  duoMinAgeBand: DUO_MIN_AGE_BAND,
  duoFramingMinBand: DUO_FRAMING_MIN_BAND,
};

export interface SocialDeps {
  repo: Repository;
  now: () => number;
  randomToken: () => string;
  sign: (payload: string) => string;
  social?: Partial<SocialConfig>;
}

export const P = {
  invite: (code: string) => `invites/${code}`,
  invites: "invites",
  friend: (uid: string, f: string) => `friends/${uid}/list/${f}`,
  friends: (uid: string) => `friends/${uid}/list`,
  block: (uid: string, other: string) => `blocks/${uid}/list/${other}`,
  visit: (id: string) => `visits/${id}`,
  away: (creatureId: string) => `away/${creatureId}`,
  visits: "visits",
  bond: (id: string) => `bonds/${id}`,
  bonds: "bonds",
  duo: (id: string) => `duos/${id}`,
  duoPrivate: (id: string) => `duoPrivate/${id}`,
  duoHouse: (id: string) => `duos/${id}/house/state`,
  duoNote: (id: string, n: string) => `duos/${id}/notes/${n}`,
  duoNotes: (id: string) => `duos/${id}/notes`,
  crew: (id: string) => `crews/${id}`,
  crewHouse: (id: string) => `crews/${id}/house/state`,
  links: (uid: string) => `links/${uid}`,
  cooldown: (id: string) => `cooldowns/${id}`,
  poke: (id: string) => `pokes/${id}`,
  pokes: "pokes",
  gallery: (uid: string, id: string) => `gallery/${uid}/items/${id}`,
  galleryItems: (uid: string) => `gallery/${uid}/items`,
} as const;

const DUO_OWNER = (id: string) => "duo:" + id;
const CREW_OWNER = (id: string) => "crew:" + id;

const sorted = (xs: readonly string[]) => [...xs].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
export const pairKey = (a: string, b: string) => id64("p_", sorted([a, b]).join("|"));
export const bondId = (a: string, b: string) => id64("k_", sorted([a, b]).join("|"));

const LOCAL_DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

/** Accepts a client local calendar day only if it can be "today" somewhere on Earth right now. */
export function checkLocalDay(v: unknown, now: number): string {
  if (typeof v !== "string" || !LOCAL_DAY_RE.test(v)) fail("invalid-argument", "bad-localDay");
  const start = Date.parse((v as string) + "T00:00:00.000Z");
  if (Number.isNaN(start) || utcDay(start) !== v) fail("invalid-argument", "bad-localDay");
  // Local midnight is between UTC-12 and UTC+14 of the UTC midnight.
  if (now < start - LOCAL_DAY_SKEW_MS || now >= start + DAY_MS + 12 * HOUR_MS) fail("invalid-argument", "bad-localDay");
  return v as string;
}

/** Anniversaries (§11): day 7/30/100/365 after linking, plus the duo creature's hatch day. */
export function duoAnniversaries(createdAt: number, now: number) {
  const daysTogether = Math.max(0, Math.floor((now - createdAt) / DAY_MS));
  const milestones = DUO_ANNIVERSARY_DAYS.map((day) => ({ day, reached: daysTogether >= day, today: daysTogether === day }));
  const next = DUO_ANNIVERSARY_DAYS.find((d) => d > daysTogether) ?? null;
  return { daysTogether, milestones, next };
}

/**
 * Crew mascot gene relay (§12): each member donates one gene in turn. Deterministic from the crew id
 * and the ordered donors via engine-ts fnv1a32 + mulberry32: a seeded rotation picks who starts the relay,
 * then gene g comes from donor (start + g) mod n (both alleles). With 3–5 donors and 8 genes everyone donates.
 */
export function geneRelay(crewId: string, donors: readonly { id: string; genome: Genome }[]): Genome {
  if (donors.length === 0) throw new RangeError("geneRelay needs donors");
  const rng = mulberry32(fnv1a32("mascot|" + crewId + "|" + donors.map((d) => d.id).join(",")));
  const start = rng.int(donors.length);
  return donors[0].genome.map((_, g) => {
    const pair = donors[(start + g) % donors.length].genome[g];
    return [pair[0], pair[1]];
  }) as Genome;
}

// MARK: visit diary (templated; creature names only — never uids, display names or places)

const DIARY_SCENES = [
  "{v} and {h} built a pillow fort.",
  "{v} and {h} played chess. {w} won!",
  "{v} and {h} painted a picture together.",
  "{v} and {h} counted the stars.",
  "{v} and {h} cooked tiny pancakes.",
  "{v} and {h} napped in a sunny spot.",
  "{v} and {h} chatted with lots of emotes.",
  "{v} and {h} had a dance party.",
];

const nameOf = (c: Pick<CreatureDoc, "name"> | null) => (c && c.name ? c.name : UNNAMED_CREATURE);

export function visitDiary(visitId: string, visitorName: string, hostName: string | null, hoursHosted: number): VisitDiary {
  const h = hostName ?? "a new friend";
  const rng = mulberry32(fnv1a32("diary|" + visitId));
  const n = Math.min(VISIT_MAX_DAYS, Math.max(1, Math.floor(hoursHosted / 24) + 1));
  const used = new Set<number>();
  const lines: string[] = [];
  while (lines.length < n) {
    const i = rng.int(DIARY_SCENES.length);
    if (used.has(i)) continue;
    used.add(i);
    const winner = rng.int(2) === 0 ? visitorName : h;
    lines.push(DIARY_SCENES[i].replaceAll("{v}", visitorName).replaceAll("{h}", h).replaceAll("{w}", winner));
  }
  lines.push(`${visitorName} brought home a souvenir.`);
  return { title: hostName ? `My visit to ${hostName}` : "My visit to a friend's house", lines };
}

export function visitSouvenir(visitId: string): string {
  return VISIT_SOUVENIRS[fnv1a32("souvenir|" + visitId) % VISIT_SOUVENIRS.length];
}

// MARK: read models (what other members may see)

export interface DuoView {
  id: string;
  framing: DuoFraming;
  members: string[];
  creatureId: string | null;
  daysBothWaved: number;
  daysTogether: number;
  anniversaries: { day: number; reached: boolean; today: boolean }[];
  nextAnniversary: number | null;
  /** The partner waved and is waiting for a wave back (a gesture, no time attached). */
  waveWaiting: boolean;
  house: HouseDoc;
  notes: { id: string; mine: boolean; emote: string; prop: string }[];
}

export interface CrewView {
  id: string;
  status: CrewDoc["status"];
  members: string[];
  mascotId: string | null;
  rollCall: Record<string, string>;
  house: HouseDoc;
}

export interface VisitorView {
  visitId: string;
  end: number;
  creature: Pick<CreatureDoc, "id" | "name" | "genome" | "generation" | "comboKey" | "paletteShift">;
  readOnly: true;
}

function emptySlots(): Record<string, string | null> {
  return Object.fromEntries(HOUSE_SLOTS.map((s) => [s, null]));
}

// MARK: transaction context (all reads first, one write per doc at the end)

class Ctx {
  readonly tx: Tx;
  private docs = new Map<string, { doc: unknown; dirty: boolean; deleted: boolean }>();
  private creatures = new Map<string, { doc: CreatureDoc | null; dirty: boolean; deleted: boolean }>();
  private players = new Map<string, { doc: PlayerDoc | null; dirty: boolean }>();
  constructor(tx: Tx) {
    this.tx = tx;
  }
  async doc<T>(path: string): Promise<T | null> {
    const hit = this.docs.get(path);
    if (hit) return hit.deleted ? null : (hit.doc as T | null);
    const d = await this.tx.getDoc<T>(path);
    this.docs.set(path, { doc: d, dirty: false, deleted: false });
    return d;
  }
  async query<T extends object>(coll: string, where: Parameters<Tx["queryDocs"]>[1], limit: number, pathOf: (d: T) => string, orderBy?: string): Promise<T[]> {
    const out = await this.tx.queryDocs<T>(coll, where, limit, orderBy);
    for (const d of out) if (!this.docs.has(pathOf(d))) this.docs.set(pathOf(d), { doc: d, dirty: false, deleted: false });
    return out.map((d) => this.docs.get(pathOf(d))!.doc as T).filter((d) => d !== null);
  }
  set(path: string, doc: object) {
    this.docs.set(path, { doc, dirty: true, deleted: false });
  }
  del(path: string) {
    this.docs.set(path, { doc: null, dirty: true, deleted: true });
  }
  async creature(id: string): Promise<CreatureDoc | null> {
    const hit = this.creatures.get(id);
    if (hit) return hit.deleted ? null : hit.doc;
    const c = await this.tx.getCreature(id);
    this.creatures.set(id, { doc: c, dirty: false, deleted: false });
    return c;
  }
  async ownedBy(uid: string, limit: number): Promise<CreatureDoc[]> {
    const list = await this.tx.creaturesByOwner(uid, limit);
    for (const c of list) if (!this.creatures.has(c.id)) this.creatures.set(c.id, { doc: c, dirty: false, deleted: false });
    return list.map((c) => this.creatures.get(c.id)!).filter((e) => !e.deleted && e.doc).map((e) => e.doc!);
  }
  setCreature(c: CreatureDoc) {
    this.creatures.set(c.id, { doc: c, dirty: true, deleted: false });
  }
  delCreature(id: string) {
    this.creatures.set(id, { doc: null, dirty: true, deleted: true });
  }
  async player(uid: string): Promise<PlayerDoc | null> {
    const hit = this.players.get(uid);
    if (hit) return hit.doc;
    const p = await this.tx.getPlayer(uid);
    this.players.set(uid, { doc: p, dirty: false });
    return p;
  }
  async mustPlayer(uid: string): Promise<PlayerDoc> {
    const p = await this.player(uid);
    if (!p) fail("failed-precondition", "not-registered");
    return p as PlayerDoc;
  }
  setPlayer(p: PlayerDoc) {
    this.players.set(p.uid, { doc: p, dirty: true });
  }
  flush() {
    for (const [path, e] of this.docs) if (e.dirty) e.deleted ? this.tx.deleteDoc(path) : this.tx.setDoc(path, e.doc as object);
    for (const [id, e] of this.creatures) if (e.dirty) e.deleted ? this.tx.deleteCreature(id) : this.tx.setCreature(e.doc!);
    for (const [, e] of this.players) if (e.dirty && e.doc) this.tx.setPlayer(e.doc);
  }
}

// MARK: services

export function createSocialServices(deps: SocialDeps) {
  const { repo, now, randomToken } = deps;
  const cfg: SocialConfig = { ...DEFAULT_SOCIAL_CONFIG, ...(deps.social ?? {}) };
  const newCreature = creatureFactory(deps.sign);

  /** Runs fn with a read-then-write context; all writes are applied once fn resolves. */
  const run = <T>(fn: (c: Ctx) => Promise<T>) =>
    repo.runTransaction(async (tx) => {
      const c = new Ctx(tx);
      const out = await fn(c);
      c.flush();
      return out;
    });

  const socialLimits = (p: PlayerDoc, day: string) =>
    p.social && p.social.dayUTC === day ? { ...p.social } : { dayUTC: day, pokes: 0, invites: 0 };

  async function socialPlayer(c: Ctx, uid: string) {
    const p = await c.mustPlayer(uid);
    requireSocial(p);
    return p;
  }

  async function areFriends(c: Ctx, a: string, b: string) {
    return (await c.doc<FriendDoc>(P.friend(a, b))) !== null;
  }

  async function requireNotBlocked(c: Ctx, a: string, b: string) {
    const x = await c.doc(P.block(a, b));
    const y = await c.doc(P.block(b, a));
    // Same reason as "not friends" so a block is never revealed.
    if (x || y) fail("failed-precondition", "not-friends");
  }

  async function requireFriends(c: Ctx, a: string, b: string) {
    await requireNotBlocked(c, a, b);
    if (!(await areFriends(c, a, b))) fail("failed-precondition", "not-friends");
  }

  async function links(c: Ctx, uid: string): Promise<LinksDoc> {
    return (await c.doc<LinksDoc>(P.links(uid))) ?? { uid, duoId: null, crewId: null };
  }

  function writeLinks(c: Ctx, l: LinksDoc) {
    if (l.duoId === null && l.crewId === null) c.del(P.links(l.uid));
    else c.set(P.links(l.uid), l);
  }

  async function requireOwnPlainCreature(c: Ctx, cr: CreatureDoc, t: number, needBreedable: boolean) {
    if (await c.doc(P.away(cr.id))) fail("failed-precondition", "creature-away");
    if (needBreedable && !atLeast(stageOf(cr, t), MIN_BREED_STAGE)) fail("failed-precondition", "too-young");
  }

  /** §11: forced "bestFriends" if any member is under 16; else the members' choice. */
  function framingFor(members: readonly PlayerDoc[], wanted: DuoFraming): DuoFraming {
    return members.every((m) => bandAtLeast(m.ageBand, cfg.duoFramingMinBand)) ? wanted : "bestFriends";
  }

  function parseFraming(v: unknown): DuoFraming | undefined {
    if (v === undefined || v === null) return undefined;
    if (v !== "duo" && v !== "bestFriends") fail("invalid-argument", "bad-framing");
    return v as DuoFraming;
  }

  async function memberDuo(c: Ctx, uid: string, duoId: string) {
    const d = await c.doc<DuoDoc>(P.duo(duoId));
    if (!d || !d.members.includes(uid)) fail("not-found", "duo-not-found");
    if ((d as DuoDoc).status !== "active") fail("failed-precondition", "duo-ended");
    return d as DuoDoc;
  }

  async function memberCrew(c: Ctx, uid: string, crewId: string) {
    const d = await c.doc<CrewDoc>(P.crew(crewId));
    if (!d || !d.members.includes(uid) || d.status === "ended") fail("not-found", "crew-not-found");
    return d as CrewDoc;
  }

  // -- visits

  async function hostedBy(c: Ctx, hostUid: string) {
    return c.query<VisitDoc>(P.visits, [{ field: "hostUid", op: "==", value: hostUid }, { field: "status", op: "==", value: "active" }], 50, (v) => P.visit(v.id));
  }

  async function ownedVisits(c: Ctx, ownerUid: string) {
    return c.query<VisitDoc>(P.visits, [{ field: "ownerUid", op: "==", value: ownerUid }, { field: "status", op: "==", value: "active" }], 50, (v) => P.visit(v.id));
  }

  /** Returns a visitor home: diary, souvenir for the owner, bond +1 if hosted ≥ 12 h. Reads only, then queues writes on c. */
  async function returnVisit(c: Ctx, v: VisitDoc, t: number, opts: { rewards: boolean }) {
    const visitor = await c.creature(v.visitorCreatureId);
    const hostCr = v.hostCreatureId ? await c.creature(v.hostCreatureId) : null;
    const owner = await c.player(v.ownerUid);
    const bId = v.hostCreatureId ? bondId(v.visitorCreatureId, v.hostCreatureId) : null;
    const bond = bId ? await c.doc<BondDoc>(P.bond(bId)) : null;

    const hours = (Math.min(t, v.end) - v.start) / HOUR_MS;
    const diary = visitDiary(v.id, nameOf(visitor), hostCr ? nameOf(hostCr) : null, hours);
    const souvenirId = opts.rewards ? visitSouvenir(v.id) : null;
    // returnedAt is deliberately NOT stored: the host must not learn when the owner recalled.
    c.set(P.visit(v.id), { ...v, status: "returned", diary, souvenirId } satisfies VisitDoc);
    c.del(P.away(v.visitorCreatureId));
    if (opts.rewards && owner && souvenirId && !owner.cosmetics.includes(souvenirId)) {
      c.setPlayer({ ...owner, cosmetics: [...owner.cosmetics, souvenirId] });
    }
    let level = bond?.level ?? 0;
    if (opts.rewards && bId && hostCr && visitor && hours >= 12) {
      level = Math.min(BOND_MAX_LEVEL, level + 1);
      c.set(P.bond(bId), {
        id: bId,
        creatureIds: sorted([v.visitorCreatureId, v.hostCreatureId!]),
        ownerUids: sorted([v.ownerUid, v.hostUid]),
        level,
        visits: (bond?.visits ?? 0) + 1,
      } satisfies BondDoc);
    }
    return { visitId: v.id, diary, souvenirId, bondLevel: level, suggestBreed: level >= BOND_SUGGEST_BREED_LEVEL };
  }

  // -- duo unlink (quiet)

  async function unlinkDuoIn(c: Ctx, d: DuoDoc, t: number, opts: { twinsFor: string[] }) {
    const priv = await c.doc<DuoPrivateDoc>(P.duoPrivate(d.id));
    const house = await c.doc<HouseDoc>(P.duoHouse(d.id));
    const duoCr = d.creatureId ? await c.creature(d.creatureId) : null;
    const ls = await Promise.all(d.members.map((m) => links(c, m)));
    const notes = await c.query<NoteDoc>(P.duoNotes(d.id), [], 500, (n) => P.duoNote(d.id, n.id));

    const day = utcDay(t);
    // Duo creature -> twins, one each (same genome, own palette shift).
    const twins: Record<string, string> = {};
    if (duoCr) {
      for (const m of opts.twinsFor) {
        const id = id64("t_", duoCr.id + "|" + m);
        twins[m] = id;
        const { coOwnerUids: _co, ...base } = duoCr;
        c.setCreature(newCreature({
          ...base, id, ownerUid: m, paletteShift: priv?.paletteShift[m] ?? 0, origin: "duo", createdAt: t,
          genome: duoCr.genome.map((p) => [p[0], p[1]]) as Genome,
        }));
      }
      c.delCreature(duoCr.id);
    }
    // Shared paintings copied to each member's gallery; the house is kept as a memory.
    // Decorations were only references to each member's own cosmetics, so they simply return to their owner.
    const returnedItems: Record<string, string[]> = {};
    for (const m of opts.twinsFor) {
      for (const p of house?.paintings ?? []) {
        c.set(P.gallery(m, "dp_" + p.id), { id: "dp_" + p.id, kind: "painting", group: "duo", seed: p.seed, rooms: null, day: p.day } satisfies GalleryDoc);
      }
      if (house) {
        const other = d.members.find((x) => x !== m);
        const memId = id64("hm_", d.id + "|" + m);
        c.set(P.gallery(m, memId), {
          id: memId, kind: "house-memory", group: "duo", seed: null, day,
          rooms: { mine: { ...(house.slots[m] ?? emptySlots()) }, theirs: { ...(other ? house.slots[other] ?? emptySlots() : emptySlots()) } },
        } satisfies GalleryDoc);
      }
      returnedItems[m] = Object.values(house?.slots[m] ?? {}).filter((x): x is string => typeof x === "string");
    }
    c.del(P.duoHouse(d.id));
    c.del(P.duoPrivate(d.id));
    notes.forEach((n) => c.del(P.duoNote(d.id, n.id)));
    // No endedBy / reason / timestamp: the partner only sees the duo is over.
    c.set(P.duo(d.id), { ...d, status: "ended", creatureId: null } satisfies DuoDoc);
    ls.forEach((l) => writeLinks(c, { ...l, duoId: l.duoId === d.id ? null : l.duoId }));
    if (d.members.length === 2) {
      const k = pairKey(d.members[0], d.members[1]);
      c.set(P.cooldown(k), { id: k, until: t + DUO_RELINK_COOLDOWN_MS } satisfies CooldownDoc);
    }
    return { twins, returnedItems };
  }

  // -- crew

  async function rebuildMascot(c: Ctx, crew: CrewDoc, t: number): Promise<string | null> {
    const donorDocs: CreatureDoc[] = [];
    for (const m of crew.members) {
      const cr = await c.creature(crew.donors[m]);
      if (cr) donorDocs.push(cr);
    }
    if (crew.members.length < CREW_MIN || donorDocs.length === 0) return crew.mascotId;
    const id = crew.mascotId ?? id64("m_", crew.id);
    const genome = geneRelay(crew.id, donorDocs);
    const existing = crew.mascotId ? await c.creature(id) : null;
    c.setCreature(newCreature({
      id,
      ownerUid: CREW_OWNER(crew.id),
      coOwnerUids: [...crew.members],
      name: existing?.name ?? "",
      genome,
      generation: generation(donorDocs.map((d) => d.generation)),
      parentIds: sorted(donorDocs.map((d) => d.id)),
      comboKey: comboKeyOfGenome(genome),
      serial: null,
      discoveredFirst: false,
      paletteShift: 0,
      origin: "mascot",
      bornAt: existing?.bornAt ?? t,
      hatchedAt: existing?.hatchedAt ?? t,
      createdAt: existing?.createdAt ?? t,
    }));
    return id;
  }

  async function leaveCrewIn(c: Ctx, crew: CrewDoc, uid: string, t: number, opts: { keepCopy: boolean }) {
    const mascot = crew.mascotId ? await c.creature(crew.mascotId) : null;
    const house = await c.doc<HouseDoc>(P.crewHouse(crew.id));
    const l = await links(c, uid);
    const members = crew.members.filter((m) => m !== uid);
    const { [uid]: _d, ...donors } = crew.donors;
    let copyId: string | null = null;
    if (mascot && opts.keepCopy) {
      copyId = id64("mc_", mascot.id + "|" + uid + "|" + t);
      const { coOwnerUids: _co, ...base } = mascot;
      c.setCreature(newCreature({ ...base, id: copyId, ownerUid: uid, createdAt: t, genome: mascot.genome.map((p) => [p[0], p[1]]) as Genome }));
    }
    if (members.length === 0) {
      if (mascot) c.delCreature(mascot.id);
      c.del(P.crewHouse(crew.id));
      c.set(P.crew(crew.id), { ...crew, members: [], donors: {}, status: "ended", mascotId: null, rollCall: { day: "", emotes: {} } } satisfies CrewDoc);
    } else {
      if (mascot) c.setCreature({ ...mascot, coOwnerUids: members });
      if (house) {
        const { [uid]: _s, ...slots } = house.slots;
        c.set(P.crewHouse(crew.id), { ...house, slots } satisfies HouseDoc);
      }
      const { [uid]: _e, ...emotes } = crew.rollCall.emotes;
      c.set(P.crew(crew.id), {
        ...crew, members, donors, status: members.length >= CREW_MIN ? "active" : "forming", rollCall: { ...crew.rollCall, emotes },
      } satisfies CrewDoc);
    }
    writeLinks(c, { ...l, crewId: null });
    return { crewId: crew.id, mascotCopyId: copyId };
  }

  // -- friendships

  async function removeFriendIn(c: Ctx, uid: string, friendUid: string, t: number) {
    const myVisits = (await ownedVisits(c, uid)).filter((v) => v.hostUid === friendUid);
    const theirVisits = (await ownedVisits(c, friendUid)).filter((v) => v.hostUid === uid);
    const mine = await links(c, uid);
    const duo = mine.duoId ? await c.doc<DuoDoc>(P.duo(mine.duoId)) : null;
    const results = [];
    for (const v of [...myVisits, ...theirVisits]) results.push(await returnVisit(c, v, t, { rewards: true }));
    let unlinked = false;
    if (duo && duo.status === "active" && duo.members.includes(friendUid)) {
      await unlinkDuoIn(c, duo, t, { twinsFor: duo.members });
      unlinked = true;
    }
    c.del(P.friend(uid, friendUid));
    c.del(P.friend(friendUid, uid));
    return { visitsEnded: results.length, duoUnlinked: unlinked };
  }

  return {
    /** Single-use, 24 h invite code. Duo/crew invites name the creator's parent / gene donor. */
    async createInvite(uidIn: string | null | undefined, input: { kind?: unknown; creatureId?: unknown; framing?: unknown }) {
      const uid = requireUid(uidIn);
      const kind = input?.kind;
      if (kind !== "friend" && kind !== "duo" && kind !== "crew") fail("invalid-argument", "bad-kind");
      const framing = kind === "duo" ? parseFraming(input?.framing) : undefined;
      const creatureId = kind === "friend" ? null : requireString(input?.creatureId, "creatureId");
      return run(async (c) => {
        const t = now();
        const p = await socialPlayer(c, uid);
        const l = await links(c, uid);
        const code = "i_" + randomToken().replace(/-/g, "").slice(0, 24);
        if (await c.doc(P.invite(code))) fail("internal", "invite-id-collision");
        if (kind === "duo") {
          if (!bandAtLeast(p.ageBand, cfg.duoMinAgeBand)) fail("permission-denied", "age-restricted");
          if (l.duoId) fail("failed-precondition", "already-in-duo");
          await requireOwnPlainCreature(c, await loadOwnedCreature(c.tx, creatureId!, uid), t, true);
        }
        if (kind === "crew") {
          await requireOwnPlainCreature(c, await loadOwnedCreature(c.tx, creatureId!, uid), t, false);
          if (l.crewId) {
            const crew = await memberCrew(c, uid, l.crewId);
            if (crew.members.length >= CREW_MAX) fail("failed-precondition", "crew-full");
          } else {
            const crewId = id64("cr_", uid + "|" + code);
            c.set(P.crew(crewId), {
              id: crewId, members: [uid], status: "forming", createdAt: t, donors: { [uid]: creatureId! }, mascotId: null, rollCall: { day: "", emotes: {} },
            } satisfies CrewDoc);
            c.set(P.crewHouse(crewId), { slots: { [uid]: emptySlots() }, paintings: [] } satisfies HouseDoc);
            writeLinks(c, { ...l, crewId });
          }
        }
        const lim = socialLimits(p, utcDay(t));
        if (lim.invites >= MAX_INVITES_PER_DAY) fail("resource-exhausted", "invite-cap");
        lim.invites += 1;
        c.setPlayer({ ...p, social: lim });
        const invite: InviteDoc = {
          code, creatorUid: uid, kind: kind as InviteKind, creatorCreatureId: creatureId, createdAt: t, expiresAt: t + INVITE_TTL_MS, usedBy: null,
          ...(framing ? { framing } : {}),
        };
        c.set(P.invite(code), invite);
        return { code, kind, expiresAt: invite.expiresAt };
      });
    },

    /** Mutual consent: the creator made the invite, the acceptor redeems it. Friend → friendship, duo → Duo, crew → membership. */
    async acceptInvite(uidIn: string | null | undefined, input: { code?: unknown; creatureId?: unknown }) {
      const uid = requireUid(uidIn);
      const code = requireString(input?.code, "code", 64);
      return run(async (c) => {
        const t = now();
        const inv = await c.doc<InviteDoc>(P.invite(code));
        if (!inv) fail("not-found", "invite-not-found");
        const i = inv as InviteDoc;
        if (i.usedBy !== null) fail("failed-precondition", "invite-used");
        if (t >= i.expiresAt) fail("failed-precondition", "invite-expired");
        if (i.creatorUid === uid) fail("permission-denied", "own-invite");
        const me = await socialPlayer(c, uid);
        const them = await c.player(i.creatorUid);
        if (!them || !bandAtLeast(them.ageBand, "13to15")) fail("failed-precondition", "invite-not-found");
        await requireNotBlocked(c, uid, i.creatorUid);
        const done = () => c.set(P.invite(code), { ...i, usedBy: uid } satisfies InviteDoc);

        if (i.kind === "friend") {
          const already = await areFriends(c, uid, i.creatorUid);
          if (!already) {
            c.set(P.friend(uid, i.creatorUid), { uid, friendUid: i.creatorUid, since: t } satisfies FriendDoc);
            c.set(P.friend(i.creatorUid, uid), { uid: i.creatorUid, friendUid: uid, since: t } satisfies FriendDoc);
          }
          done();
          return { kind: "friend" as const, friendUid: i.creatorUid, alreadyFriends: already };
        }

        if (!(await areFriends(c, uid, i.creatorUid))) fail("failed-precondition", "not-friends");
        const myCreatureId = requireString(input?.creatureId, "creatureId");
        const mine = await loadOwnedCreature(c.tx, myCreatureId, uid);

        if (i.kind === "duo") {
          if (!bandAtLeast(me.ageBand, cfg.duoMinAgeBand) || !bandAtLeast(them!.ageBand, cfg.duoMinAgeBand)) fail("permission-denied", "age-restricted");
          const [lm, lt] = [await links(c, uid), await links(c, i.creatorUid)];
          if (lm.duoId || lt.duoId) fail("failed-precondition", "already-in-duo");
          const cd = await c.doc<CooldownDoc>(P.cooldown(pairKey(uid, i.creatorUid)));
          if (cd && t < cd.until) fail("failed-precondition", "relink-cooldown");
          const theirs = await c.creature(i.creatorCreatureId!);
          if (!theirs || theirs.ownerUid !== i.creatorUid) fail("failed-precondition", "invite-parent-gone");
          await requireOwnPlainCreature(c, mine, t, true);
          await requireOwnPlainCreature(c, theirs as CreatureDoc, t, true);

          const duoId = id64("d_", sorted([uid, i.creatorUid]).join("|") + "|" + code);
          const result = breed({
            parentA: { id: (theirs as CreatureDoc).id, genome: (theirs as CreatureDoc).genome, owner: i.creatorUid },
            parentB: { id: mine.id, genome: mine.genome, owner: uid },
            nonce: "duo|" + code,
            unlockedMutations: [],
          });
          const crId = id64("dc_", duoId);
          const members = [i.creatorUid, uid];
          c.setCreature(newCreature({
            id: crId, ownerUid: DUO_OWNER(duoId), coOwnerUids: members, name: "", genome: result.genome,
            generation: generation([(theirs as CreatureDoc).generation, mine.generation]),
            parentIds: sorted([(theirs as CreatureDoc).id, mine.id]), comboKey: comboKeyOfGenome(result.genome),
            serial: null, discoveredFirst: false, paletteShift: 0, origin: "duo", bornAt: t, hatchedAt: null, createdAt: t,
          }));
          const framing = framingFor([me, them!], i.framing ?? "duo");
          c.set(P.duo(duoId), {
            id: duoId, members, status: "active", framing, createdAt: t, creatureId: crId, daysBothWaved: 0,
          } satisfies DuoDoc);
          c.set(P.duoPrivate(duoId), {
            id: duoId, waves: { [uid]: null, [i.creatorUid]: null }, notes: {}, noteSeq: 0, paletteShift: result.paletteShift,
          } satisfies DuoPrivateDoc);
          c.set(P.duoHouse(duoId), { slots: { [uid]: emptySlots(), [i.creatorUid]: emptySlots() }, paintings: [] } satisfies HouseDoc);
          writeLinks(c, { ...lm, duoId });
          writeLinks(c, { ...lt, duoId });
          done();
          return { kind: "duo" as const, duoId, creatureId: crId };
        }

        // crew
        const lm = await links(c, uid);
        const lt = await links(c, i.creatorUid);
        if (lm.crewId) fail("failed-precondition", "already-in-crew");
        if (!lt.crewId) fail("failed-precondition", "crew-gone");
        const crew = await c.doc<CrewDoc>(P.crew(lt.crewId!));
        if (!crew || crew.status === "ended" || !crew.members.includes(i.creatorUid)) fail("failed-precondition", "crew-gone");
        const cr = crew as CrewDoc;
        if (cr.members.length >= CREW_MAX) fail("failed-precondition", "crew-full");
        await requireOwnPlainCreature(c, mine, t, false);
        const house = await c.doc<HouseDoc>(P.crewHouse(cr.id));
        const next: CrewDoc = {
          ...cr, members: [...cr.members, uid], donors: { ...cr.donors, [uid]: myCreatureId },
          status: cr.members.length + 1 >= CREW_MIN ? "active" : "forming",
        };
        next.mascotId = await rebuildMascot(c, next, t);
        c.set(P.crew(cr.id), next);
        c.set(P.crewHouse(cr.id), { slots: { ...(house?.slots ?? {}), [uid]: emptySlots() }, paintings: house?.paintings ?? [] } satisfies HouseDoc);
        writeLinks(c, { ...lm, crewId: cr.id });
        done();
        return { kind: "crew" as const, crewId: cr.id, status: next.status, mascotId: next.mascotId };
      });
    },

    /** Removes the friendship both ways; ends visits between the two; quietly unlinks their Duo. */
    async removeFriend(uidIn: string | null | undefined, input: { friendUid?: unknown }) {
      const uid = requireUid(uidIn);
      const friendUid = requireString(input?.friendUid, "friendUid", 128);
      return run(async (c) => {
        if (!(await areFriends(c, uid, friendUid))) return { removed: false, visitsEnded: 0, duoUnlinked: false };
        return { removed: true, ...(await removeFriendIn(c, uid, friendUid, now())) };
      });
    },

    // MARK: visits (§10)

    async startVisit(uidIn: string | null | undefined, input: { creatureId?: unknown; hostUid?: unknown; days?: unknown }) {
      const uid = requireUid(uidIn);
      const creatureId = requireString(input?.creatureId, "creatureId");
      const hostUid = requireString(input?.hostUid, "hostUid", 128);
      const days = input?.days;
      if (typeof days !== "number" || !Number.isInteger(days) || days < VISIT_MIN_DAYS || days > VISIT_MAX_DAYS) fail("invalid-argument", "bad-days");
      if (hostUid === uid) fail("invalid-argument", "bad-hostUid");
      return run(async (c) => {
        const t = now();
        await socialPlayer(c, uid);
        const host = await c.player(hostUid);
        if (!host || !bandAtLeast(host.ageBand, "13to15")) fail("failed-precondition", "not-friends");
        await requireFriends(c, uid, hostUid);
        const cr = await loadOwnedCreature(c.tx, creatureId, uid);
        await requireOwnPlainCreature(c, cr, t, false);
        if (stageOf(cr, t) === "egg") fail("failed-precondition", "too-young");
        if ((await hostedBy(c, hostUid)).length >= MAX_GUESTS_PER_HOST) fail("resource-exhausted", "host-full");
        const hostCreatures: CreatureDoc[] = [];
        for (const x of await c.ownedBy(hostUid, 50)) if (!(await c.doc(P.away(x.id)))) hostCreatures.push(x);
        hostCreatures.sort((a, b) => a.createdAt - b.createdAt || (a.id < b.id ? -1 : 1));
        const visit: VisitDoc = {
          id: "v_" + randomToken().replace(/-/g, "").slice(0, 20),
          visitorCreatureId: creatureId, ownerUid: uid, hostUid, hostCreatureId: hostCreatures[0]?.id ?? null,
          start: t, end: t + (days as number) * DAY_MS, status: "active", diary: null, souvenirId: null,
        };
        if (await c.doc(P.visit(visit.id))) fail("internal", "visit-id-collision");
        c.set(P.away(cr.id), { creatureId: cr.id, hostUid, visitId: visit.id } satisfies AwayDoc);
        c.set(P.visit(visit.id), visit);
        return { visit };
      });
    },

    /** Owner calls the creature home at any time. */
    async recallVisit(uidIn: string | null | undefined, input: { visitId?: unknown }) {
      const uid = requireUid(uidIn);
      const visitId = requireString(input?.visitId, "visitId");
      return run(async (c) => {
        const v = await c.doc<VisitDoc>(P.visit(visitId));
        if (!v || v.ownerUid !== uid) fail("not-found", "visit-not-found");
        if ((v as VisitDoc).status !== "active") fail("failed-precondition", "visit-returned");
        return returnVisit(c, v as VisitDoc, now(), { rewards: true });
      });
    },

    /** Host's read-only view of a visitor (genome shown on the host device; no owner data). */
    async getVisitor(uidIn: string | null | undefined, input: { visitId?: unknown }): Promise<VisitorView> {
      const uid = requireUid(uidIn);
      const visitId = requireString(input?.visitId, "visitId");
      return run(async (c) => {
        const v = await c.doc<VisitDoc>(P.visit(visitId));
        if (!v || v.hostUid !== uid || v.status !== "active") fail("not-found", "visit-not-found");
        const cr = await c.creature((v as VisitDoc).visitorCreatureId);
        if (!cr) fail("not-found", "visit-not-found");
        const x = cr as CreatureDoc;
        return {
          visitId, end: (v as VisitDoc).end, readOnly: true,
          creature: { id: x.id, name: x.name, genome: x.genome, generation: x.generation, comboKey: x.comboKey, paletteShift: x.paletteShift },
        };
      });
    },

    /** Scheduled: returns every visitor whose time is up. */
    async endVisits(): Promise<{ returned: number }> {
      const t = now();
      let returned = 0;
      for (;;) {
        const n = await run(async (c) => {
          const due = await c.query<VisitDoc>(P.visits, [{ field: "status", op: "==", value: "active" }, { field: "end", op: "<=", value: t }], 20, (v) => P.visit(v.id), "end");
          for (const v of due) await returnVisit(c, v, t, { rewards: true });
          return due.length;
        });
        returned += n;
        if (n === 0) break;
      }
      return { returned };
    },

    // MARK: Duo (§11)

    /** Once per LOCAL day per member. Both waved (within 24 h of each other) → dance, counter +1 (never resets). */
    async morningWave(uidIn: string | null | undefined, input: { duoId?: unknown; localDay?: unknown }) {
      const uid = requireUid(uidIn);
      const duoId = requireString(input?.duoId, "duoId");
      return run(async (c) => {
        const t = now();
        const localDay = checkLocalDay(input?.localDay, t);
        const d = await memberDuo(c, uid, duoId);
        const priv = (await c.doc<DuoPrivateDoc>(P.duoPrivate(duoId)))!;
        const waves = priv.waves ?? {};
        const mine = waves[uid] ?? null;
        if (mine && localDay <= mine.day) {
          return { waved: false, alreadyWaved: true, bothWaved: mine.paired, daysBothWaved: d.daysBothWaved };
        }
        const partner = d.members.find((m) => m !== uid)!;
        const theirs = waves[partner] ?? null;
        const pairs = !!theirs && !theirs.paired && t - theirs.at <= WAVE_BACK_WINDOW_MS;
        const nextWaves = { ...waves, [uid]: { day: localDay, at: t, paired: pairs } };
        if (pairs) nextWaves[partner] = { ...theirs!, paired: true };
        const daysBothWaved = d.daysBothWaved + (pairs ? 1 : 0);
        c.set(P.duoPrivate(duoId), { ...priv, waves: nextWaves } satisfies DuoPrivateDoc);
        if (pairs) c.set(P.duo(duoId), { ...d, daysBothWaved } satisfies DuoDoc);
        return { waved: true, alreadyWaved: false, bothWaved: pairs, daysBothWaved };
      });
    },

    /** Member's view of the Duo. Contains nothing about the partner's time, place or activity. */
    async getDuo(uidIn: string | null | undefined, input: { duoId?: unknown }): Promise<DuoView> {
      const uid = requireUid(uidIn);
      const duoId = requireString(input?.duoId, "duoId");
      return run(async (c) => {
        const t = now();
        const d = await memberDuo(c, uid, duoId);
        const priv = await c.doc<DuoPrivateDoc>(P.duoPrivate(duoId));
        const house = (await c.doc<HouseDoc>(P.duoHouse(duoId))) ?? { slots: {}, paintings: [] };
        const notes = await c.query<NoteDoc>(P.duoNotes(duoId), [], 500, (n) => P.duoNote(duoId, n.id));
        const partner = d.members.find((m) => m !== uid)!;
        const w = priv?.waves ?? {};
        const a = duoAnniversaries(d.createdAt, t);
        return {
          id: d.id, framing: d.framing, members: d.members, creatureId: d.creatureId, daysBothWaved: d.daysBothWaved,
          daysTogether: a.daysTogether, anniversaries: a.milestones, nextAnniversary: a.next,
          waveWaiting: !!w[partner] && !w[partner]!.paired && t - w[partner]!.at <= WAVE_BACK_WINDOW_MS,
          house,
          notes: notes.sort((a, b) => a.seq - b.seq).slice(-NOTES_SHOWN).map((n) => ({ id: n.id, mine: n.byUid === uid, emote: n.emote, prop: n.prop })),
        };
      });
    },

    /** Fridge note: one emote + one pixel prop (no free text), max 3 per member per UTC day. */
    async sendFridgeNote(uidIn: string | null | undefined, input: { duoId?: unknown; emote?: unknown; prop?: unknown }) {
      const uid = requireUid(uidIn);
      const duoId = requireString(input?.duoId, "duoId");
      if (typeof input?.emote !== "string" || !NOTE_EMOTES.includes(input.emote)) fail("invalid-argument", "bad-emote");
      if (typeof input?.prop !== "string" || !NOTE_PROPS.includes(input.prop)) fail("invalid-argument", "bad-prop");
      return run(async (c) => {
        const day = utcDay(now());
        await memberDuo(c, uid, duoId);
        const priv = (await c.doc<DuoPrivateDoc>(P.duoPrivate(duoId)))!;
        const cur = priv.notes[uid]?.day === day ? priv.notes[uid].count : 0;
        if (cur >= MAX_NOTES_PER_DAY) fail("resource-exhausted", "note-cap");
        const seq = (priv.noteSeq ?? 0) + 1;
        const id = id64("n_", duoId + "|" + seq);
        c.set(P.duoNote(duoId, id), { id, byUid: uid, emote: input.emote as string, prop: input.prop as string, seq } satisfies NoteDoc);
        c.set(P.duoPrivate(duoId), { ...priv, noteSeq: seq, notes: { ...priv.notes, [uid]: { day, count: cur + 1 } } } satisfies DuoPrivateDoc);
        return { noteId: id, notesLeftToday: MAX_NOTES_PER_DAY - cur - 1 };
      });
    },

    /** Same rule as firestore.rules: a member writes only their own slots, with cosmetics they own (or null). */
    async decorateSlot(uidIn: string | null | undefined, input: { group?: unknown; groupId?: unknown; slot?: unknown; itemId?: unknown }) {
      const uid = requireUid(uidIn);
      const group = input?.group;
      if (group !== "duo" && group !== "crew") fail("invalid-argument", "bad-group");
      const groupId = requireString(input?.groupId, "groupId");
      if (typeof input?.slot !== "string" || !HOUSE_SLOTS.includes(input.slot)) fail("invalid-argument", "bad-slot");
      const itemId = input?.itemId === null ? null : requireString(input?.itemId, "itemId", 64);
      return run(async (c) => {
        const p = await c.mustPlayer(uid);
        if (group === "duo") await memberDuo(c, uid, groupId);
        else await memberCrew(c, uid, groupId);
        if (itemId !== null && !p.cosmetics.includes(itemId)) fail("permission-denied", "item-not-owned");
        const path = group === "duo" ? P.duoHouse(groupId) : P.crewHouse(groupId);
        const house = (await c.doc<HouseDoc>(path)) ?? { slots: {}, paintings: [] };
        const mine = { ...(house.slots[uid] ?? emptySlots()), [input.slot as string]: itemId };
        c.set(path, { ...house, slots: { ...house.slots, [uid]: mine } } satisfies HouseDoc);
        return { slots: mine };
      });
    },

    /** Saves today's shared painting (deterministic seed per group and UTC day; idempotent). */
    async savePainting(uidIn: string | null | undefined, input: { group?: unknown; groupId?: unknown }) {
      const uid = requireUid(uidIn);
      const group = input?.group;
      if (group !== "duo" && group !== "crew") fail("invalid-argument", "bad-group");
      const groupId = requireString(input?.groupId, "groupId");
      return run(async (c) => {
        const day = utcDay(now());
        if (group === "duo") await memberDuo(c, uid, groupId);
        else await memberCrew(c, uid, groupId);
        const path = group === "duo" ? P.duoHouse(groupId) : P.crewHouse(groupId);
        const house = (await c.doc<HouseDoc>(path)) ?? { slots: {}, paintings: [] };
        const id = hex8(fnv1a32("painting|" + groupId + "|" + day));
        const existing = house.paintings.find((p) => p.id === id);
        if (existing) return { painting: existing, fresh: false };
        const painting = { id, seed: fnv1a32("seed|" + groupId + "|" + day), day };
        c.set(path, { ...house, paintings: [...house.paintings, painting].slice(-MAX_PAINTINGS) } satisfies HouseDoc);
        return { painting, fresh: true };
      });
    },

    /** Either member switches "duo" / "bestFriends". Forced to "bestFriends" while any member is under 16. */
    async setDuoFraming(uidIn: string | null | undefined, input: { duoId?: unknown; framing?: unknown }) {
      const uid = requireUid(uidIn);
      const duoId = requireString(input?.duoId, "duoId");
      const wanted = parseFraming(input?.framing);
      if (!wanted) fail("invalid-argument", "bad-framing");
      return run(async (c) => {
        const d = await memberDuo(c, uid, duoId);
        const members = await Promise.all(d.members.map((m) => c.mustPlayer(m)));
        const framing = framingFor(members, wanted!);
        if (framing !== d.framing) c.set(P.duo(duoId), { ...d, framing } satisfies DuoDoc);
        return { framing, forced: framing !== wanted };
      });
    },

    /** One-sided, quiet unlink. Twins one each, items back to their owners, paintings copied, 7-day re-link cooldown. */
    async unlinkDuo(uidIn: string | null | undefined, input: { duoId?: unknown }) {
      const uid = requireUid(uidIn);
      const duoId = requireString(input?.duoId, "duoId");
      return run(async (c) => {
        const d = await memberDuo(c, uid, duoId);
        const r = await unlinkDuoIn(c, d, now(), { twinsFor: d.members });
        return { duoId, myTwinId: r.twins[uid] ?? null, returnedItems: r.returnedItems[uid] ?? [] };
      });
    },

    // MARK: Crew (§12)

    /** Roll call: one emote per member per UTC day. */
    async rollCall(uidIn: string | null | undefined, input: { crewId?: unknown; emote?: unknown }) {
      const uid = requireUid(uidIn);
      const crewId = requireString(input?.crewId, "crewId");
      if (typeof input?.emote !== "string" || !ROLL_CALL_EMOTES.includes(input.emote)) fail("invalid-argument", "bad-emote");
      return run(async (c) => {
        const day = utcDay(now());
        const crew = await memberCrew(c, uid, crewId);
        const emotes = crew.rollCall.day === day ? { ...crew.rollCall.emotes } : {};
        if (emotes[uid]) return { already: true, rollCall: emotes };
        emotes[uid] = input.emote as string;
        c.set(P.crew(crewId), { ...crew, rollCall: { day, emotes } } satisfies CrewDoc);
        return { already: false, rollCall: emotes };
      });
    },

    async getCrew(uidIn: string | null | undefined, input: { crewId?: unknown }): Promise<CrewView> {
      const uid = requireUid(uidIn);
      const crewId = requireString(input?.crewId, "crewId");
      return run(async (c) => {
        const day = utcDay(now());
        const crew = await memberCrew(c, uid, crewId);
        const house = (await c.doc<HouseDoc>(P.crewHouse(crewId))) ?? { slots: {}, paintings: [] };
        return {
          id: crew.id, status: crew.status, members: crew.members, mascotId: crew.mascotId,
          rollCall: crew.rollCall.day === day ? crew.rollCall.emotes : {}, house,
        };
      });
    },

    /** Quiet leave; the leaver keeps a copy of the mascot. */
    async leaveCrew(uidIn: string | null | undefined, input: { crewId?: unknown }) {
      const uid = requireUid(uidIn);
      const crewId = requireString(input?.crewId, "crewId");
      return run(async (c) => leaveCrewIn(c, await memberCrew(c, uid, crewId), uid, now(), { keepCopy: true }));
    },

    // MARK: pokes (§13)

    async sendPoke(uidIn: string | null | undefined, input: { toUid?: unknown; emote?: unknown }) {
      const uid = requireUid(uidIn);
      const toUid = requireString(input?.toUid, "toUid", 128);
      if (typeof input?.emote !== "string" || !POKE_EMOTES.includes(input.emote)) fail("invalid-argument", "bad-emote");
      return run(async (c) => {
        const day = utcDay(now());
        const p = await socialPlayer(c, uid);
        await requireFriends(c, uid, toUid);
        const lim = socialLimits(p, day);
        if (lim.pokes >= MAX_POKES_PER_DAY) fail("resource-exhausted", "poke-cap");
        lim.pokes += 1;
        const id = id64("pk_", uid + "|" + day + "|" + lim.pokes);
        c.setPlayer({ ...p, social: lim });
        c.set(P.poke(id), { id, toUid, fromUid: uid, emote: input.emote as string } satisfies PokeDoc);
        return { pokeId: id, pokesLeftToday: MAX_POKES_PER_DAY - lim.pokes };
      });
    },

    /** Account deletion: removes the player from the social graph. Called by deleteAccount before creatures go. */
    async purgeAccount(uid: string) {
      const t = now();
      // 1. Duo / crew / visits as host (each in its own transaction to stay small).
      await run(async (c) => {
        const l = await links(c, uid);
        const duo = l.duoId ? await c.doc<DuoDoc>(P.duo(l.duoId)) : null;
        const crew = l.crewId ? await c.doc<CrewDoc>(P.crew(l.crewId)) : null;
        if (duo && duo.status === "active") await unlinkDuoIn(c, duo, t, { twinsFor: duo.members.filter((m) => m !== uid) });
        if (crew && crew.status !== "ended" && crew.members.includes(uid)) await leaveCrewIn(c, crew, uid, t, { keepCopy: false });
        if (!duo && !crew && (l.duoId || l.crewId)) c.del(P.links(uid));
      });
      await run(async (c) => {
        for (const v of await hostedBy(c, uid)) await returnVisit(c, v, t, { rewards: false });
      });
      // 2. Friend edges, own visits, invites, pokes, bonds, gallery: chunked deletes.
      const chunks: [string, Parameters<Tx["queryDocs"]>[1], (d: any) => string[]][] = [
        [P.friends(uid), [], (f: FriendDoc) => [P.friend(uid, f.friendUid), P.friend(f.friendUid, uid)]],
        [P.visits, [{ field: "ownerUid", op: "==", value: uid }], (v: VisitDoc) => [P.visit(v.id), P.away(v.visitorCreatureId)]],
        [P.visits, [{ field: "hostUid", op: "==", value: uid }], (v: VisitDoc) => [P.visit(v.id)]],
        [P.invites, [{ field: "creatorUid", op: "==", value: uid }], (i: InviteDoc) => [P.invite(i.code)]],
        [P.invites, [{ field: "usedBy", op: "==", value: uid }], (i: InviteDoc) => [P.invite(i.code)]],
        // Ended duos (active ones were unlinked above; their house / notes / private docs are already gone).
        ["duos", [{ field: "members", op: "array-contains", value: uid }], (d: DuoDoc) => [P.duo(d.id)]],
        [P.pokes, [{ field: "fromUid", op: "==", value: uid }], (p: PokeDoc) => [P.poke(p.id)]],
        [P.pokes, [{ field: "toUid", op: "==", value: uid }], (p: PokeDoc) => [P.poke(p.id)]],
        [P.bonds, [{ field: "ownerUids", op: "array-contains", value: uid }], (b: BondDoc) => [P.bond(b.id)]],
        [P.galleryItems(uid), [], (g: GalleryDoc) => [P.gallery(uid, g.id)]],
      ];
      for (const [coll, where, paths] of chunks) {
        for (;;) {
          const n = await repo.runTransaction(async (tx) => {
            const docs = await tx.queryDocs<any>(coll, where, BULK_CHUNK);
            docs.flatMap(paths).forEach((p) => tx.deleteDoc(p));
            return docs.length;
          });
          if (n === 0) break;
        }
      }
    },
  };
}

export type SocialServices = ReturnType<typeof createSocialServices>;
