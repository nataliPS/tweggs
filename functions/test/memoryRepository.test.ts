import { test } from "node:test";
import assert from "node:assert/strict";
import { MemoryRepository, type PlayerDoc } from "../src/index.ts";

const player = (uid: string): PlayerDoc => ({
  uid, displayName: "", createdAt: 0, ageBand: "18plus", unlockedMutations: [], streak: { count: 0, lastDayUTC: null },
  limits: { dayUTC: "2026-01-01", offers: 0, previews: 0 }, sparks: 0, lastSurpriseDayUTC: null, cosmetics: [],
});

test("writes are atomic: a throwing transaction writes nothing", async () => {
  const repo = new MemoryRepository();
  await assert.rejects(repo.runTransaction(async (tx) => {
    tx.setPlayer(player("a"));
    throw new Error("boom");
  }));
  assert.equal(repo.all("players").length, 0);
});

test("reads after writes are rejected (Firestore rule)", async () => {
  const repo = new MemoryRepository();
  await assert.rejects(repo.runTransaction(async (tx) => {
    tx.setPlayer(player("a"));
    await tx.getPlayer("a");
  }), /read after write/);
});

test("returned and stored docs are copies", async () => {
  const repo = new MemoryRepository();
  const p = player("a");
  await repo.runTransaction(async (tx) => tx.setPlayer(p));
  p.sparks = 999;
  const got = await repo.runTransaction(async (tx) => tx.getPlayer("a"));
  assert.equal(got!.sparks, 0);
  got!.sparks = 5;
  assert.equal(repo.get<PlayerDoc>("players", "a")!.sparks, 0);
});

test("transactions are serialized", async () => {
  const repo = new MemoryRepository();
  await repo.runTransaction(async (tx) => tx.setPlayer(player("a")));
  const inc = () => repo.runTransaction(async (tx) => {
    const p = (await tx.getPlayer("a"))!;
    await new Promise((r) => setTimeout(r, 1));
    tx.setPlayer({ ...p, sparks: p.sparks + 1 });
  });
  await Promise.all(Array.from({ length: 20 }, inc));
  assert.equal(repo.get<PlayerDoc>("players", "a")!.sparks, 20);
});
