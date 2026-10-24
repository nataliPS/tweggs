import { test } from "node:test";
import assert from "node:assert/strict";
import { fnv1a32, mulberry32 } from "../../engine-ts/src/index.ts";
import {
  CREW_MAX, DAY_MS, DUO_RELINK_COOLDOWN_MS, HOUR_MS, INVITE_TTL_MS, MAX_NOTES_PER_DAY, MAX_POKES_PER_DAY, P,
  UNNAMED_CREATURE, creatureSigPayload, duoAnniversaries, geneRelay, utcDay, verifySig,
  type BondDoc, type CreatureDoc, type CrewDoc, type DuoDoc, type GalleryDoc, type HouseDoc, type PlayerDoc, type VisitDoc,
} from "../src/index.ts";
import { T0, friends, rejects, setup, type Env } from "./helpers.ts";

const SECRET = "test-secret-0123456789";

async function befriend(env: Env, a: string, b: string) {
  const { code } = await env.svc.createInvite(a, { kind: "friend" });
  return env.svc.acceptInvite(b, { code });
}

async function makeDuo(env: Env, a: string, b: string, cs: Record<string, CreatureDoc[]>) {
  await befriend(env, a, b);
  const { code } = await env.svc.createInvite(a, { kind: "duo", creatureId: cs[a][0].id });
  const r = await env.svc.acceptInvite(b, { code, creatureId: cs[b][0].id });
  assert.equal(r.kind, "duo");
  return r as { kind: "duo"; duoId: string; creatureId: string };
}

async function makeCrew(env: Env, uids: string[], cs: Record<string, CreatureDoc[]>) {
  const [lead, ...rest] = uids;
  let crewId = "";
  for (const u of rest) {
    await befriend(env, lead, u);
    const { code } = await env.svc.createInvite(lead, { kind: "crew", creatureId: cs[lead][0].id });
    const r = (await env.svc.acceptInvite(u, { code, creatureId: cs[u][0].id })) as { crewId: string };
    crewId = r.crewId;
  }
  return crewId;
}

const giveCosmetic = (env: Env, uid: string, id: string) => {
  const p = env.repo.get<PlayerDoc>("players", uid)!;
  env.repo.put("players", uid, { ...p, cosmetics: [...p.cosmetics, id] });
};

/** Keys that would leak another user's whereabouts, presence or activity (§11 RED LINES). */
const FORBIDDEN = /location|lat|lng|geo|weather|timezone|timeZone|tz|localDay|lastSeen|online|presence|status_?text|activity|opened|lastActive|readAt|seen|receipt|steps|wake|alarm|score|ownerUid|displayName|wavedAt|^at$|lastWave/i;

function forbiddenKeys(v: unknown, path = ""): string[] {
  if (Array.isArray(v)) return v.flatMap((x, i) => forbiddenKeys(x, `${path}[${i}]`));
  if (v !== null && typeof v === "object") {
    return Object.entries(v).flatMap(([k, x]) => [...(FORBIDDEN.test(k) ? [path + "." + k] : []), ...forbiddenKeys(x, path + "." + k)]);
  }
  return [];
}

// MARK: invites + friendships

test("friend invite: single use, 24h expiry, mutual edges", async () => {
  const env = setup();
  await friends(env, "a", "b", "c");
  const inv = await env.svc.createInvite("a", { kind: "friend" });
  assert.equal(inv.expiresAt - T0 - 8 * DAY_MS, INVITE_TTL_MS);
  await rejects(env.svc.acceptInvite("a", { code: inv.code }), "own-invite");
  const r = await env.svc.acceptInvite("b", { code: inv.code });
  assert.deepEqual(r, { kind: "friend", friendUid: "a", alreadyFriends: false });
  assert.ok(env.repo.doc(P.friend("a", "b")));
  assert.ok(env.repo.doc(P.friend("b", "a")));
  await rejects(env.svc.acceptInvite("c", { code: inv.code }), "invite-used");
  const late = await env.svc.createInvite("a", { kind: "friend" });
  env.advance(INVITE_TTL_MS);
  await rejects(env.svc.acceptInvite("c", { code: late.code }), "invite-expired");
  await rejects(env.svc.acceptInvite("c", { code: "nope" }), "invite-not-found");
  await rejects(env.svc.createInvite("a", { kind: "enemy" }), "bad-kind");
});

