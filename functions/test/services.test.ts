import { test } from "node:test";
import assert from "node:assert/strict";
import {
  breed, comboKeyOfGenome, dailySurprise, starter, validateGenome, rarity,
} from "../../engine-ts/src/index.ts";
import {
  DAY_MS, HOUR_MS, MAX_OFFERS_PER_DAY, MAX_PREVIEWS_PER_DAY, DELETED_UID, STREAK_UNLOCKS,
  creatureSigPayload, verifySig, starterCreatureId, stageOf, unlocksForStreak, utcDay,
  type BreedDoc, type ComboDoc, type CreatureDoc, type OfferDoc, type PlayerDoc,
} from "../src/index.ts";
import { T0, friends, rejects, setup } from "./helpers.ts";

// MARK: registerPlayer

test("registerPlayer persists both starters server-side with engine genomes", async () => {
  const env = setup();
  const r = await env.svc.registerPlayer("alice", { ageBand: "18plus", displayName: "Alice" });
  assert.equal(r.created, true);
  assert.equal(r.starters.length, 2);
  for (const [slot, c] of r.starters.entries()) {
    assert.deepEqual(c.genome, starter("alice", slot));
    assert.equal(c.id, starterCreatureId("alice", slot));
    assert.equal(c.ownerUid, "alice");
    assert.equal(c.generation, 0);
    assert.equal(c.origin, "starter");
    assert.equal(c.comboKey, comboKeyOfGenome(c.genome));
    assert.ok(verifySig("test-secret-0123456789", creatureSigPayload(c), c.sig));
    assert.deepEqual(env.repo.get("creatures", c.id), c);
  }
  const p = env.repo.get<PlayerDoc>("players", "alice")!;
  assert.deepEqual(p.unlockedMutations, []);
  assert.equal(p.sparks, 0);
  assert.equal(p.displayName, "Alice");
});

test("registerPlayer is idempotent and does not reset state", async () => {
  const env = setup();
  await env.svc.registerPlayer("alice", { ageBand: "18plus" });
  await env.svc.claimDailySurprise("alice");
  const before = env.repo.get<PlayerDoc>("players", "alice")!;
  const again = await env.svc.registerPlayer("alice", { ageBand: "under13" });
  assert.equal(again.created, false);
  assert.deepEqual(again.player, before);
  assert.equal(again.starters.length, 2);
  assert.equal(env.repo.all("creatures").length, 2);
});

test("registerPlayer validates auth, age band and display name", async () => {
  const env = setup();
  await rejects(env.svc.registerPlayer(null, { ageBand: "18plus" }), "no-auth");
  await rejects(env.svc.registerPlayer("a", { ageBand: "adult" }), "bad-ageBand");
  await rejects(env.svc.registerPlayer("a", {}), "bad-ageBand");
  await rejects(env.svc.registerPlayer("a", { ageBand: "18plus", displayName: "call 0501234567" }), "bad-displayName");
  assert.equal(env.repo.all("players").length, 0);
});

test("growth: starter 0 is teen on day 3, starter 1 hatches on day 2 (retro G4)", async () => {
  const env = setup();
  const [s0, s1] = (await env.svc.registerPlayer("a", { ageBand: "18plus" })).starters;
  assert.equal(stageOf(s0, T0), "baby");
  assert.equal(stageOf(s1, T0), "egg");
  assert.equal(stageOf(s1, T0 + DAY_MS), "baby");
  assert.equal(stageOf(s0, T0 + 2 * DAY_MS), "teen");
  assert.equal(stageOf(s0, T0 + 6 * DAY_MS), "adult");
});

// MARK: createOffer

