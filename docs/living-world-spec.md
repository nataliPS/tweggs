# Tweggs — Living World Spec v0.1 (approved 2026-10-24)

The creature reacts to the real world. All features are optional, privacy-first and never punish.

## 0. Cross-cutting rules (debrief 2026-10-24, approved)
- One **activity state machine** decides what the creature does now, by priority: focus → night → weather → pair scene → daily routine.
- One **line service** (templates; on-device AI when available) for talk, diary and chat bubbles, with one set of guardrails and filters.
- One **daily spark cap** across all new earning sources (weather items, souvenirs, mini-games, alarm, visits).
- Care items are always earnable for free; never Club-only.
- Stage split: MVP = weather, template lines (AI on iOS 26 devices), jump rope (no clip), pair life of your own two creatures + diary, local holidays, widget tap reactions, daily routine scenes, gene-based likes. Beta = AlarmKit wake-up, pedometer walks (CMPedometer, HealthKit later), paintings, birthday, Focus filter, mini-game clip, friends graph → visits → Duo → Crew. Later = AI diary/visit stories, Remote Config holidays, HealthKit.

## 1. Weather (MVP)
- Source: Apple WeatherKit (500k calls/month included; attribution "Weather" + legal link required). Fetch at most every 3 h per device (BGAppRefresh + on app open); cache in App Group so the widget reads cached state only.
- Location: approximate (city-level) with permission; never stored server-side; fallback = city chosen manually; no permission = neutral weather.
- States → visuals → care item:
  | Weather | Creature | Care item (cosmetic, kept in collection) |
  |---|---|---|
  | rain / drizzle | droplets, wet sheen, happily splashing in puddles (cosy, never sad) | umbrella |
  | heat ≥ 28 °C / strong UV | sweat drop, squint | water bottle, fan, sun hat |
  | snow / ≤ 0 °C | snowflakes, shiver frame | scarf, beanie |
  | wind ≥ 30 km/h | ears & tail blown | — |
  | night (local sunset→sunrise) | sleeping frame in widget | blanket (optional) |
- Giving the right item: +joy and a small spark reward once per weather event; not giving it never harms (no penalty).

## 2. Talk, tips and support (MVP)
- One-way short lines (≤ 80 chars), generated on-device (Apple Foundation Models) with template fallback; shown in speech bubble, widget and occasional notification (≤ 2/day total notifications).
- Categories: self-care nudges (water, sleep, screen break, stretch), encouragement ("You showed up today"), weather comments, personality banter by `temper`.
- Guardrails: no open chat / free-text input; no medical, mental-health, diet or relationship advice; no guilt ("I'm sad you left") — positive only; crisis words never appear; label "Lines written by on-device AI"; nothing personal sent off device.

## 3. Walks with steps (Beta)
- HealthKit step count (read-only, permission, optional) or device pedometer; every 2,000 steps the creature "brings back" a souvenir (sparks/cosmetic). Health data never used for ads, never leaves device.

## 4. Holidays & seasons (Beta)
- Calendar of events with decorations and limited cosmetics (free to earn): Halloween, Christmas/New Year, Valentine's, spring, Ukraine's Independence Day (vyshyvanka), plus local-calendar variants. Server-driven dates (Remote Config) later; local table now.

## 5. Creature birthday (post-launch)
- Yearly on hatch date: party frame, small gift, card variant.

## 6. Focus mode (post-launch)
- iOS Focus filter / manual "Do not disturb" toggle: creature is "busy studying/working", no nudges; afterwards a happy greeting and small reward. Screen Time API not required.

## Art needed (Піксель)
umbrella, water bottle, fan, sun hat, scarf, beanie, blanket; wet / sweat / shiver / sleep / wind-blown frames; holiday decorations; birthday hat.

## 7. Morning wake-up with the creature's voice (MVP stretch → Beta)
- iOS does not let apps read or hook into alarms set in the system Clock app. So the user sets the wake time INSIDE Tweggs ("Ранок з Tweggs").
- Implementation (rational, approved 2026-10-24): ONE real alarm only — the main alarm via AlarmKit (iOS 26+; rings through silent mode/Focus, Live Activity with the creature waking up, snooze). The pre-alarm is a gentle time-sensitive local notification with the creature's soft voice clip ("Good morning… let's start waking up"), not a second alarm.
- Pre-alarm offset: off / 1 / 2 / 5 min, default 2. Skipped automatically if the user already opened the app or dismissed the alarm that morning. In silent mode it arrives quietly; the main alarm does the waking.
- Voice: one short bundled clip (< 30 s, .caf) per temperament × language (en, uk) for the pre-alarm and one melody+voice clip for the main alarm, recorded or generated at build time; custom sounds must ship in the app bundle (per developer reports). No personalised name in audio for now.
- iOS 17–25 fallback: time-sensitive local notification with the creature sound (does not ring in silent mode — say so in the UI).
- Reward: "Early mornings" total counter (never resets) and a small spark gift when the alarm is stopped on time; never punish snoozing.
- Permission: AlarmKit authorization requested only when the user enables the feature.

