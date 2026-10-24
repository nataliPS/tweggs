// Shared input guards and creature helpers used by services.ts (breeding) and social.ts (friends graph).
// Pure: engine-ts + ports only.

import { fnv1a32, hex8, validateGenome } from "./engine.ts";
import { SPEC_VERSION } from "./config.ts";
import { fail } from "./errors.ts";
import type { Tx } from "./repository.ts";
import { AGE_BANDS, normalizeAgeBand, type AgeBand, type CreatureDoc, type PlayerDoc } from "./types.ts";

/** Canonical string a creature's `sig` covers: who owns what genome, and where it came from. */
export function creatureSigPayload(c: Pick<CreatureDoc, "id" | "ownerUid" | "genome" | "parentIds" | "generation" | "specVersion">): string {
  return [c.id, c.ownerUid, JSON.stringify(c.genome), c.parentIds.join(","), c.generation, c.specVersion].join("|");
}

/** 64-bit id (two independent FNV words) so ids stay unique across the whole player base. */
export function id64(prefix: string, key: string): string {
  return prefix + hex8(fnv1a32("a|" + key)) + hex8(fnv1a32("b|" + key));
}

export function requireUid(uid: string | null | undefined): string {
  if (typeof uid !== "string" || uid.length === 0) fail("unauthenticated", "no-auth");
  return uid as string;
}

export function requireString(v: unknown, field: string, max = 200): string {
  if (typeof v !== "string" || v.length === 0 || v.length > max || v.includes("/")) {
    fail("invalid-argument", "bad-" + field);
  }
  return v as string;
}

export async function loadPlayer(tx: Tx, uid: string): Promise<PlayerDoc> {
  const p = await tx.getPlayer(uid);
  if (!p) fail("failed-precondition", "not-registered");
  return p as PlayerDoc;
}

/** Legacy-safe: a stored "13to17" counts as 13to15; an unknown band counts as under13 (fail closed). */
export function bandAtLeast(band: AgeBand | string, min: AgeBand): boolean {
  return AGE_BANDS.indexOf(normalizeAgeBand(band) ?? "under13") >= AGE_BANDS.indexOf(min);
}

export function requireSocial(p: PlayerDoc): void {
  // Retro C2: under-13 players are offline-only, no social features.
  if (!bandAtLeast(p.ageBand, "13to15")) fail("permission-denied", "age-restricted");
}

export async function loadOwnedCreature(tx: Tx, id: string, uid: string): Promise<CreatureDoc> {
  const c = await tx.getCreature(id);
  if (!c) fail("not-found", "creature-not-found");
  if ((c as CreatureDoc).ownerUid !== uid) fail("permission-denied", "not-owner");
  return c as CreatureDoc;
}

/** Builds a signed creature doc (validates the genome first). */
export function creatureFactory(sign: (payload: string) => string) {
  return (fields: Omit<CreatureDoc, "sig" | "specVersion" | "createdAt"> & { createdAt: number }): CreatureDoc => {
    validateGenome(fields.genome);
    const doc: CreatureDoc = { ...fields, specVersion: SPEC_VERSION, sig: "" };
    doc.sig = sign(creatureSigPayload(doc));
    return doc;
  };
}
