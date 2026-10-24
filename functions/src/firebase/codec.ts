// Firestore encoding. Firestore rejects arrays that directly contain arrays, so genomes
// ([[a,b] x 8]) are stored flat as 16 ints: [g0a, g0b, g1a, g1b, ...]. Pure; unit-tested.

import type { Genome } from "../domain/engine.ts";
import type { BreedDoc, CreatureDoc } from "../domain/types.ts";

export function flattenGenome(g: Genome): number[] {
  return g.flatMap((p) => [p[0], p[1]]);
}

export function unflattenGenome(flat: readonly number[]): Genome {
  if (!Array.isArray(flat) || flat.length % 2 !== 0) throw new Error("bad stored genome");
  const out: Genome = [];
  for (let i = 0; i < flat.length; i += 2) out.push([flat[i], flat[i + 1]]);
  return out;
}

export const creatureCodec = {
  toStored: (c: CreatureDoc) => ({ ...c, genome: flattenGenome(c.genome) }),
  fromStored: (d: Record<string, unknown>): CreatureDoc => ({ ...(d as unknown as CreatureDoc), genome: unflattenGenome(d.genome as number[]) }),
};

export const breedCodec = {
  toStored: (b: BreedDoc) => ({ ...b, previewChild: { ...b.previewChild, genome: flattenGenome(b.previewChild.genome) } }),
  fromStored: (d: Record<string, unknown>): BreedDoc => {
    const b = d as unknown as BreedDoc;
    return { ...b, previewChild: { ...b.previewChild, genome: unflattenGenome(b.previewChild.genome as unknown as number[]) } };
  },
};