test("createOffer: own teen+ creature only, 72h expiry, 20 per UTC day", async () => {
  const env = setup();
  const { a, b } = await friends(env, "a", "b");
  const r = await env.svc.createOffer("a", { parentCreatureId: a[0].id });
  assert.equal(r.offer.status, "open");
  assert.equal(r.offer.expiresAt - r.offer.createdAt, 72 * HOUR_MS);
  assert.equal(r.offersLeftToday, MAX_OFFERS_PER_DAY - 1);
  await rejects(env.svc.createOffer("a", { parentCreatureId: b[0].id }), "not-owner");
  await rejects(env.svc.createOffer("a", { parentCreatureId: "nope" }), "creature-not-found");
  await rejects(env.svc.createOffer("zed", { parentCreatureId: a[0].id }), "not-registered");
  await rejects(env.svc.createOffer("a", { parentCreatureId: "x/y" }), "bad-parentCreatureId");
  for (let i = 1; i < MAX_OFFERS_PER_DAY; i++) await env.svc.createOffer("a", { parentCreatureId: a[i % 2].id });
  await rejects(env.svc.createOffer("a", { parentCreatureId: a[0].id }), "offer-cap");
  // New UTC day resets the cap.
  const msToMidnight = Date.parse(utcDay(env.clock.t) + "T00:00:00Z") + DAY_MS - env.clock.t;
  env.advance(msToMidnight);
  await env.svc.createOffer("a", { parentCreatureId: a[0].id });
});

test("createOffer: babies and eggs cannot breed; teens can", async () => {
  const env = setup();
  const [s0, s1] = (await env.svc.registerPlayer("a", { ageBand: "18plus" })).starters;
  await rejects(env.svc.createOffer("a", { parentCreatureId: s0.id }), "too-young");
  await rejects(env.svc.createOffer("a", { parentCreatureId: s1.id }), "too-young");
  env.days(2);
  await env.svc.createOffer("a", { parentCreatureId: s0.id });
});

test("under-13 players have no social features (retro C2)", async () => {
  const env = setup();
  const kid = (await env.svc.registerPlayer("kid", { ageBand: "under13" })).starters;
  await friends(env, "b");
  await rejects(env.svc.createOffer("kid", { parentCreatureId: kid[0].id }), "age-restricted");
  const { offer } = await env.svc.createOffer("b", { parentCreatureId: env.repo.all<CreatureDoc>("creatures").find((c) => c.ownerUid === "b")!.id });
  await rejects(env.svc.previewBreed("kid", { offerId: offer.id, myCreatureId: kid[0].id }), "age-restricted");
  // Solo features still work.
  await env.svc.claimDailySurprise("kid");
  await env.svc.checkInStreak("kid");
});

// MARK: previewBreed

async function offerSetup() {
  const env = setup();
  const cs = await friends(env, "alice", "bob");
  const { offer } = await env.svc.createOffer("alice", { parentCreatureId: cs.alice[0].id });
  return { env, cs, offer };
}

test("previewBreed matches engine breed() with the stored nonce and server genomes", async () => {
  const { env, cs, offer } = await offerSetup();
  const p = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id });
  assert.equal(p.fresh, true);
  const expected = breed({
    parentA: { id: cs.alice[0].id, genome: cs.alice[0].genome, owner: "alice" },
    parentB: { id: cs.bob[0].id, genome: cs.bob[0].genome, owner: "bob" },
    nonce: p.nonce,
    unlockedMutations: [],
  });
  assert.deepEqual(p.child.genome, expected.genome);
  assert.equal(p.child.id, expected.id);
  assert.deepEqual(p.child.paletteShift, expected.paletteShift);
  assert.deepEqual(p.child.rarity, rarity(expected.genome));
  assert.equal(p.myPaletteShift, expected.paletteShift.bob);
  assert.equal(p.previewsLeftToday, MAX_PREVIEWS_PER_DAY - 1);
});

test("previewBreed: same pair returns the SAME nonce and child, no cap charge (no reroll)", async () => {
  const { env, cs, offer } = await offerSetup();
  const a = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id });
  const b = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id });
  assert.equal(b.fresh, false);
  assert.equal(b.nonce, a.nonce);
  assert.equal(b.breedId, a.breedId);
  assert.deepEqual(b.child, a.child);
  assert.equal(b.previewsLeftToday, a.previewsLeftToday);
  assert.equal(env.repo.all("breeds").length, 1);
  // Different acceptor creature = a different binding with a different nonce.
  const c = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[1].id });
  assert.notEqual(c.nonce, a.nonce);
  assert.equal(env.repo.all("breeds").length, 2);
});

