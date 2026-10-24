# Tweggs — Wellbeing module "Хвилинка спокою" v0.1 (approved 2026-10-24)

Light, native, never clinical. The creature is a calm companion, not a therapist.

## Principles
1. Native: lives inside the creature's world (breathing = the creature inflates/deflates), never a separate "mental health" app.
2. Opt-in and quiet: never pushed when the player is busy; ≤1 gentle offer per day, part of the global ≤2 notifications/day.
3. No clinical claims, no diagnosis, no AI in wellbeing flows (templates only, expert-reviewed).
4. No guilt, no streaks, no scores; nothing is lost by skipping.
5. Data stays on device; never shared with friends, Duo/Crew, server or analytics (only anonymous "feature opened" counts).
6. A real person (adolescent psychologist) signs off all content before Beta.

## Components
| Component | What | Stage |
|---|---|---|
| Breathe with me | Creature inflates/deflates; 4-4 or 4-6 rhythm; 1–2 min; haptic pulse optional | MVP |
| Grounding 5-4-3-2-1 | Creature asks for 5 things you see … 1 you taste; tap to advance (no typing) | MVP |
| "I'm having a hard time" button | Always reachable (Home menu, Settings, Calm screen): breathe → grounding → country helplines | MVP |
| Evening wind-down | Creature yawns, dims lights, one kind thought about the day; optional in evening routine | MVP |
| "How are you today?" | Optional 5-emoji check-in; creature reacts warmly and suggests one activity; history only on device, deletable | Beta (after review) |
| Gratitude jar | Pick a pebble from preset prompts ("a friend", "food", "music"…), no free text | Beta (after review) |

## Where it lives
- Home: "Хвилинка спокою" chip near the creature; Calm screen with the three MVP practices.
- Activity state machine: a "calm" activity (creature meditates) is a valid scene; after breathing, the creature shows a calm pose in the widget.
- Evening routine scene offers wind-down (opt-in).

## Crisis resources
- Static, offline table of helplines by country (UA, EE, LV, LT, PL, DE, UK, US, CA, AU + "find a helpline" fallback link), verified by Щит before each release; shown without judgement, no data collected.
- Under-13 offline mode still shows the button and helplines.

## Content pipeline
1. Баланс drafts scripts (en/uk) → 2. research note: evidence per practice → 3. Щит safety & legal review (no clinical claims, App Store 1.4.1 health framing) → 4. external psychologist review & sign-off (founder sources the expert) → 5. localization review → 6. ship. Every text has an id and a "reviewed by/date" field.

## Metrics (no engagement maximizing)
Opens per practice, completion rate, optional one-tap "feel a bit calmer? yes/no" after a practice (on-device aggregate only). Never tie rewards to wellbeing use (no sparks for breathing), so nobody "farms" calm.