test("under-13: no invites, no accepting, no visits, no pokes", async () => {
  const env = setup();
  const kid = (await env.svc.registerPlayer("kid", { ageBand: "under13" })).starters;
  await friends(env, "a");
  await rejects(env.svc.createInvite("kid", { kind: "friend" }), "age-restricted");
  const { code } = await env.svc.createInvite("a", { kind: "friend" });
  await rejects(env.svc.acceptInvite("kid", { code }), "age-restricted");
  await rejects(env.svc.startVisit("kid", { creatureId: kid[0].id, hostUid: "a", days: 1 }), "age-restricted");
  await rejects(env.svc.sendPoke("kid", { toUid: "a", emote: "wave" }), "age-restricted");
  assert.equal(env.repo.docsUnder("friends/").length, 0);
});

test("blocked users cannot befriend, poke or visit (block is not revealed)", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b");
  await befriend(env, "a", "b");
  env.repo.docs.set(P.block("b", "a"), { reason: "spam", target: "a" });
  await rejects(env.svc.sendPoke("a", { toUid: "b", emote: "wave" }), "not-friends");
  await rejects(env.svc.startVisit("a", { creatureId: cs.a[0].id, hostUid: "b", days: 1 }), "not-friends");
  const { code } = await env.svc.createInvite("a", { kind: "friend" });
  await rejects(env.svc.acceptInvite("b", { code }), "not-friends");
});

test("removeFriend: both edges go, visits end both ways, duo unlinks quietly", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b");
  const { duoId } = await makeDuo(env, "a", "b", cs);
  const v1 = (await env.svc.startVisit("a", { creatureId: cs.a[1].id, hostUid: "b", days: 2 })).visit;
  const v2 = (await env.svc.startVisit("b", { creatureId: cs.b[1].id, hostUid: "a", days: 2 })).visit;
  const r = await env.svc.removeFriend("b", { friendUid: "a" });
  assert.deepEqual(r, { removed: true, visitsEnded: 2, duoUnlinked: true });
  assert.equal(env.repo.doc(P.friend("a", "b")), undefined);
  assert.equal(env.repo.doc(P.friend("b", "a")), undefined);
  for (const v of [v1, v2]) assert.equal(env.repo.doc<VisitDoc>(P.visit(v.id))!.status, "returned");
  const duo = env.repo.doc<DuoDoc>(P.duo(duoId))!;
  assert.equal(duo.status, "ended");
  assert.ok(!JSON.stringify(duo).match(/endedBy|leftBy|reason|"b"\s*left/));
  assert.deepEqual(await env.svc.removeFriend("b", { friendUid: "a" }), { removed: false, visitsEnded: 0, duoUnlinked: false });
  await rejects(env.svc.sendPoke("a", { toUid: "b", emote: "wave" }), "not-friends");
});

// MARK: visits

test("startVisit: friends only, 1–3 days, not twice at once; host reads the visitor read-only", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b", "c");
  await rejects(env.svc.startVisit("a", { creatureId: cs.a[0].id, hostUid: "b", days: 1 }), "not-friends");
  await befriend(env, "a", "b");
  await rejects(env.svc.startVisit("a", { creatureId: cs.a[0].id, hostUid: "b", days: 0 }), "bad-days");
  await rejects(env.svc.startVisit("a", { creatureId: cs.a[0].id, hostUid: "b", days: 4 }), "bad-days");
  await rejects(env.svc.startVisit("a", { creatureId: cs.b[0].id, hostUid: "b", days: 1 }), "not-owner");
  const { visit } = await env.svc.startVisit("a", { creatureId: cs.a[0].id, hostUid: "b", days: 3 });
  assert.equal(visit.end - visit.start, 3 * DAY_MS);
  assert.ok(cs.b.some((c) => c.id === visit.hostCreatureId));
  await rejects(env.svc.startVisit("a", { creatureId: cs.a[0].id, hostUid: "b", days: 1 }), "creature-away");

  const view = await env.svc.getVisitor("b", { visitId: visit.id });
  assert.equal(view.readOnly, true);
  assert.deepEqual(view.creature.genome, cs.a[0].genome);
  assert.deepEqual(forbiddenKeys(view), []);
  await rejects(env.svc.getVisitor("c", { visitId: visit.id }), "visit-not-found");
  // Host cannot keep, rename, offer or duo the visitor.
  await rejects(env.svc.renameCreature("b", { id: cs.a[0].id, name: "Mine" }), "not-owner");
  await rejects(env.svc.createOffer("b", { parentCreatureId: cs.a[0].id }), "not-owner");
  assert.equal(env.repo.get<CreatureDoc>("creatures", cs.a[0].id)!.ownerUid, "a");
  // The visiting creature doc itself is unchanged (away state is a server-only marker).
  assert.deepEqual(env.repo.get<CreatureDoc>("creatures", cs.a[0].id), cs.a[0]);
  assert.ok(env.repo.doc(P.away(cs.a[0].id)));
});

