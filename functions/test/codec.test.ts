import { test } from "node:test";
import assert from "node:assert/strict";
import { starter } from "../../engine-ts/src/index.ts";
import { creatureCodec, breedCodec, flattenGenome, unflattenGenome } from "../src/firebase/codec.ts";
import { setup, friends } from "./helpers.ts";

const hasNestedArray = (v: unknown): boolean =>
  Array.isArray(v) ? v.some((x) => Array.isArray(x) || hasNestedArray(x))
  : v !== null && typeof v === "object" ? Object.values(v).some(hasNestedArray) : false;

test("genome flattens to 16 ints and round-trips", () => {
  const g = starter("alice", 0);
  const flat = flattenGenome(g);
  assert.equal(flat.length, 16);
  assert.deepEqual(unflattenGenome(flat), g);
  assert.throws(() => unflattenGenome([1, 2, 3]));
});

test("stored creature and breed docs contain no nested arrays (Firestore rule) and round-trip", async () => {
  const env = setup();
  const cs = await friends(env, "a", "b");
  const { offer } = await env.svc.createOffer("a", { parentCreatureId: cs.a[0].id });
  const p = await env.svc.previewBreed("b", { offerId: offer.id, myCreatureId: cs.b[0].id });
  const c = cs.a[0];
  const b = env.repo.get<any>("breeds", p.breedId);
  assert.equal(hasNestedArray(creatureCodec.toStored(c)), false);
  assert.equal(hasNestedArray(breedCodec.toStored(b)), false);
  assert.deepEqual(creatureCodec.fromStored(creatureCodec.toStored(c)), c);
  assert.deepEqual(breedCodec.fromStored(breedCodec.toStored(b)), b);
});
