import { test } from "node:test";
import assert from "node:assert/strict";
import { fnv1a32, hex8 } from "../src/hash.ts";

test("fnv1a32 known values", () => {
  assert.equal(fnv1a32(""), 0x811c9dc5);
  assert.equal(fnv1a32("a"), 0xe40c292c);
  assert.equal(fnv1a32("foobar"), 0xbf9cf968);
});

test("fnv1a32 hashes UTF-8 bytes, not UTF-16 units", () => {
  // "é" = C3 A9 in UTF-8
  let h = 0x811c9dc5;
  for (const b of [0xc3, 0xa9]) h = Math.imul(h ^ b, 0x01000193) >>> 0;
  assert.equal(fnv1a32("é"), h);
  assert.notEqual(fnv1a32("é"), fnv1a32("é".normalize("NFD")));
});

test("hex8 pads and lowercases", () => {
  assert.equal(hex8(0), "00000000");
  assert.equal(hex8(0xabc), "00000abc");
  assert.equal(hex8(0xdeadbeef), "deadbeef");
});