test("recallVisit: owner anytime; diary has creature names only; souvenir; bond rises", async () => {
  const env = setup();
  const cs = await friends(env, "alice", "bob");
  await env.svc.registerPlayer("alice", { ageBand: "18plus" });
  await env.svc.renameCreature("alice", { id: cs.alice[0].id, name: "Lilo" });
  await env.svc.renameCreature("bob", { id: cs.bob[0].id, name: "Zephyr" });
  await befriend(env, "alice", "bob");
  const { visit } = await env.svc.startVisit("alice", { creatureId: cs.alice[0].id, hostUid: "bob", days: 3 });
  await rejects(env.svc.recallVisit("bob", { visitId: visit.id }), "visit-not-found");
  env.advance(30 * HOUR_MS);
  const r = await env.svc.recallVisit("alice", { visitId: visit.id });
  assert.equal(r.diary.title, "My visit to Zephyr");
  assert.ok(r.diary.lines.length >= 2);
  assert.ok(r.diary.lines.some((l) => l.includes("Lilo")));
  const text = JSON.stringify(r.diary);
  for (const bad of ["alice", "bob", "Alice", "Bob"]) assert.ok(!text.includes(bad), bad);
  assert.match(r.souvenirId!, /^souvenir_/);
  assert.ok(env.repo.get<PlayerDoc>("players", "alice")!.cosmetics.includes(r.souvenirId!));
  assert.equal(r.bondLevel, 1);
  const bond = env.repo.docsUnder<BondDoc>("bonds/")[0];
  assert.deepEqual(bond.creatureIds, [cs.alice[0].id, cs.bob[0].id].sort());
  assert.equal(env.repo.doc(P.away(cs.alice[0].id)), undefined);
  const stored = env.repo.doc<VisitDoc>(P.visit(visit.id))!;
  assert.equal(stored.status, "returned");
  assert.ok(!("returnedAt" in stored), "host must not learn when the owner recalled");
  await rejects(env.svc.recallVisit("alice", { visitId: visit.id }), "visit-returned");
  // Same visit id -> same diary and souvenir (deterministic templates).
  const { visitDiary, visitSouvenir } = await import("../src/index.ts");
  assert.deepEqual(visitDiary(visit.id, "Lilo", "Zephyr", 30), r.diary);
  assert.equal(visitSouvenir(visit.id), r.souvenirId);
});

test("endVisits returns due visitors only; second visit raises the bond and suggests breeding", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b");
  await befriend(env, "a", "b");
  const short = (await env.svc.startVisit("a", { creatureId: cs.a[0].id, hostUid: "b", days: 1 })).visit;
  const long = (await env.svc.startVisit("a", { creatureId: cs.a[1].id, hostUid: "b", days: 3 })).visit;
  env.advance(DAY_MS);
  assert.deepEqual(await env.svc.endVisits(), { returned: 1 });
  assert.equal(env.repo.doc<VisitDoc>(P.visit(short.id))!.status, "returned");
  assert.equal(env.repo.doc<VisitDoc>(P.visit(long.id))!.status, "active");
  const again = (await env.svc.startVisit("a", { creatureId: cs.a[0].id, hostUid: "b", days: 1 })).visit;
  env.advance(2 * DAY_MS);
  assert.deepEqual(await env.svc.endVisits(), { returned: 2 });
  assert.deepEqual(await env.svc.endVisits(), { returned: 0 });
  const bond = env.repo.doc<BondDoc>(P.bond((await import("../src/index.ts")).bondId(cs.a[0].id, again.hostCreatureId!)))!;
  assert.equal(bond.level, 2);
  assert.equal(bond.visits, 2);
  assert.equal(env.repo.doc<VisitDoc>(P.visit(again.id))!.diary!.title.startsWith("My visit to"), true);
  // Title uses the host CREATURE's name (starter names), never a player name.
  assert.match(env.repo.doc<VisitDoc>(P.visit(again.id))!.diary!.title, /^My visit to (Mixy|Pip)$/);
  // Unnamed creature -> generic fallback.
  const { visitDiary } = await import("../src/index.ts");
  assert.ok(visitDiary("v", UNNAMED_CREATURE, null, 5).lines.join(" ").includes(UNNAMED_CREATURE));
});

test("a host takes at most 3 guests", async () => {
  const env = setup();
  const cs = await friends(env, "h", "a", "b");
  await befriend(env, "h", "a");
  await befriend(env, "h", "b");
  await env.svc.startVisit("a", { creatureId: cs.a[0].id, hostUid: "h", days: 1 });
  await env.svc.startVisit("a", { creatureId: cs.a[1].id, hostUid: "h", days: 1 });
  await env.svc.startVisit("b", { creatureId: cs.b[0].id, hostUid: "h", days: 1 });
  await rejects(env.svc.startVisit("b", { creatureId: cs.b[1].id, hostUid: "h", days: 1 }), "host-full");
});

