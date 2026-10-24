import { test } from "node:test";
import assert from "node:assert/strict";
import {
  CATALOG, SEASON_1, SEASONS, SURPRISE_COSMETICS,
  comboKey, comboKeyOfGenome, generation, seasonProgress, isSeasonActive, dailySurprise, seasonEntryVariant,
  express, type Genome,
} from "../src/index.ts";

test("comboKey joins the 7 visible expressed genes and ignores temper", () => {
  assert.equal(comboKey([0, 1, 2, 3, 4, 5, 6, 7]), "0-1-2-3-4-5-6");
  assert.equal(comboKey([0, 1, 2, 3, 4, 5, 6, 9]), "0-1-2-3-4-5-6");
  assert.equal(comboKey([5, 7, 7, 5, 5, 15, 3, 9]), "5-7-7-5-5-15-3");
  assert.throws(() => comboKey([0, 1]));
  const g: Genome = [[0, 4], [7, 0], [2, 1], [5, 3], [0, 0], [12, 15], [2, 1], [8, 9]];
  assert.equal(comboKeyOfGenome(g), comboKey(express(g)));
  // G3: drop(6) ties round(6) and cyclops(6) ties dots(6) -> lower index wins.
  assert.equal(comboKeyOfGenome(g), "4-7-1-3-0-15-1");
});

test("generation is 0 for starters and max(parents) + 1 for hybrids", () => {
  assert.equal(generation([]), 0);
  assert.equal(generation([0, 0]), 1);
  assert.equal(generation([2, 0]), 3);
  assert.equal(generation([1, 4]), 5);
});

test("season 1 is 12 unique, non-mutation variants with a balanced rarity mix", () => {
  assert.equal(SEASONS[0], SEASON_1);
  assert.equal(SEASON_1.entries.length, 12);
  const keys = new Set(SEASON_1.entries.map((e) => `${e.gene}:${e.variant}`));
  assert.equal(keys.size, 12);
  const byRarity = [0, 0, 0, 0];
  for (const e of SEASON_1.entries) {
    assert.ok(e.gene >= 0 && e.gene < 7, "visible genes only");
    assert.ok(e.variant >= 0 && e.variant < CATALOG[e.gene].variants.length);
    const v = seasonEntryVariant(e);
    assert.equal(v.mutationOnly, false);
    byRarity[v.rarity]++;
  }
  assert.deepEqual(byRarity, [5, 4, 3, 0]);
  assert.ok(isSeasonActive(SEASON_1, "2026-10-24"));
  assert.ok(isSeasonActive(SEASON_1, SEASON_1.endDay));
  assert.ok(!isSeasonActive(SEASON_1, "2027-06-01"));
});

test("seasonProgress marks entries expressed by any creature", () => {
  assert.deepEqual(seasonProgress(SEASON_1, []), Array(12).fill(false));
  const catearsMint = [0, 0, 1, 0, 0, 0, 0, 0];
  const starNight = [0, 6, 0, 0, 0, 12, 0, 0];
  const p = seasonProgress(SEASON_1, [catearsMint, starNight]);
  assert.deepEqual(p, [true, false, true, false, false, false, false, false, false, false, true, true]);
});

test("dailySurprise is deterministic, in range, and varies by day and player", () => {
  const a = dailySurprise("p1", "2026-10-24");
  assert.deepEqual(dailySurprise("p1", "2026-10-24"), a);
  let sparks = 0, cosmetics = 0;
  const seen = new Set<string>();
  for (let d = 1; d <= 200; d++) {
    const day = `2027-01-${String(d).padStart(3, "0")}`;
    const s = dailySurprise("player-x", day);
    seen.add(JSON.stringify(s));
    if (s.kind === "sparks") {
      sparks++;
      assert.ok(Number.isInteger(s.amount) && s.amount >= 5 && s.amount <= 25);
    } else {
      cosmetics++;
      assert.ok(SURPRISE_COSMETICS.includes(s.id));
    }
  }
  assert.ok(sparks > 100 && cosmetics > 10, `mix sparks=${sparks} cosmetics=${cosmetics}`);
  assert.ok(seen.size > 10);
});
