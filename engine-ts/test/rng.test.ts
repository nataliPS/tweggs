import { test } from "node:test";
import assert from "node:assert/strict";
import { mulberry32 } from "../src/rng.ts";

function seq(seed: number, n: number): number[] {
  const r = mulberry32(seed);
  return Array.from({ length: n }, () => r.next());
}

test("mulberry32 is deterministic per seed", () => {
  assert.deepEqual(seq(42, 20), seq(42, 20));
  assert.notDeepEqual(seq(42, 5), seq(43, 5));
});

test("mulberry32 matches the canonical JS reference", () => {
  // canonical one-liner (bryc), returns float
  function ref(a: number) {
    return function () {
      let t = (a += 0x6d2b79f5);
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  for (const seed of [0, 1, 42, 0xdeadbeef, 0xffffffff]) {
    const f = ref(seed);
    const r = mulberry32(seed);
    for (let i = 0; i < 100; i++) assert.equal(r.float(), f());
  }
});

test("outputs are UInt32, float in [0,1), int in [0,n)", () => {
  const r = mulberry32(7);
  for (let i = 0; i < 1000; i++) {
    const v = r.next();
    assert.ok(Number.isInteger(v) && v >= 0 && v <= 0xffffffff);
    const f = r.float();
    assert.ok(f >= 0 && f < 1);
    const k = r.int(7);
    assert.ok(Number.isInteger(k) && k >= 0 && k < 7);
  }
  assert.throws(() => r.int(0));
});