// MARK: Duo

test("duo: friends only, 13+ only, nobody in two duos", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b", "c");
  const kid = (await env.svc.registerPlayer("kid", { ageBand: "under13" })).starters;
  env.days(8);
  const inv = await env.svc.createInvite("a", { kind: "duo", creatureId: cs.a[0].id });
  await rejects(env.svc.acceptInvite("b", { code: inv.code, creatureId: cs.b[0].id }), "not-friends");
  await rejects(env.svc.createInvite("kid", { kind: "duo", creatureId: kid[0].id }), "age-restricted");
  await rejects(env.svc.createInvite("a", { kind: "duo", creatureId: cs.a[0].id, framing: "couple" }), "bad-framing");

  await makeDuo(env, "a", "b", cs);
  await befriend(env, "a", "c");
  await rejects(env.svc.createInvite("a", { kind: "duo", creatureId: cs.a[1].id }), "already-in-duo");
  const inv3 = await env.svc.createInvite("c", { kind: "duo", creatureId: cs.c[0].id });
  await rejects(env.svc.acceptInvite("a", { code: inv3.code, creatureId: cs.a[1].id }), "already-in-duo");
});

async function bandedDuo(bandA: string, bandB: string, framing?: string) {
  const env = setup();
  const cs: Record<string, CreatureDoc[]> = {};
  cs.a = (await env.svc.registerPlayer("a", { ageBand: bandA })).starters;
  cs.b = (await env.svc.registerPlayer("b", { ageBand: bandB })).starters;
  env.days(8);
  await befriend(env, "a", "b");
  const { code } = await env.svc.createInvite("a", { kind: "duo", creatureId: cs.a[0].id, framing });
  const r = (await env.svc.acceptInvite("b", { code, creatureId: cs.b[0].id })) as { duoId: string };
  return { env, duoId: r.duoId, framing: env.repo.doc<DuoDoc>(P.duo(r.duoId))!.framing };
}

test("duo framing: forced bestFriends if any member is under 16; otherwise member-chosen (default duo)", async () => {
  assert.equal((await bandedDuo("13to15", "13to15")).framing, "bestFriends");
  assert.equal((await bandedDuo("13to15", "18plus", "duo")).framing, "bestFriends");
  assert.equal((await bandedDuo("16to17", "18plus")).framing, "duo");
  assert.equal((await bandedDuo("16to17", "16to17", "bestFriends")).framing, "bestFriends");
  // Legacy "13to17" is treated as 13to15 (conservative).
  assert.equal((await bandedDuo("13to17", "18plus")).framing, "bestFriends");

  const adults = await bandedDuo("18plus", "18plus");
  assert.deepEqual(await adults.env.svc.setDuoFraming("b", { duoId: adults.duoId, framing: "bestFriends" }), { framing: "bestFriends", forced: false });
  assert.equal((await adults.env.svc.getDuo("a", { duoId: adults.duoId })).framing, "bestFriends");
  await rejects(adults.env.svc.setDuoFraming("a", { duoId: adults.duoId, framing: "romantic" }), "bad-framing");
  const teen = await bandedDuo("13to15", "18plus");
  assert.deepEqual(await teen.env.svc.setDuoFraming("b", { duoId: teen.duoId, framing: "duo" }), { framing: "bestFriends", forced: true });
  assert.equal(teen.env.repo.doc<DuoDoc>(P.duo(teen.duoId))!.framing, "bestFriends");
  // Read models never carry age bands.
  assert.ok(!JSON.stringify(await teen.env.svc.getDuo("b", { duoId: teen.duoId })).match(/ageBand|13to15|18plus/));
});

test("age bands: new split accepted; legacy 13to17 stored as 13to15; social works 13+", async () => {
  const env = setup();
  for (const b of ["under13", "13to15", "16to17", "18plus"]) {
    assert.equal((await env.svc.registerPlayer("u" + b, { ageBand: b })).player.ageBand, b);
  }
  assert.equal((await env.svc.registerPlayer("old", { ageBand: "13to17" })).player.ageBand, "13to15");
  // A doc stored before the split still gets 13+ social and is never "16+".
  const p = env.repo.get<PlayerDoc>("players", "old")!;
  env.repo.put("players", "old", { ...p, ageBand: "13to17" });
  await env.svc.createInvite("old", { kind: "friend" });
  const { bandAtLeast } = await import("../src/index.ts");
  assert.equal(bandAtLeast("13to17", "16to17"), false);
  assert.equal(bandAtLeast("bogus", "13to15"), false);
  await rejects(env.svc.createInvite("uunder13", { kind: "friend" }), "age-restricted");
});

