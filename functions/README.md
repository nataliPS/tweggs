# Mixlings backend (Cloud Functions)

Implements `docs/backend-spec.md` and `docs/genome-spec.md` §7. This is development mode: everything runs locally, and nothing is deployed.

## Layout

```
src/domain/       pure business logic (depends only on engine-ts + the Repository port)
  engine.ts       the only import of the engine: re-exports ../../engine-ts/src/index.ts
  services.ts     registerPlayer, createOffer, cancelOffer, previewBreed, commitBreed,
                  claimDailySurprise, checkInStreak, renameCreature, deleteAccount, sweep
  repository.ts   Repository / Tx interface (Firestore-style transactions)
  config.ts       caps, TTLs, growth timings, starters, streak unlock table
  nameFilter.ts   creature name filter (retro C3)
  growth.ts, time.ts, signing.ts, types.ts, errors.ts
src/memory/       in-memory Repository (tests, local runs)
src/firebase/     thin adapters, written but NOT executed yet
  main.ts         onCall / onSchedule wrappers
  firestoreRepository.ts, codec.ts (flattens genomes: Firestore forbids nested arrays)
test/             node:test suites
firestore.rules, firestore.indexes.json, firebase.json
```

## Run the tests locally

Node 22.18 or newer runs `.ts` files natively. No `npm install` is needed for the tests:

```sh
cd functions
npm test              # = node --test test/*.test.ts
cd ../engine-ts && npm test   # the engine the functions import
```

Type-check (needs `npm install` for `@types/node` and the firebase typings): `npm run typecheck`.

## Key rules that the code enforces

- Previews are bound and single-use. The breed doc id is `hash(offerId, myCreatureId)`. Repeating a preview returns the same nonce and child, and it does not count against the cap.
- Caps: 10 new previews and 20 offers per player per server UTC day.
- Genomes and mutations are read only from the server records. The server ignores any genome or mutation list that the client sends.
- Commit runs as one transaction. It recomputes the result with the stored nonce, creates both twins, sets serial = `combos.count + 1`, sets the discoverer only if empty, marks the offer as used, and burns the sibling previews. A retry is idempotent.
- Teens and adults can breed (retro G4). Under-13 accounts get no social calls (C2).
- Streak unlocks are the `STREAK_UNLOCKS` table in `config.ts` (days 3/7/14/21/30). Unlocks are permanent.

## Deploy (later, founder approval required)

Do not run any of these steps without explicit approval from the founder.

1. Create a Firebase project. Enable Auth (Anonymous, then Sign in with Apple), Firestore and App Check.
2. `npm install` in `functions/`.
3. `firebase functions:secrets:set CREATURE_SIG_KEY` (32+ random bytes).
4. Run the local emulator first: `npm run serve`.
5. `firebase deploy --only firestore:rules,firestore:indexes,functions`. `predeploy` runs the engine-ts and functions tests plus the build. CI must be green, including the golden check.
6. Set a $25/month budget alert.