test("previewBreed ignores client-sent genomes and mutations (spec §7.3, §7.4)", async () => {
  const { env, cs, offer } = await offerSetup();
  const evil: any = {
    offerId: offer.id, myCreatureId: cs.bob[0].id,
    genome: [[4, 4], [7, 7], [7, 7], [4, 4], [5, 5], [15, 15], [3, 3], [9, 9]],
    unlockedMutations: [{ gene: 5, variant: 15 }],
  };
  const p = await env.svc.previewBreed("bob", evil);
  const stored = env.repo.get<BreedDoc>("breeds", p.breedId)!;
  assert.deepEqual(stored.unlockedMutations, []);
  const expected = breed({
    parentA: { id: cs.alice[0].id, genome: cs.alice[0].genome, owner: "alice" },
    parentB: { id: cs.bob[0].id, genome: cs.bob[0].genome, owner: "bob" },
    nonce: p.nonce, unlockedMutations: [],
  });
  assert.deepEqual(p.child.genome, expected.genome);
});

test("previewBreed uses the player's SERVER mutations", async () => {
  const { env, cs, offer } = await offerSetup();
  const bob = env.repo.get<PlayerDoc>("players", "bob")!;
  env.repo.put("players", "bob", { ...bob, unlockedMutations: [{ gene: 6, variant: 3 }, { gene: 5, variant: 15 }] });
  const p = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id });
  const stored = env.repo.get<BreedDoc>("breeds", p.breedId)!;
  assert.deepEqual(stored.unlockedMutations, [{ gene: 5, variant: 15 }, { gene: 6, variant: 3 }]);
  const expected = breed({
    parentA: { id: cs.alice[0].id, genome: cs.alice[0].genome, owner: "alice" },
    parentB: { id: cs.bob[0].id, genome: cs.bob[0].genome, owner: "bob" },
    nonce: p.nonce, unlockedMutations: stored.unlockedMutations,
  });
  assert.deepEqual(p.child.genome, expected.genome);
  assert.deepEqual(p.child.mutation, expected.mutation);
});

test("previewBreed caps at 10 fresh previews per UTC day", async () => {
  const env = setup();
  const cs = await friends(env, "alice", "bob");
  const offers: OfferDoc[] = [];
  for (let i = 0; i < 6; i++) offers.push((await env.svc.createOffer("alice", { parentCreatureId: cs.alice[i % 2].id })).offer);
  let n = 0;
  outer: for (const o of offers) for (const mine of cs.bob) {
    if (n === MAX_PREVIEWS_PER_DAY) break outer;
    await env.svc.previewBreed("bob", { offerId: o.id, myCreatureId: mine.id });
    n++;
  }
  await rejects(env.svc.previewBreed("bob", { offerId: offers[5].id, myCreatureId: cs.bob[0].id }), "preview-cap");
  // Repeats of an existing pair still work at the cap.
  const again = await env.svc.previewBreed("bob", { offerId: offers[0].id, myCreatureId: cs.bob[0].id });
  assert.equal(again.fresh, false);
  assert.equal(again.previewsLeftToday, 0);
  env.days(1);
  await env.svc.previewBreed("bob", { offerId: offers[5].id, myCreatureId: cs.bob[0].id });
});

test("previewBreed rejects own offer, foreign creature, expired / cancelled offers", async () => {
  const { env, cs, offer } = await offerSetup();
  await rejects(env.svc.previewBreed("alice", { offerId: offer.id, myCreatureId: cs.alice[1].id }), "own-offer");
  await rejects(env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.alice[1].id }), "not-owner");
  await rejects(env.svc.previewBreed("bob", { offerId: "o_missing", myCreatureId: cs.bob[0].id }), "offer-not-found");
  env.advance(72 * HOUR_MS);
  await rejects(env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id }), "offer-expired");
  const o2 = (await env.svc.createOffer("alice", { parentCreatureId: cs.alice[0].id })).offer;
  await env.svc.cancelOffer("alice", { offerId: o2.id });
  await rejects(env.svc.previewBreed("bob", { offerId: o2.id, myCreatureId: cs.bob[0].id }), "offer-cancelled");
});