test("duo creature: co-owned, signed, bred from one parent each; members read it", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b");
  const { duoId, creatureId } = await makeDuo(env, "a", "b", cs);
  const d = env.repo.doc<DuoDoc>(P.duo(duoId))!;
  assert.deepEqual(d.members, ["a", "b"]);
  assert.equal(d.framing, "duo");
  const cr = env.repo.get<CreatureDoc>("creatures", creatureId)!;
  assert.equal(cr.ownerUid, "duo:" + duoId);
  assert.deepEqual(cr.coOwnerUids, ["a", "b"]);
  assert.deepEqual(cr.parentIds, [cs.a[0].id, cs.b[0].id].sort());
  assert.equal(cr.origin, "duo");
  assert.ok(verifySig(SECRET, creatureSigPayload(cr), cr.sig));
  assert.ok(env.repo.doc(P.links("a")) && env.repo.doc(P.links("b")));
  // Not part of either member's own collection (no shared upkeep).
  await rejects(env.svc.renameCreature("a", { id: creatureId, name: "Ours" }), "not-owner");
});

test("morningWave: once per local day; both waved -> counter; counter never resets", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b");
  const { duoId } = await makeDuo(env, "a", "b", cs);
  const day = () => utcDay(env.clock.t);
  await rejects(env.svc.morningWave("a", { duoId, localDay: "2020-01-01" }), "bad-localDay");
  await rejects(env.svc.morningWave("c", { duoId, localDay: day() }), "duo-not-found");
  let r = await env.svc.morningWave("a", { duoId, localDay: day() });
  assert.deepEqual(r, { waved: true, alreadyWaved: false, bothWaved: false, daysBothWaved: 0 });
  assert.equal((await env.svc.getDuo("b", { duoId })).waveWaiting, true);
  r = await env.svc.morningWave("a", { duoId, localDay: day() });
  assert.equal(r.alreadyWaved, true);
  r = await env.svc.morningWave("b", { duoId, localDay: day() });
  assert.deepEqual(r, { waved: true, alreadyWaved: false, bothWaved: true, daysBothWaved: 1 });
  assert.equal((await env.svc.getDuo("a", { duoId })).waveWaiting, false);
  // Only one partner waves for a few days: nothing is lost.
  for (let i = 0; i < 4; i++) {
    env.days(1);
    await env.svc.morningWave("a", { duoId, localDay: day() });
  }
  assert.equal(env.repo.doc<DuoDoc>(P.duo(duoId))!.daysBothWaved, 1);
  await env.svc.morningWave("b", { duoId, localDay: day() });
  env.days(1);
  await env.svc.morningWave("b", { duoId, localDay: day() });
  await env.svc.morningWave("a", { duoId, localDay: day() });
  assert.equal(env.repo.doc<DuoDoc>(P.duo(duoId))!.daysBothWaved, 3);
});

test("anniversaries 7/30/100/365 are computed from the link day", async () => {
  const t = T0;
  assert.deepEqual(duoAnniversaries(t, t).next, 7);
  const a7 = duoAnniversaries(t, t + 7 * DAY_MS + HOUR_MS);
  assert.equal(a7.daysTogether, 7);
  assert.deepEqual(a7.milestones.map((m) => [m.day, m.reached, m.today]), [[7, true, true], [30, false, false], [100, false, false], [365, false, false]]);
  assert.equal(a7.next, 30);
  const y = duoAnniversaries(t, t + 400 * DAY_MS);
  assert.ok(y.milestones.every((m) => m.reached && !m.today));
  assert.equal(y.next, null);
  const env = setup();
  const cs = await friends(env, "a", "b");
  const { duoId } = await makeDuo(env, "a", "b", cs);
  env.days(30);
  const v = await env.svc.getDuo("a", { duoId });
  assert.equal(v.daysTogether, 30);
  assert.equal(v.anniversaries.find((m) => m.day === 30)!.today, true);
});

test("fridge notes: emote + prop only, max 3/day per member", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b");
  const { duoId } = await makeDuo(env, "a", "b", cs);
  await rejects(env.svc.sendFridgeNote("a", { duoId, emote: "I miss you", prop: "cake" }), "bad-emote");
  await rejects(env.svc.sendFridgeNote("a", { duoId, emote: "heart", prop: "https://x" }), "bad-prop");
  for (let i = 0; i < MAX_NOTES_PER_DAY; i++) await env.svc.sendFridgeNote("a", { duoId, emote: "heart", prop: "cake" });
  await rejects(env.svc.sendFridgeNote("a", { duoId, emote: "heart", prop: "cake" }), "note-cap");
  await env.svc.sendFridgeNote("b", { duoId, emote: "sun", prop: "tea" });
  env.days(1);
  await env.svc.sendFridgeNote("a", { duoId, emote: "star", prop: "gift" });
  const v = await env.svc.getDuo("b", { duoId });
  assert.equal(v.notes.length, 5);
  assert.deepEqual(v.notes.at(-1), { id: v.notes.at(-1)!.id, mine: false, emote: "star", prop: "gift" });
  for (const n of env.repo.docsUnder<object>(`duos/${duoId}/notes/`)) assert.deepEqual(Object.keys(n).sort(), ["byUid", "emote", "id", "prop", "seq"]);
});

