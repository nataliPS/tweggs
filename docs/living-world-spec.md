# Tweggs — Living World Spec v0.1 (approved 2026-10-24)

The creature reacts to the real world. All features are optional, privacy-first and never punish.

## 1. Weather (MVP)
- Source: Apple WeatherKit (500k calls/month included; attribution "Weather" + legal link required). Fetch at most every 3 h per device (BGAppRefresh + on app open); cache in App Group so the widget reads cached state only.
- Location: approximate (city-level) with permission; never stored server-side; fallback = city chosen manually; no permission = neutral weather.
- States → visuals → care item:
  | Weather | Creature | Care item (cosmetic, kept in collection) |
  |---|---|---|
  | rain / drizzle | droplets, wet sheen, sad ears | umbrella |
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
- Reward: "Early bird" streak and a small spark gift when the alarm is stopped on time; never punish snoozing.
- Permission: AlarmKit authorization requested only when the user enables the feature.

## 8. Boredom quests & mini-games (MVP)
- Trigger: joy below ~40 (or random 1×/day) → bubble "I'm bored…" + suggested activity. Never a penalty if ignored.
- Jump rope (first mini-game): player taps in rhythm, creature jumps; rope speed ramps; combo counter; 20–40 s session; rewards: joy +, sparks by combo (capped/day), personal best, optional 6 s share clip. The rope becomes a collection item.
- Next mini-games on the same framework: catch the ball, hide-and-seek, grow a flower.

## 9. Pair life — "their own world" (MVP core; more scenes in Beta)
- Two creatures (both yours, or yours + a visiting friend's creature once trade/visits exist) share a tiny house.
- While the phone is idle they "live": scenes drawn from a deterministic schedule seeded by `fnv1a32(pairId|day)`: painting, chess, chatting (speech bubbles with emotes), pillow fort, napping together, cooking, stargazing at night (uses local time & weather).
- Lock Screen / Home widget: a timeline of upcoming scene entries (e.g. every 30–60 min for 12 h) so on unlock the user sees what they are doing now. Static frames; no background execution is needed or possible.
- App open → "While you were away" diary: short entries computed from elapsed time ("Lilo and Zephyr played chess — Zephyr won", "They painted a picture").
- Paintings (Beta): procedural pixel artwork generated from the pair's palettes + seed, saved to a Gallery (collectible, shareable as an image).
- Chess result, chat lines and diary text come from templates (+ optional on-device AI lines within the §2 guardrails).
