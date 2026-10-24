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