test("house: each member writes only own slots with owned cosmetics", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b", "c");
  const { duoId } = await makeDuo(env, "a", "b", cs);
  await rejects(env.svc.decorateSlot("a", { group: "duo", groupId: duoId, slot: "s1", itemId: "lamp" }), "item-not-owned");
  giveCosmetic(env, "a", "lamp");
  await env.svc.decorateSlot("a", { group: "duo", groupId: duoId, slot: "s1", itemId: "lamp" });
  await rejects(env.svc.decorateSlot("a", { group: "duo", groupId: duoId, slot: "s9", itemId: "lamp" }), "bad-slot");
  await rejects(env.svc.decorateSlot("c", { group: "duo", groupId: duoId, slot: "s1", itemId: null }), "duo-not-found");
  const h = env.repo.doc<HouseDoc>(P.duoHouse(duoId))!;
  assert.equal(h.slots.a.s1, "lamp");
  assert.equal(h.slots.b.s1, null);
});

test("unlinkDuo: one-sided, quiet; twins one each; items back; paintings copied; 7-day re-link cooldown", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b");
  const { duoId, creatureId } = await makeDuo(env, "a", "b", cs);
  giveCosmetic(env, "b", "rug");
  await env.svc.decorateSlot("b", { group: "duo", groupId: duoId, slot: "s2", itemId: "rug" });
  const { painting } = await env.svc.savePainting("a", { group: "duo", groupId: duoId });
  assert.equal((await env.svc.savePainting("b", { group: "duo", groupId: duoId })).fresh, false);
  const duoCr = env.repo.get<CreatureDoc>("creatures", creatureId)!;

  const r = await env.svc.unlinkDuo("a", { duoId });
  assert.ok(r.myTwinId);
  assert.equal(env.repo.get("creatures", creatureId), undefined);
  const twins = env.repo.all<CreatureDoc>("creatures").filter((c) => c.origin === "duo");
  assert.deepEqual(twins.map((t) => t.ownerUid).sort(), ["a", "b"]);
  for (const t of twins) {
    assert.deepEqual(t.genome, duoCr.genome);
    assert.equal(t.coOwnerUids, undefined);
    assert.ok(verifySig(SECRET, creatureSigPayload(t), t.sig));
  }
  assert.ok(env.repo.get<PlayerDoc>("players", "b")!.cosmetics.includes("rug"));
  for (const u of ["a", "b"]) {
    const g = env.repo.docsUnder<GalleryDoc>(`gallery/${u}/items/`);
    assert.ok(g.some((x) => x.kind === "painting" && x.seed === painting.seed));
    assert.ok(g.some((x) => x.kind === "house-memory"));
  }
  assert.deepEqual(forbiddenKeys(env.repo.docsUnder("gallery/")), []);
  assert.ok(!JSON.stringify(env.repo.docsUnder("gallery/")).match(/"a"|"b"/));
  const ended = env.repo.doc<DuoDoc>(P.duo(duoId))!;
  assert.equal(ended.status, "ended");
  assert.deepEqual(Object.keys(ended).sort(), ["createdAt", "creatureId", "daysBothWaved", "framing", "id", "members", "status"]);
  assert.equal(env.repo.doc(P.links("b")), undefined);
  assert.equal(env.repo.doc(P.duoPrivate(duoId)), undefined);
  await rejects(env.svc.morningWave("b", { duoId, localDay: utcDay(env.clock.t) }), "duo-ended");

  // Friends remain; re-link with the same person blocked for 7 days; another person is fine.
  assert.ok(env.repo.doc(P.friend("a", "b")));
  const again = await env.svc.createInvite("b", { kind: "duo", creatureId: cs.b[1].id });
  await rejects(env.svc.acceptInvite("a", { code: again.code, creatureId: cs.a[1].id }), "relink-cooldown");
  env.advance(DUO_RELINK_COOLDOWN_MS);
  const later = await env.svc.createInvite("b", { kind: "duo", creatureId: cs.b[1].id });
  assert.equal((await env.svc.acceptInvite("a", { code: later.code, creatureId: cs.a[1].id })).kind, "duo");
});

