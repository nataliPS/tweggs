// In-memory Repository for tests and local runs. Mirrors Firestore transaction semantics:
// reads-before-writes enforced, writes buffered and applied atomically on success, nothing on throw.
// Transactions are serialized (a simple mutex) so concurrent calls behave like Firestore retries.

import type { Repository, Tx, Where } from "../domain/repository.ts";
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
  /** Path-addressed docs (friends graph): "visits/v1", "friends/a/list/b", "blocks/a/list/b", ... */
  readonly docs = new Map<string, unknown>();
  transactions = 0;
  private queue: Promise<unknown> = Promise.resolve();

  async runTransaction<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    const run = this.queue.then(() => this.exec(fn));
    this.queue = run.catch(() => undefined);
    return run;
  }

  async purgeSocial(uid: string): Promise<void> {
    this.social.delete(uid);
    for (const k of [...this.docs.keys()]) if (k.startsWith(`blocks/${uid}/`)) this.docs.delete(k);
  }

  private async exec<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    this.transactions++;
    const writes: { coll: Coll | null; id: string; doc: unknown | null }[] = [];
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
    const write = (coll: Coll | null, id: string, doc: unknown | null) => writes.push({ coll, id, doc: doc === null ? null : clone(doc) });
    const docs = this.docs;
    const checkPath = (path: string, docPath: boolean) => {
      const parts = path.split("/");
      if (parts.some((x) => x.length === 0) || (parts.length % 2 === 0) !== docPath) throw new Error(`bad path ${path}`);
    };
    const matches = (d: Record<string, unknown>, w: Where) => {
      const v = d[w.field];
      if (w.op === "==") return v === w.value;
      if (w.op === "<=") return typeof v === "number" && typeof w.value === "number" && v <= w.value;
      return Array.isArray(v) && v.includes(w.value);
    };

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
      getDoc: async <D>(path: string) => {
        if (writes.length > 0) throw new Error("transaction: read after write");
        checkPath(path, true);
        const v = docs.get(path);
        return v === undefined ? null : clone(v as D);
      },
      queryDocs: async <D>(coll: string, where: readonly Where[], limit: number, orderBy?: string) => {
        if (writes.length > 0) throw new Error("transaction: read after write");
        checkPath(coll, false);
        const depth = coll.split("/").length + 1;
        let out = [...docs.entries()]
          .filter(([k]) => k.startsWith(coll + "/") && k.split("/").length === depth)
          .map(([, v]) => v as Record<string, unknown>)
          .filter((d) => where.every((w) => matches(d, w)));
        if (orderBy) out = out.sort((a, b) => (a[orderBy] as number) - (b[orderBy] as number));
        return out.slice(0, limit).map((d) => clone(d as D));
      },
      setDoc: (path, d) => {
        checkPath(path, true);
        write(null, path, d);
      },
      deleteDoc: (path) => {
        checkPath(path, true);
        write(null, path, null);
      },
    };

    const result = await fn(tx);
    for (const w of writes) {
      const m = w.coll === null ? docs : data[w.coll];
      if (w.doc === null) m.delete(w.id);
      else m.set(w.id, w.doc);
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
  doc<D>(path: string): D | undefined {
    const v = this.docs.get(path);
    return v === undefined ? undefined : clone(v as D);
  }
  /** Docs whose path starts with `prefix`. */
  docsUnder<D>(prefix: string): D[] {
    return [...this.docs.entries()].filter(([k]) => k.startsWith(prefix)).map(([, v]) => clone(v as D));
  }
  /** Direct write that bypasses services (fixtures only). */
  put(coll: Coll, id: string, doc: unknown): void {
    this.data[coll].set(id, clone(doc));
  }
}
