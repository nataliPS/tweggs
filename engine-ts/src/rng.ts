// mulberry32 PRNG (spec §3). All state and outputs are UInt32.

export class Mulberry32 {
  private s: number;

  constructor(seed: number) {
    this.s = seed >>> 0;
  }

  /** Next UInt32. */
  next(): number {
    this.s = (this.s + 0x6d2b79f5) >>> 0;
    let t = this.s;
    t = Math.imul(t ^ (t >>> 15), t | 1) >>> 0;
    t = (t ^ ((t + Math.imul(t ^ (t >>> 7), t | 61)) >>> 0)) >>> 0;
    return (t ^ (t >>> 14)) >>> 0;
  }

  /** Float in [0, 1): next() / 2^32. */
  float(): number {
    return this.next() / 4294967296;
  }

  /** Integer in [0, n): next() % n. n must be a positive integer. */
  int(n: number): number {
    if (!Number.isInteger(n) || n <= 0) throw new RangeError(`int(n): n must be a positive integer, got ${n}`);
    return this.next() % n;
  }
}

export function mulberry32(seed: number): Mulberry32 {
  return new Mulberry32(seed);
}
