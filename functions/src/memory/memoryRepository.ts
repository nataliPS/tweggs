// In-memory Repository for tests and local runs. Mirrors Firestore transaction semantics:
// reads-before-writes enforced, writes buffered and applied atomically on success, nothing on throw.
// Transactions are serialized (a simple mutex) so concurrent calls behave like Firestore retries.

import type { Repository, Tx } from "../domain/repository.ts";
import type { BreedDoc, ComboDoc, CreatureDoc, OfferDoc, PlayerDoc } from "../domain/types.ts";

type Coll = "players" | "creatures" | "offers" | "breeds" | "combos";

const clone = <T>(v: T): T => structuredClone(v);

export class MemoryRepository implements Repository {
  readonly data: Record<Coll, Map<string, unknown>> = {
    players: new Map(),
    creatures: new Map(),
    offers: new Map(),
    breeds: new Map(),
    combos: new Map(),
  };
  /** Client-created social docs (reports, blocks) keyed by author uid. */
  readonly social = new Map<string, unknown[]>();
  transactions = 0;
  private queue: Promise<unknown> = Promise.resolve();

  async runTransaction<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    const run = this.queue.then(() => this.exec(fn));
    this.queue = run.catch(() => undefined);
    return run;
  }

  async purgeSocial(uid: string): Promise<void> {
    this.social.delete(uid);
  }

  private async exec<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    this.transactions++;
    const writes: { coll: Coll; id: string; doc: unknown | null }[] = [];
    const data = this.data;
    const read = <D>(coll: Coll, id: string): D | null => {
      if (writes.length > 0) throw new Error("transaction: read after write");
      const v = data[coll].get(id);
      return v === undefined ? null : clone(v as D);
    };
    const scan = <D>(coll: Coll, pred: (d: D) => boolean, limit: number, order?: (a: D, b: D) => number): D[] => {
      if (writes.length > 0) throw new Error("transaction: read after write");
      let out = [...data[coll].values()].map((v) => v as D).filter(pred);
      if (order) out = out.sort(order);
      return out.slice(0, limit).map(clone);
    };
    const write = (coll: Coll, id: string, doc: unknown | null) => writes.push({ coll, id, doc: doc === null ? null : clone(doc) });

    const tx: Tx = {
      getPlayer: async (uid) => read<PlayerDoc>("players", uid),
      getCreature: async (id) => read<CreatureDoc>("creatures", id),
      getOffer: async (id) => read<OfferDoc>("offers", id),
      getBreed: async (id) => read<BreedDoc>("breeds", id),
      getCombo: async (k) => read<ComboDoc>("combos", k),
      creaturesByOwner: async (uid, n) => scan<CreatureDoc>("creatures", (c) => c.ownerUid === uid, n),
      offersByCreator: async (uid, n) => scan<OfferDoc>("offers", (o) => o.creatorUid === uid, n),
      breedsByAcceptor: async (uid, n) => scan<BreedDoc>("breeds", (b) => b.acceptorUid === uid, n),
      breedsByOffer: async (id, n) => scan<BreedDoc>("breeds", (b) => b.offerId === id, n),
      combosByDiscoverer: async (uid, n) => scan<ComboDoc>("combos", (c) => c.discovererUid === uid, n),
      openOffersExpiredBy: async (t, n) =>
        scan<OfferDoc>("offers", (o) => o.status === "open" && o.expiresAt <= t, n, (a, b) => a.expiresAt - b.expiresAt),
      previewsCreatedBy: async (t, n) =>
        scan<BreedDoc>("breeds", (b) => b.status === "preview" && b.createdAt <= t, n, (a, b) => a.createdAt - b.createdAt),
      setPlayer: (d) => write("players", d.uid, d),
      setCreature: (d) => write("creatures", d.id, d),
      setOffer: (d) => write("offers", d.id, d),
      setBreed: (d) => write("breeds", d.id, d),
      setCombo: (d) => write("combos", d.comboKey, d),
      deletePlayer: (id) => write("players", id, null),
      deleteCreature: (id) => write("creatures", id, null),
      deleteOffer: (id) => write("offers", id, null),
      deleteBreed: (id) => write("breeds", id, null),
    };

    const result = await fn(tx);
    for (const w of writes) {
      if (w.doc === null) data[w.coll].delete(w.id);
      else data[w.coll].set(w.id, w.doc);
    }
    return clone(result);
  }

  // Test helpers
  get<D>(coll: Coll, id: string): D | undefined {
    const v = this.data[coll].get(id);
    return v === undefined ? undefined : clone(v as D);
  }
  all<D>(coll: Coll): D[] {
    return [...this.data[coll].values()].map((v) => clone(v as D));
  }
  /** Direct write that bypasses services (fixtures only). */
  put(coll: Coll, id: string, doc: unknown): void {
    this.data[coll].set(id, clone(doc));
  }
}