test("cancelOffer burns open previews; only the creator can cancel", async () => {
  const { env, cs, offer } = await offerSetup();
  const p = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id });
  await rejects(env.svc.cancelOffer("bob", { offerId: offer.id }), "not-owner");
  const r = await env.svc.cancelOffer("alice", { offerId: offer.id });
  assert.equal(r.burned, 1);
  assert.equal(env.repo.get<BreedDoc>("breeds", p.breedId)!.status, "burned");
  await rejects(env.svc.commitBreed("bob", { breedId: p.breedId }), "breed-burned");
});

// MARK: commitBreed

test("commitBreed creates both twins atomically with serial 1 and discoverer", async () => {
  const { env, cs, offer } = await offerSetup();
  const p = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id });
  const r = await env.svc.commitBreed("bob", { breedId: p.breedId });
  assert.equal(r.replay, false);
  assert.equal(r.creatures.length, 2);
  const [mine, theirs] = r.creatures;
  assert.equal(mine.ownerUid, "bob");
  assert.equal(theirs.ownerUid, "alice");
  for (const c of r.creatures) {
    validateGenome(c.genome);
    assert.deepEqual(c.genome, p.child.genome);
    assert.equal(c.comboKey, p.child.comboKey);
    assert.equal(c.serial, 1);
    assert.equal(c.discoveredFirst, true);
    assert.equal(c.generation, 1);
    assert.equal(c.origin, "bred");
    assert.deepEqual(c.parentIds, [cs.alice[0].id, cs.bob[0].id].sort());
    assert.equal(c.paletteShift, p.child.paletteShift[c.ownerUid]);
    assert.ok(verifySig("test-secret-0123456789", creatureSigPayload(c), c.sig));
    assert.ok(env.repo.get("creatures", c.id));
  }
  assert.notEqual(mine.id, theirs.id);
  assert.notEqual(mine.paletteShift, theirs.paletteShift);
  const combo = env.repo.get<ComboDoc>("combos", p.child.comboKey)!;
  assert.equal(combo.count, 1);
  assert.equal(combo.discovererUid, "bob");
  assert.equal(env.repo.get<OfferDoc>("offers", offer.id)!.status, "used");
  const b = env.repo.get<BreedDoc>("breeds", p.breedId)!;
  assert.equal(b.status, "committed");
  assert.deepEqual(b.childIds, [mine.id, theirs.id]);
});

test("commitBreed is idempotent; one commit per offer; sibling previews burned", async () => {
  const { env, cs, offer } = await offerSetup();
  const p1 = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id });
  const p2 = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[1].id });
  const r1 = await env.svc.commitBreed("bob", { breedId: p1.breedId });
  const again = await env.svc.commitBreed("bob", { breedId: p1.breedId });
  assert.equal(again.replay, true);
  assert.deepEqual(again.creatures.map((c) => c.id), r1.creatures.map((c) => c.id));
  assert.equal(env.repo.all("creatures").length, 6);
  assert.equal(env.repo.get<BreedDoc>("breeds", p2.breedId)!.status, "burned");
  await rejects(env.svc.commitBreed("bob", { breedId: p2.breedId }), "breed-burned");
  await rejects(env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[1].id }), "offer-used");
  assert.equal(env.repo.get<ComboDoc>("combos", p1.child.comboKey)!.count, 1);
});

test("commitBreed: only the acceptor; not after expiry; validates input", async () => {
  const { env, cs, offer } = await offerSetup();
  const p = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id });
  await rejects(env.svc.commitBreed("alice", { breedId: p.breedId }), "not-acceptor");
  await rejects(env.svc.commitBreed("bob", { breedId: "b_nope" }), "breed-not-found");
  await rejects(env.svc.commitBreed("bob", {}), "bad-breedId");
  env.advance(72 * HOUR_MS);
  await rejects(env.svc.commitBreed("bob", { breedId: p.breedId }), "offer-expired");
  assert.equal(env.repo.all("creatures").length, 4);
});