// MARK: Crew

test("geneRelay is deterministic and every donor gives a gene", () => {
  const donors = ["x", "y", "z", "w"].map((id, i) => ({ id, genome: Array.from({ length: 8 }, (_, g) => [i, (g + i) % 3] as [number, number]) }));
  const g1 = geneRelay("crew1", donors);
  assert.deepEqual(geneRelay("crew1", donors), g1);
  const start = mulberry32(fnv1a32("mascot|crew1|x,y,z,w")).int(4);
  g1.forEach((pair, g) => assert.deepEqual(pair, donors[(start + g) % 4].genome[g]));
  assert.equal(new Set(g1.map((p) => p[0])).size, 4);
});

test("crew: forms at 3, max 5, roll call, mascot via gene relay", async () => {
  const env = setup();
  const cs = await friends(env, "l", "m1", "m2", "m3", "m4", "m5");
  await befriend(env, "l", "m1");
  const { code } = await env.svc.createInvite("l", { kind: "crew", creatureId: cs.l[0].id });
  const r1 = (await env.svc.acceptInvite("m1", { code, creatureId: cs.m1[0].id })) as { crewId: string; status: string; mascotId: string | null };
  assert.equal(r1.status, "forming");
  assert.equal(r1.mascotId, null);
  const crewId = await makeCrew(env, ["l", "m2"], cs);
  assert.equal(crewId, r1.crewId);
  const crew = env.repo.doc<CrewDoc>(P.crew(crewId))!;
  assert.equal(crew.status, "active");
  const mascot = env.repo.get<CreatureDoc>("creatures", crew.mascotId!)!;
  assert.equal(mascot.origin, "mascot");
  assert.deepEqual(mascot.genome, geneRelay(crewId, ["l", "m1", "m2"].map((u) => ({ id: cs[u][0].id, genome: cs[u][0].genome }))));
  await makeCrew(env, ["l", "m3", "m4"], cs);
  assert.equal(env.repo.doc<CrewDoc>(P.crew(crewId))!.members.length, CREW_MAX);
  await rejects(env.svc.createInvite("l", { kind: "crew", creatureId: cs.l[0].id }), "crew-full");

  await env.svc.rollCall("m1", { crewId, emote: "salute" });
  assert.equal((await env.svc.rollCall("m1", { crewId, emote: "dance" })).already, true);
  await rejects(env.svc.rollCall("m5", { crewId, emote: "wave" }), "crew-not-found");
  await rejects(env.svc.rollCall("m2", { crewId, emote: "hello there" }), "bad-emote");
  const v = await env.svc.getCrew("l", { crewId });
  assert.deepEqual(v.rollCall, { m1: "salute" });
  env.days(1);
  assert.deepEqual((await env.svc.getCrew("l", { crewId })).rollCall, {});
});

test("leaveCrew: quiet; leaver keeps a mascot copy; crew keeps going", async () => {
  const env = setup();
  const cs = await friends(env, "l", "a", "b", "c");
  const crewId = await makeCrew(env, ["l", "a", "b", "c"], cs);
  const mascotId = env.repo.doc<CrewDoc>(P.crew(crewId))!.mascotId!;
  const mascot = env.repo.get<CreatureDoc>("creatures", mascotId)!;
  const r = await env.svc.leaveCrew("c", { crewId });
  const copy = env.repo.get<CreatureDoc>("creatures", r.mascotCopyId!)!;
  assert.equal(copy.ownerUid, "c");
  assert.deepEqual(copy.genome, mascot.genome);
  assert.ok(verifySig(SECRET, creatureSigPayload(copy), copy.sig));
  const crew = env.repo.doc<CrewDoc>(P.crew(crewId))!;
  assert.deepEqual(crew.members, ["l", "a", "b"]);
  assert.equal(crew.status, "active");
  assert.ok(!JSON.stringify(crew).includes('"c"'));
  assert.deepEqual(env.repo.get<CreatureDoc>("creatures", mascotId)!.coOwnerUids, ["l", "a", "b"]);
  await rejects(env.svc.getCrew("c", { crewId }), "crew-not-found");
  await env.svc.leaveCrew("b", { crewId });
  assert.equal(env.repo.doc<CrewDoc>(P.crew(crewId))!.status, "forming");
});

// MARK: pokes

