// FNV-1a 32-bit over the UTF-8 bytes of a string (spec §3).

const FNV_OFFSET = 0x811c9dc5;
const FNV_PRIME = 0x01000193;
const encoder = new TextEncoder();

export function fnv1a32(input: string): number {
  const bytes = encoder.encode(input);
  let h = FNV_OFFSET;
  for (let i = 0; i < bytes.length; i++) {
    h ^= bytes[i];
    h = Math.imul(h, FNV_PRIME) >>> 0;
  }
  return h >>> 0;
}

/** 8-char lowercase hex, zero padded. */
export function hex8(n: number): string {
  return (n >>> 0).toString(16).padStart(8, "0");
}