test("commitBreed: serials count up per comboKey; discoverer is set only once", async () => {
  const env = setup();
  await friends(env, "alice", "bob", "carol");
  // Two identical-genome parents (all genes homozygous) always give the same comboKey.
  const g = [[0, 0], [0, 0], [1, 1], [1, 1], [1, 1], [0, 0], [0, 0], [0, 0]] as CreatureDoc["genome"];
  const base = env.repo.get<CreatureDoc>("creatures", starterCreatureId("alice", 0))!;
  const mk = (id: string, owner: string): CreatureDoc => ({ ...base, id, ownerUid: owner, genome: g, comboKey: comboKeyOfGenome(g) });
  env.repo.put("creatures", "x_alice", mk("x_alice", "alice"));
  env.repo.put("creatures", "x_bob", mk("x_bob", "bob"));
  env.repo.put("creatures", "x_carol", mk("x_carol", "carol"));
  const key = comboKeyOfGenome(g);

  const o1 = (await env.svc.createOffer("alice", { parentCreatureId: "x_alice" })).offer;
  const p1 = await env.svc.previewBreed("bob", { offerId: o1.id, myCreatureId: "x_bob" });
  assert.equal(p1.child.comboKey, key);
  const r1 = await env.svc.commitBreed("bob", { breedId: p1.breedId });

  const o2 = (await env.svc.createOffer("alice", { parentCreatureId: "x_alice" })).offer;
  const p2 = await env.svc.previewBreed("carol", { offerId: o2.id, myCreatureId: "x_carol" });
  const r2 = await env.svc.commitBreed("carol", { breedId: p2.breedId });

  assert.equal(r1.serial, 1);
  assert.equal(r1.discoveredFirst, true);
  assert.equal(r2.serial, 2);
  assert.equal(r2.discoveredFirst, false);
  assert.ok(r2.creatures.every((c) => c.serial === 2 && !c.discoveredFirst));
  const combo = env.repo.get<ComboDoc>("combos", key)!;
  assert.equal(combo.count, 2);
  assert.equal(combo.discovererUid, "bob");
});

test("commitBreed: concurrent commits on different offers serialize serials", async () => {
  const env = setup();
  const cs = await friends(env, "alice", "bob");
  const offers = [];
  for (let i = 0; i < 2; i++) offers.push((await env.svc.createOffer("alice", { parentCreatureId: cs.alice[i].id })).offer);
  const p = await Promise.all(offers.map((o, i) => env.svc.previewBreed("bob", { offerId: o.id, myCreatureId: cs.bob[i].id })));
  const r = await Promise.all(p.map((x) => env.svc.commitBreed("bob", { breedId: x.breedId })));
  for (const x of r) assert.ok(x.serial >= 1);
  const combos = env.repo.all<ComboDoc>("combos");
  assert.equal(combos.reduce((s, c) => s + c.count, 0), 2);
});

test("commitBreed: transaction failure writes nothing", async () => {
  const { env, cs, offer } = await offerSetup();
  const p = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id });
  // Tamper with the stored preview: server recompute must catch it and abort the whole transaction.
  const b = env.repo.get<BreedDoc>("breeds", p.breedId)!;
  env.repo.put("breeds", b.id, { ...b, previewChild: { ...b.previewChild, id: "c_forged00" } });
  await rejects(env.svc.commitBreed("bob", { breedId: p.breedId }), "preview-mismatch");
  assert.equal(env.repo.all("creatures").length, 4);
  assert.equal(env.repo.all("combos").length, 0);
  assert.equal(env.repo.get<OfferDoc>("offers", offer.id)!.status, "open");
});

test("bred children can breed again once grown; generation climbs", async () => {
  const { env, cs, offer } = await offerSetup();
  const p = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id });
  const [kidBob, kidAlice] = (await env.svc.commitBreed("bob", { breedId: p.breedId })).creatures;
  await rejects(env.svc.createOffer("bob", { parentCreatureId: kidBob.id }), "too-young");
  env.days(3);
  const o = (await env.svc.createOffer("bob", { parentCreatureId: kidBob.id })).offer;
  const p2 = await env.svc.previewBreed("alice", { offerId: o.id, myCreatureId: kidAlice.id });
  const r = await env.svc.commitBreed("alice", { breedId: p2.breedId });
  assert.equal(r.creatures[0].generation, 2);
});

// MARK: daily surprise

