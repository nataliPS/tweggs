// Firestore implementation of the domain Repository. NOT executed locally (firebase-admin is not
// installed in dev mode); behaviour is specified by src/memory/memoryRepository.ts + its tests.

import type { Firestore, Transaction, Query, DocumentReference } from "firebase-admin/firestore";
import type { Repository, Tx } from "../domain/repository.ts";
import { breedCodec, creatureCodec } from "./codec.ts";
import type { BreedDoc, ComboDoc, CreatureDoc, OfferDoc, PlayerDoc } from "../domain/types.ts";

const C = { players: "players", creatures: "creatures", offers: "offers", breeds: "breeds", combos: "combos" } as const;

export class FirestoreRepository implements Repository {
  private readonly db: Firestore;
  constructor(db: Firestore) {
    this.db = db;
  }

  runTransaction<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    return this.db.runTransaction((t) => fn(this.wrap(t)));
  }

  private wrap(t: Transaction): Tx {
    const db = this.db;
    const get = async <D>(ref: DocumentReference): Promise<D | null> => {
      const s = await t.get(ref);
      return s.exists ? (s.data() as D) : null;
    };
    const list = async <D>(q: Query): Promise<D[]> => (await t.get(q)).docs.map((d) => d.data() as D);
    const decC = (d: Record<string, unknown> | null) => (d ? creatureCodec.fromStored(d) : null);
    const decB = (d: Record<string, unknown> | null) => (d ? breedCodec.fromStored(d) : null);
    const ref = (coll: string, id: string) => db.collection(coll).doc(id);
    return {
      getPlayer: (uid) => get<PlayerDoc>(ref(C.players, uid)),
      getCreature: async (id) => decC(await get(ref(C.creatures, id))),
      getOffer: (id) => get<OfferDoc>(ref(C.offers, id)),
      getBreed: async (id) => decB(await get(ref(C.breeds, id))),
      getCombo: (k) => get<ComboDoc>(ref(C.combos, k)),
      creaturesByOwner: async (uid, n) =>
        (await list<Record<string, unknown>>(db.collection(C.creatures).where("ownerUid", "==", uid).limit(n))).map(creatureCodec.fromStored),
      offersByCreator: (uid, n) => list(db.collection(C.offers).where("creatorUid", "==", uid).limit(n)),
      breedsByAcceptor: async (uid, n) =>
        (await list<Record<string, unknown>>(db.collection(C.breeds).where("acceptorUid", "==", uid).limit(n))).map(breedCodec.fromStored),
      breedsByOffer: async (id, n) =>
        (await list<Record<string, unknown>>(db.collection(C.breeds).where("offerId", "==", id).limit(n))).map(breedCodec.fromStored),
      combosByDiscoverer: (uid, n) => list(db.collection(C.combos).where("discovererUid", "==", uid).limit(n)),
      openOffersExpiredBy: (now, n) =>
        list(db.collection(C.offers).where("status", "==", "open").where("expiresAt", "<=", now).orderBy("expiresAt").limit(n)),
      previewsCreatedBy: async (before, n) =>
        (await list<Record<string, unknown>>(db.collection(C.breeds).where("status", "==", "preview").where("createdAt", "<=", before).orderBy("createdAt").limit(n))).map(breedCodec.fromStored),
      // Creatures and breeds go through codec.ts (Firestore forbids nested arrays).
      setPlayer: (d) => void t.set(ref(C.players, d.uid), d),
      setCreature: (d) => void t.set(ref(C.creatures, d.id), creatureCodec.toStored(d)),
      setOffer: (d) => void t.set(ref(C.offers, d.id), d),
      setBreed: (d) => void t.set(ref(C.breeds, d.id), breedCodec.toStored(d)),
      setCombo: (d) => void t.set(ref(C.combos, d.comboKey), d),
      deletePlayer: (id) => void t.delete(ref(C.players, id)),
      deleteCreature: (id) => void t.delete(ref(C.creatures, id)),
      deleteOffer: (id) => void t.delete(ref(C.offers, id)),
      deleteBreed: (id) => void t.delete(ref(C.breeds, id)),
    };
  }

  async purgeSocial(uid: string): Promise<void> {
    const reports = await this.db.collection("reports").where("reporterUid", "==", uid).get();
    const writer = this.db.bulkWriter();
    reports.docs.forEach((d) => writer.delete(d.ref));
    await writer.close();
    await this.db.recursiveDelete(this.db.collection("blocks").doc(uid));
  }
}
