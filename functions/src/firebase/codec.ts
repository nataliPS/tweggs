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

/**
 * Friends-graph docs (social.ts) hold no genomes. Firestore drops `undefined` and rejects nested
 * arrays, so the codec strips undefined and asserts the no-nested-array rule at write time.
 */
export const genericCodec = {
  toStored: (d: object): Record<string, unknown> => {
    const walk = (v: unknown, inArray: boolean): unknown => {
      if (Array.isArray(v)) {
        if (inArray) throw new Error("nested array in Firestore doc");
        return v.map((x) => walk(x, true));
      }
      if (v !== null && typeof v === "object") {
        return Object.fromEntries(Object.entries(v).filter(([, x]) => x !== undefined).map(([k, x]) => [k, walk(x, false)]));
      }
      return v;
    };
    return walk(d, false) as Record<string, unknown>;
  },
  fromStored: (d: Record<string, unknown>): Record<string, unknown> => d,
};