test("claimDailySurprise uses server UTC day and is once per day", async () => {
  const env = setup(Date.parse("2026-11-02T23:59:00Z"));
  await env.svc.registerPlayer("a", { ageBand: "18plus" });
  const r1 = await env.svc.claimDailySurprise("a");
  assert.equal(r1.day, "2026-11-02");
  assert.deepEqual(r1.souvenir, dailySurprise("a", "2026-11-02"));
  const r2 = await env.svc.claimDailySurprise("a");
  assert.equal(r2.alreadyClaimed, true);
  assert.deepEqual(r2.souvenir, r1.souvenir);
  assert.equal(r2.sparks, r1.sparks);
  env.advance(2 * 60 * 1000);
  const r3 = await env.svc.claimDailySurprise("a");
  assert.equal(r3.day, "2026-11-03");
  assert.equal(r3.alreadyClaimed, false);
});

test("claimDailySurprise credits sparks or cosmetics exactly once over many days", async () => {
  const env = setup();
  await env.svc.registerPlayer("a", { ageBand: "18plus" });
  let sparks = 0;
  const cos = new Set<string>();
  for (let d = 0; d < 40; d++) {
    const day = utcDay(env.clock.t);
    const s = dailySurprise("a", day);
    if (s.kind === "sparks") sparks += s.amount; else cos.add(s.id);
    await env.svc.claimDailySurprise("a");
    await env.svc.claimDailySurprise("a");
    env.days(1);
  }
  const p = env.repo.get<PlayerDoc>("players", "a")!;
  assert.equal(p.sparks, sparks);
  assert.deepEqual(new Set(p.cosmetics), cos);
  await rejects(env.svc.claimDailySurprise("ghost"), "not-registered");
});

// MARK: streaks

test("checkInStreak counts consecutive UTC days and resets on a gap", async () => {
  const env = setup(Date.parse("2026-11-02T23:30:00Z"));
  await env.svc.registerPlayer("a", { ageBand: "18plus" });
  assert.equal((await env.svc.checkInStreak("a")).count, 1);
  const same = await env.svc.checkInStreak("a");
  assert.equal(same.alreadyCheckedIn, true);
  assert.equal(same.count, 1);
  env.advance(HOUR_MS); // crosses UTC midnight: next day even though < 24h
  assert.equal((await env.svc.checkInStreak("a")).count, 2);
  env.days(2); // skip a day
  assert.equal((await env.svc.checkInStreak("a")).count, 1);
});

test("checkInStreak unlocks mutations per the table and keeps them after a break", async () => {
  const env = setup();
  await env.svc.registerPlayer("a", { ageBand: "18plus" });
  const unlockedAt: Record<number, number> = {};
  for (let d = 1; d <= 30; d++) {
    const r = await env.svc.checkInStreak("a");
    assert.equal(r.count, d);
    if (r.newlyUnlocked.length) unlockedAt[d] = r.newlyUnlocked.length;
    env.days(1);
  }
  assert.deepEqual(Object.keys(unlockedAt).map(Number), STREAK_UNLOCKS.map((u) => u.days));
  const p = env.repo.get<PlayerDoc>("players", "a")!;
  assert.deepEqual(p.unlockedMutations, unlocksForStreak(30));
  assert.equal(p.unlockedMutations.length, STREAK_UNLOCKS.length);
  env.days(5);
  const r = await env.svc.checkInStreak("a");
  assert.equal(r.count, 1);
  assert.deepEqual(r.unlockedMutations, unlocksForStreak(30));
  assert.deepEqual(r.newlyUnlocked, []);
});

test("streak unlock table only lists real mutation-only variants", async () => {
  const { CATALOG } = await import("../../engine-ts/src/index.ts");
  for (const u of STREAK_UNLOCKS) {
    const v = CATALOG[u.mutation.gene].variants[u.mutation.variant];
    assert.ok(v, `variant ${u.mutation.gene}:${u.mutation.variant} exists`);
    assert.equal(v.mutationOnly, true, `${v.name} is mutation-only`);
  }
});

// MARK: rename

test("renameCreature: owner only, filtered, trimmed", async () => {
  const env = setup();
  const { a, b } = await friends(env, "a", "b");
  assert.deepEqual(await env.svc.renameCreature("a", { id: a[0].id, name: "  Пухнастик  " }), { id: a[0].id, name: "Пухнастик" });
  assert.equal(env.repo.get<CreatureDoc>("creatures", a[0].id)!.name, "Пухнастик");
  await rejects(env.svc.renameCreature("a", { id: b[0].id, name: "Mine" }), "not-owner");
  await rejects(env.svc.renameCreature("a", { id: a[0].id, name: "sh1t" }), "bad-name");
  await rejects(env.svc.renameCreature("a", { id: a[0].id, name: "" }), "bad-name");
  assert.equal(env.repo.get<CreatureDoc>("creatures", a[0].id)!.name, "Пухнастик");
});