test("sendPoke: friends only, emote only, max 3/day", async () => {
  const env = setup();
  await friends(env, "a", "b", "c");
  await rejects(env.svc.sendPoke("a", { toUid: "b", emote: "wave" }), "not-friends");
  await befriend(env, "a", "b");
  await rejects(env.svc.sendPoke("a", { toUid: "b", emote: "hey call me" }), "bad-emote");
  for (let i = 0; i < MAX_POKES_PER_DAY; i++) await env.svc.sendPoke("a", { toUid: "b", emote: "hug" });
  await rejects(env.svc.sendPoke("a", { toUid: "b", emote: "hug" }), "poke-cap");
  env.days(1);
  assert.equal((await env.svc.sendPoke("a", { toUid: "b", emote: "hug" })).pokesLeftToday, 2);
  for (const p of env.repo.docsUnder<object>("pokes/")) assert.deepEqual(Object.keys(p).sort(), ["emote", "fromUid", "id", "toUid"]);
});

// MARK: privacy (§11 RED LINES)

test("privacy: duo / crew / visit read models and shared docs carry no location, status or activity", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b", "c");
  const { duoId } = await makeDuo(env, "a", "b", cs);
  await env.svc.morningWave("a", { duoId, localDay: utcDay(env.clock.t) });
  await env.svc.sendFridgeNote("a", { duoId, emote: "heart", prop: "tea" });
  await env.svc.savePainting("b", { group: "duo", groupId: duoId });
  const crewId = await makeCrew(env, ["a", "b", "c"], cs);
  await env.svc.rollCall("b", { crewId, emote: "wave" });
  const { visit } = await env.svc.startVisit("a", { creatureId: cs.a[1].id, hostUid: "c", days: 1 });

  const views = {
    duo: await env.svc.getDuo("b", { duoId }),
    crew: await env.svc.getCrew("c", { crewId }),
    visitor: await env.svc.getVisitor("c", { visitId: visit.id }),
    // Raw docs a member / host can read via rules:
    duoDoc: env.repo.doc(P.duo(duoId)),
    duoHouse: env.repo.doc(P.duoHouse(duoId)),
    duoNotes: env.repo.docsUnder(`duos/${duoId}/notes/`),
    crewDoc: env.repo.doc(P.crew(crewId)),
    crewHouse: env.repo.doc(P.crewHouse(crewId)),
    visitDoc: env.repo.doc(P.visit(visit.id)),
    returned: await env.svc.recallVisit("a", { visitId: visit.id }),
    pokes: env.repo.docsUnder("pokes/"),
  };
  for (const [name, v] of Object.entries(views)) {
    // visitDoc: ownerUid/hostUid are the two parties of the visit (rules key on them); nothing else.
    const keys = forbiddenKeys(v).filter((k) => !(name === "visitDoc" && /\.(ownerUid)$/.test(k)));
    assert.deepEqual(keys, [], name);
  }
  // Server-only bookkeeping holds the wave time, and rules never let a client read it.
  assert.ok(env.repo.doc<any>(P.duoPrivate(duoId)).waves.a.at > 0);
  const rules = (await import("node:fs")).readFileSync(new URL("../firestore.rules", import.meta.url), "utf8");
  for (const coll of ["duoPrivate", "away", "cooldowns", "invites"]) {
    assert.match(rules, new RegExp(`match /${coll}/\\{\\w+\\}\\s*\\{\\s*allow read, write: if false;`), coll);
  }
  // Partner's display name never reaches the duo view.
  assert.ok(!JSON.stringify(views.duo).includes("displayName"));
});

test("deleteAccount removes the player from the friends graph; partner keeps a twin", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b", "c", "d");
  const { creatureId } = await makeDuo(env, "a", "b", cs);
  const crewId = await makeCrew(env, ["c", "b", "d"], cs);
  await env.svc.startVisit("b", { creatureId: cs.b[1].id, hostUid: "a", days: 2 });
  await befriend(env, "c", "a");
  await env.svc.startVisit("c", { creatureId: cs.c[1].id, hostUid: "b", days: 2 });
  await env.svc.sendPoke("b", { toUid: "a", emote: "wave" });

  await env.svc.deleteAccount("b");
  const leftovers = [...env.repo.docs.entries()].filter(([k, v]) => JSON.stringify([k, v]).includes('"b"'));
  assert.deepEqual(leftovers, [], "no doc mentions b");
  assert.ok(![...env.repo.docs.keys()].some((k) => k.includes("/b/") || k.endsWith("/b")));
  assert.equal(env.repo.get("creatures", creatureId), undefined);
  assert.equal(env.repo.all<CreatureDoc>("creatures").filter((c) => c.origin === "duo" && c.ownerUid === "a").length, 1);
  assert.deepEqual(env.repo.doc<CrewDoc>(P.crew(crewId))!.members, ["c", "d"]);
  assert.equal(env.repo.doc(P.away(cs.c[1].id)), undefined);
  assert.ok(env.repo.doc(P.friend("a", "c")));
});
