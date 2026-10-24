import { ADULT_AFTER_HATCH_MS, HATCH_AFTER_MS, TEEN_AFTER_HATCH_MS } from "./config.ts";
import type { CreatureDoc } from "./types.ts";

export const STAGES = ["egg", "baby", "teen", "adult"] as const;
export type Stage = (typeof STAGES)[number];

/** Mirrors CareEngine.stage (App/Shared/Engine/CareEngine.swift), computed on server time. */
export function stageOf(c: Pick<CreatureDoc, "bornAt" | "hatchedAt">, now: number): Stage {
  const hatch = c.hatchedAt ?? c.bornAt + HATCH_AFTER_MS;
  if (now < hatch) return "egg";
  const age = now - hatch;
  if (age >= ADULT_AFTER_HATCH_MS) return "adult";
  if (age >= TEEN_AFTER_HATCH_MS) return "teen";
  return "baby";
}

export function atLeast(stage: Stage, min: Stage): boolean {
  return STAGES.indexOf(stage) >= STAGES.indexOf(min);
}
