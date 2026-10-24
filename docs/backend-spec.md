# Mixlings — Backend Spec v0.1 (Stage 1 → MVP)

Firebase: Auth (Anonymous → upgrade to Sign in with Apple), Firestore, Cloud Functions (Node 22, TypeScript, imports `engine-ts` unchanged), App Check, Remote Config, Crashlytics/Analytics (app target only — never in the widget).

## Collections
| Path | Fields | Written by |
|---|---|---|
| `players/{uid}` | displayName, createdAt, ageBand, unlockedMutations[], streak{count,lastDayUTC}, limits{dayUTC, offers, previews}, sparks, lastSurpriseDayUTC | functions only (client reads own) |
| `creatures/{id}` | ownerUid, genome, generation, parentIds, comboKey, serial, discoveredFirst, specVersion, createdAt, sig | functions only |
| `offers/{offerId}` | creatorUid, parentCreatureId, expiresAt (+72h), status (open/used/expired/cancelled) | functions only |
| `breeds/{breedId}` | offerId, acceptorUid, acceptorCreatureId, nonce, previewChild, status (preview/committed/burned) | functions only |
| `combos/{comboKey}` | discovererUid, firstAt, count | functions only |
| `reports/{id}`, `blocks/{uid}/list/{blockedUid}` | reason, target, createdAt | client create (validated), functions read |

## Callable functions (App Check + Auth required)
- `registerPlayer(ageBand)` — creates player; persists starter genomes server-side (no re-derivation from a local id).
- `createOffer(parentCreatureId)` — adult (or teen, per balance rules) owned by caller; caps.
- `previewBreed(offerId, myCreatureId)` — single-use nonce per pair (spec §7), cap 10/day.
- `commitBreed(breedId)` — transaction: both twins, serial, discoverer.
- `claimDailySurprise()` — server UTC day, deterministic seed `surprise|uid|day`.
- `checkInStreak()` — server UTC; unlocks mutations.
- `deleteAccount()` — deletes Auth user + all their docs (Apple 5.1.1(v)).
- `renameCreature(id, name)` — profanity/PII filter (names reach friends).

## Scheduled
- hourly: expire offers, burn stale previews.

## Security rules
Clients read only their own `players/{uid}` and `creatures` where ownerUid == uid; all writes to creatures/offers/breeds/combos/players via functions.

## Offline policy
Care stats: local, last-write-wins. Breeding, serials, discoverer, streaks, season dates, daily surprise: server-owned; breeding queues offline and shows "hatching…" until confirmed.

## Cost guard
Widget never touches Firestore. Budget alert at $25/month. Target < $25/month at 10k DAU.

## Deploy
Functions deploy only after `engine-ts` golden tests pass in CI.


## Friends graph (prerequisite for visits, Duo, Crew) — Beta
| Path | Fields |
|---|---|
| `invites/{code}` | creatorUid, kind (friend/duo/crew), expiresAt (+24h), usedBy |
| `friends/{uid}/list/{friendUid}` | since, nickname? |
| `visits/{id}` | visitorCreatureId, ownerUid, hostUid, start, end, status |
| `duos/{id}` | members[2], status, createdAt; `duos/{id}/house/state` |
| `crews/{id}` | members[3..5], status; `crews/{id}/house/state` |
Functions: `createInvite`, `acceptInvite`, `removeFriend`, `startVisit`, `recallVisit`, scheduled `endVisits`, `unlinkDuo`, `leaveCrew`, `sendPoke` (≤3/day). Rules: members read their duo/crew docs and members' creatures read-only; house writes rules-validated per-slot (owner only); everything else via functions. Partners never receive location, status or activity data.