## 8. Boredom quests & mini-games (MVP)
- Trigger (revised): random moments, max 2×/day → bubble "I have an idea!" + suggested activity (no hidden joy drain). Never a penalty if ignored.
- Jump rope (first mini-game): player taps in rhythm, creature jumps; rope speed ramps; combo counter; 20–40 s session; rewards: joy +, sparks by combo (capped/day), personal best, optional 6 s share clip. The rope becomes a collection item.
- Next mini-games on the same framework: catch the ball, hide-and-seek, grow a flower.

## 9. Pair life — "their own world" (MVP core; more scenes in Beta)
- Two creatures (both yours, or yours + a visiting friend's creature once trade/visits exist) share a tiny house.
- While the phone is idle they "live": scenes drawn from a deterministic schedule seeded by `fnv1a32(pairId|day)`: painting, chess, chatting (speech bubbles with emotes), pillow fort, napping together, cooking, stargazing at night (uses local time & weather).
- Lock Screen / Home widget: a timeline of upcoming scene entries (e.g. every 30–60 min for 12 h) so on unlock the user sees what they are doing now. Static frames; no background execution is needed or possible.
- App open → "While you were away" diary: short entries computed from elapsed time ("Lilo and Zephyr played chess — Zephyr won", "They painted a picture").
- Paintings (Beta): procedural pixel artwork generated from the pair's palettes + seed, saved to a Gallery (collectible, shareable as an image).
- Chess result, chat lines and diary text come from templates (+ optional on-device AI lines within the §2 guardrails).

## 10. Visits — "Away at a friend's" (Beta, needs server)
- Send one of your creatures to a friend (link/friends list) for 1–3 days. It appears in the friend's house next to their creature; pair-life scenes include it; the friend sees it on their Lock Screen/widget.
- Guaranteed return: auto-return at the chosen time; owner can recall anytime; host cannot keep, rename, breed or trade a visitor. Permanent giving only via explicit mutual "Trade".
- On return: diary "My visit to <friend>" (templated + guarded AI lines), a souvenir and possibly a jointly painted picture for the Gallery; friendship level between the two creatures rises; suggestion "They became friends — breed them?".
- Server: `visits/{id}` {visitorCreatureId, ownerUid, hostUid, start, end, status}; functions `startVisit`, `recallVisit`, scheduled `endVisits`; the visitor's genome is shown read-only on the host device.
- Safety: friends only, emoji-only interactions, block/report, no personal data in stories, under-13 offline mode excludes visits.


## 11. Duo mode (Beta, after friends graph) — approved
- Wholesome shared world for two players (couples OR best friends). Label "Duo"; under-16 framing "Best friends"; no romantic/sexual content.
- Mutual-consent link via invite between existing friends only (no strangers/matching). Gated by age band.
- Shared house shown on both widgets; each partner decorates own slots (owner pips); "Decorated together" two-tone wallpaper.
- Duo creature: each partner gives one parent; co-owned; grows like any creature (no shared upkeep).
- "Morning wave": each taps once a day; both waved → duo dance; one → wave back. Counter "days we both waved" never resets.
- Anniversaries: day 7/30/100/365 + hatch day → party frame, free cosmetic, plaque.
- Care relay feed ("Alex gave Pip an umbrella"), fridge notes from emote + pixel-prop combos (max 3/day, no free text).
- RED LINES: no location/weather/time zone of partner, no online/last-seen/opened-app status, no read receipts, no steps/wake data sharing, no relationship score, no jealousy or guilt, no shared streak that dies; AI never comments on the partner.
- Unlink: one-sided, quiet (no "X left you"), cooldown on re-link, block/report in the same place; each keeps own creatures, duo creature becomes twins (one each), shared paintings copied, items return to origin; house saved to Gallery as a memory.

## 12. Crew mode (Beta) — approved
- 3–5 friends; big house with a room each; crew mascot from a gene relay (each donates one gene, deterministic); roll call with emotes; group scenes (band, picnic, sleepover); shared crew painting with a layer each; leavers keep a copy of the mascot.

## 13. New "alive" ideas (approved)
| Idea | Stage |
|---|---|
| Widget tap reactions (pat, poke, feed) | MVP |
| Daily routine scenes (breakfast, backpack, homework, dinner) | MVP |
| Likes & dislikes from genes ("loves rain, hates wind") | MVP |
| Charging = snack time; Low Power Mode = blanket nap | MVP |
| First unlock of the day: stretch + "Morning!" (umbrella by the door if rain) | MVP |
| Real sky in the window (moon phase, golden hour) | Beta |
| Day-of-week moods (sleepy Monday, Friday dance) | Beta |
| Lock Screen pokes / hugs to a friend (max 3/day) | Beta |
| Guest-book stamp from visitors; painting exchange | Beta |
| Weekly "Wrapped" share card | Beta |
| Memory jar (first snow, first friend, first visit) resurfacing on anniversaries | Beta |
| Personal chirp + haptic from genes | Later |
| Duo jump rope; morning link with a friend | Later |
| Dynamic Island peek / study buddy | Later |
