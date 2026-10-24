// Firebase entry point: thin onCall / onSchedule wrappers over the pure domain services.
// NOT executed in dev mode (dependencies are not installed). Deploy is a later step that needs
// founder approval (see functions/README.md).

import { randomUUID } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall, type CallableRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";

import { DomainError } from "../domain/errors.ts";
import { createServices, type Services } from "../domain/services.ts";
import { hmacSigner } from "../domain/signing.ts";
import { FirestoreRepository } from "./firestoreRepository.ts";

initializeApp();
const db = getFirestore();
const repo = new FirestoreRepository(db);

/** Creature signing key (Secret Manager). Set with `firebase functions:secrets:set CREATURE_SIG_KEY`. */
const SIG_KEY = defineSecret("CREATURE_SIG_KEY");

let services: Services | null = null;
function svc(): Services {
  services ??= createServices({
    repo,
    now: () => Date.now(),
    randomToken: () => randomUUID(),
    sign: hmacSigner(SIG_KEY.value()),
  });
  return services;
}

const OPTS = { region: "europe-west1", enforceAppCheck: true, secrets: [SIG_KEY], memory: "256MiB" as const };

function callable<T>(fn: (uid: string | undefined, data: any) => Promise<T>) {
  return onCall(OPTS, async (req: CallableRequest) => {
    if (!req.auth) throw new HttpsError("unauthenticated", "no-auth");
    try {
      return await fn(req.auth.uid, req.data ?? {});
    } catch (e) {
      if (e instanceof DomainError) throw new HttpsError(e.code, e.reason, { reason: e.reason });
      logger.error("callable failed", e);
      throw new HttpsError("internal", "internal");
    }
  });
}

export const registerPlayer = callable((uid, d) => svc().registerPlayer(uid, { ageBand: d.ageBand, displayName: d.displayName }));
export const createOffer = callable((uid, d) => svc().createOffer(uid, { parentCreatureId: d.parentCreatureId }));
export const cancelOffer = callable((uid, d) => svc().cancelOffer(uid, { offerId: d.offerId }));
export const previewBreed = callable((uid, d) => svc().previewBreed(uid, { offerId: d.offerId, myCreatureId: d.myCreatureId }));
export const commitBreed = callable((uid, d) => svc().commitBreed(uid, { breedId: d.breedId }));
export const claimDailySurprise = callable((uid) => svc().claimDailySurprise(uid));
export const checkInStreak = callable((uid) => svc().checkInStreak(uid));
export const renameCreature = callable((uid, d) => svc().renameCreature(uid, { id: d.id, name: d.name }));

/** Apple 5.1.1(v): deletes all docs first, then the Auth user (so a retry can still authenticate). */
export const deleteAccount = callable(async (uid) => {
  const result = await svc().deleteAccount(uid);
  await getAuth().deleteUser(uid!);
  return result;
});

export const hourlySweep = onSchedule({ schedule: "every 60 minutes", region: OPTS.region, secrets: [SIG_KEY] }, async () => {
  const r = await svc().sweep();
  logger.info("sweep", r);
});