// MARK: deleteAccount

test("deleteAccount removes all of the player's docs; friends keep their twins", async () => {
  const { env, cs, offer } = await offerSetup();
  const p = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id });
  const [, aliceTwin] = (await env.svc.commitBreed("bob", { breedId: p.breedId })).creatures;
  const o2 = (await env.svc.createOffer("bob", { parentCreatureId: cs.bob[1].id })).offer;
  const p2 = await env.svc.previewBreed("alice", { offerId: o2.id, myCreatureId: cs.alice[1].id });
  env.repo.social.set("bob", [{ reason: "spam" }]);

  const r = await env.svc.deleteAccount("bob");
  assert.equal(r.creatures, 3);
  assert.equal(r.offers, 1);
  assert.equal(r.breeds, 2);
  assert.equal(r.combosAnonymized, 1);
  assert.equal(env.repo.get("players", "bob"), undefined);
  assert.ok(env.repo.all<CreatureDoc>("creatures").every((c) => c.ownerUid !== "bob"));
  assert.ok(env.repo.all<OfferDoc>("offers").every((o) => o.creatorUid !== "bob"));
  assert.ok(env.repo.all<BreedDoc>("breeds").every((b) => b.acceptorUid !== "bob" && b.id !== p2.breedId));
  assert.equal(env.repo.get<ComboDoc>("combos", p.child.comboKey)!.discovererUid, DELETED_UID);
  assert.ok(env.repo.get("creatures", aliceTwin.id));
  assert.equal(env.repo.social.has("bob"), false);
  assert.ok(!JSON.stringify(env.repo.data.players.get("alice")).includes("bob"));
  // Idempotent, and re-registration starts clean.
  assert.deepEqual(await env.svc.deleteAccount("bob"), { creatures: 0, offers: 0, breeds: 0, combosAnonymized: 0 });
  const again = await env.svc.registerPlayer("bob", { ageBand: "18plus" });
  assert.equal(again.created, true);
});

test("deleteAccount handles more docs than one chunk", async () => {
  const env = setup();
  const { a } = await friends(env, "a");
  for (let i = 0; i < 250; i++) env.repo.put("creatures", `bulk_${i}`, { ...a[0], id: `bulk_${i}` });
  for (let d = 0; d < 3; d++) {
    for (let i = 0; i < 15; i++) await env.svc.createOffer("a", { parentCreatureId: a[0].id });
    env.days(1);
  }
  const r = await env.svc.deleteAccount("a");
  assert.equal(r.creatures, 252);
  assert.equal(r.offers, 45);
  assert.equal(env.repo.all("creatures").length, 0);
  assert.equal(env.repo.all("offers").length, 0);
});

// MARK: hourly sweep

test("sweep expires offers after 72h and burns stale previews", async () => {
  const { env, cs, offer } = await offerSetup();
  const p = await env.svc.previewBreed("bob", { offerId: offer.id, myCreatureId: cs.bob[0].id });
  env.advance(25 * HOUR_MS);
  const o2 = (await env.svc.createOffer("alice", { parentCreatureId: cs.alice[1].id })).offer;
  let r = await env.svc.sweep();
  assert.deepEqual(r, { expiredOffers: 0, burnedPreviews: 1 });
  assert.equal(env.repo.get<BreedDoc>("breeds", p.breedId)!.status, "burned");
  env.advance(48 * HOUR_MS);
  r = await env.svc.sweep();
  assert.equal(r.expiredOffers, 1);
  assert.equal(env.repo.get<OfferDoc>("offers", offer.id)!.status, "expired");
  assert.equal(env.repo.get<OfferDoc>("offers", o2.id)!.status, "open");
  assert.deepEqual(await env.svc.sweep(), { expiredOffers: 0, burnedPreviews: 0 });
});
