import { test } from "node:test";
import assert from "node:assert/strict";
import { checkName } from "../src/index.ts";

test("accepts ordinary names in several scripts", () => {
  for (const n of ["Mixy", "Pip", "Пухнастик", "Їжачок", "Mr. Bean", "Ana-Maria", "O'Neil", "Peacock", "Skillet", "Zoë", "R2"]) {
    const v = checkName(n);
    assert.ok(v.ok, `${n}: ${JSON.stringify(v)}`);
  }
});

test("normalizes whitespace", () => {
  assert.deepEqual(checkName("  Big   Bob "), { ok: true, name: "Big Bob" });
});

test("rejects length, characters, contact data, links and blocked words", () => {
  const cases: [unknown, string][] = [
    ["", "too-short"], ["   ", "too-short"], ["x".repeat(17), "too-long"], [42, "not-a-string"],
    ["hi😀", "bad-characters"], ["a@b", "bad-characters"], ["<script>", "bad-characters"],
    ["050 123 45", "contact-info"], ["call 123", "contact-info"],
    ["www dot", "link"], ["t.me bob", "link"],
    ["fuck", "blocked-word"], ["FuCk", "blocked-word"], ["sh1t", "blocked-word"], ["f.u.c.k", "blocked-word"],
    ["Хуйло", "blocked-word"], ["сука", "blocked-word"], ["Hitler", "blocked-word"],
  ];
  for (const [n, reason] of cases) {
    const v = checkName(n);
    assert.equal(v.ok, false, String(n));
    if (!v.ok) assert.equal(v.reason, reason, String(n));
  }
});
