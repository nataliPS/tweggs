import assert from "node:assert/strict";
import { MemoryRepository, createServices, hmacSigner, DAY_MS, type CreatureDoc } from "../src/index.ts";

export const T0 = Date.parse("2026-11-02T10:00:00.000Z");

export function setup(start = T0) {
  const repo = new MemoryRepository();
  const clock = { t: start };
  let n = 0;
  const svc = createServices({
    repo,
    now: () => clock.t,
    randomToken: () => `tok-${(++n).toString().padStart(6, "0")}-${n * 7919}`,
    sign: hmacSigner("test-secret-0123456789"),
  });
  const advance = (ms: number) => { clock.t += ms; };
  const days = (d: number) => advance(d * DAY_MS);
  return { repo, svc, clock, advance, days };
}

export type Env = ReturnType<typeof setup>;

/** Registers players and ages everyone 7 days (so starters are adults). */
export async function friends(env: Env, ...uids: string[]) {
  const out: Record<string, CreatureDoc[]> = {};
  for (const u of uids) out[u] = (await env.svc.registerPlayer(u, { ageBand: "18plus" })).starters;
  env.days(8);
  return out;
}

export async function rejects(p: Promise<unknown>, reason: string) {
  await assert.rejects(p, (e: any) => {
    assert.equal(e?.name, "DomainError", String(e));
    assert.equal(e.reason, reason);
    return true;
  });
}
