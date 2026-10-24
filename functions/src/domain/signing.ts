// Creature signature (genome-spec §7.4 "signed at birth"). Uses node:crypto only (no Firebase).
import { createHmac, timingSafeEqual } from "node:crypto";

export function hmacSigner(secret: string): (payload: string) => string {
  if (secret.length < 16) throw new Error("signing secret too short");
  return (payload) => createHmac("sha256", secret).update(payload, "utf8").digest("base64url");
}

export function verifySig(secret: string, payload: string, sig: string): boolean {
  const want = Buffer.from(hmacSigner(secret)(payload));
  const got = Buffer.from(sig);
  return want.length === got.length && timingSafeEqual(want, got);
}
