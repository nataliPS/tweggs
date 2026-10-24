// Storage port. Domain services depend only on this interface (+ engine-ts).
// Implementations: src/memory/memoryRepository.ts (tests), src/firebase/firestoreRepository.ts (prod).
//
// Contract (mirrors Firestore transactions): inside one transaction ALL reads happen
// before ANY write; writes become visible atomically when the callback resolves;
// if it throws, nothing is written. The memory implementation enforces read-before-write.

import type { BreedDoc, ComboDoc, CreatureDoc, OfferDoc, PlayerDoc } from "./types.ts";

export interface Tx {
  getPlayer(uid: string): Promise<PlayerDoc | null>;
  getCreature(id: string): Promise<CreatureDoc | null>;
  getOffer(id: string): Promise<OfferDoc | null>;
  getBreed(id: string): Promise<BreedDoc | null>;
  getCombo(comboKey: string): Promise<ComboDoc | null>;

  creaturesByOwner(uid: string, limit: number): Promise<CreatureDoc[]>;
  offersByCreator(uid: string, limit: number): Promise<OfferDoc[]>;
  breedsByAcceptor(uid: string, limit: number): Promise<BreedDoc[]>;
  breedsByOffer(offerId: string, limit: number): Promise<BreedDoc[]>;
  combosByDiscoverer(uid: string, limit: number): Promise<ComboDoc[]>;
  /** status == "open" && expiresAt <= now, oldest first. */
  openOffersExpiredBy(now: number, limit: number): Promise<OfferDoc[]>;
  /** status == "preview" && createdAt <= before, oldest first. */
  previewsCreatedBy(before: number, limit: number): Promise<BreedDoc[]>;

  setPlayer(doc: PlayerDoc): void;
  setCreature(doc: CreatureDoc): void;
  setOffer(doc: OfferDoc): void;
  setBreed(doc: BreedDoc): void;
  setCombo(doc: ComboDoc): void;

  deletePlayer(uid: string): void;
  deleteCreature(id: string): void;
  deleteOffer(id: string): void;
  deleteBreed(id: string): void;

  // Generic path-addressed docs (friends graph collections; see social.ts for the paths).
  // Paths are Firestore paths ("visits/v1", "friends/a/list/b"). Creatures still go through setCreature.
  getDoc<T>(path: string): Promise<T | null>;
  /** Docs directly in `collectionPath` matching all clauses; optional ascending orderBy. */
  queryDocs<T>(collectionPath: string, where: readonly Where[], limit: number, orderBy?: string): Promise<T[]>;
  setDoc(path: string, doc: object): void;
  deleteDoc(path: string): void;
}

export interface Where {
  field: string;
  op: "==" | "<=" | "array-contains";
  value: string | number | boolean | null;
}

export interface Repository {
  runTransaction<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
  /** Deletes client-created social docs of `uid`: reports by uid and blocks/{uid}/list/*. Idempotent. */
  purgeSocial(uid: string): Promise<void>;
}

/** Max docs touched per transaction in bulk jobs (Firestore limit is 500 writes). */
export const BULK_CHUNK = 100;
