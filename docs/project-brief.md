# Mixlings — project brief for team reviews (Oct 24, 2026)

Studio: Orizo Labs (founder Denys + Claude as project lead + AI agent team). iOS-first, closed-access project.

## Product
Pixel creatures (32×32, procedural from 8 genes) live in iOS widgets / Lock Screen. Friends breed them via a shared link → both get twin eggs → unique hybrid, previewed before confirming. Nothing dies. Rated 13+. English-first, Ukrainian second. No ads, no paid randomness.

## Pillars
1 Never punishes · 2 Every creature unique · 3 Better with friends · 4 30 seconds is enough · 5 Honest money.

## Key systems (see Claude Doc design document; repo docs/)
- Genetics: 8 genes, diploid, dominance, deterministic breeding (server nonce), mutations unlocked by streaks/biomes/events (all free), rarity tiers by score. Spec: docs/genome-spec.md.
- Growth egg→baby(day1)→teen(day3)→adult(day7); starter adult given at onboarding so day-1 breeding works.
- Social: breed link via any messenger, deferred deep link, 72h expiry, emoji-only, block/report, no shared failure.
- Economy: soft currency "sparks" (earned only). Mix Club subscription $3.99/mo or $24.99/yr, 7-day trial: 30 slots vs 6 (+unlimited free "sanctuary"), all widget sizes/themes, seasonal palettes, extended personality lines, decorative biome variants. Same breeding/mutation odds for all. Cosmetic one-offs $0.99–2.99.
- Collecting (approved today, from Pokémon TCG analysis): Creature Card (shareable, rarity frame, generation, serial number), Seasonal collections (12 genes/season, album, badge), Discoverer (first in world to breed a combo), Daily free surprise, Friend trade (beta), physical fixed-set cards with QR later.
- Tech: SwiftUI app + WidgetKit + Live Activities (hatch timer only), MixlingsKit (Genome + Art, pixel-exact with TS/Python), Firebase (Auth, Firestore, Functions validates breeding & server-time streaks), RevenueCat, Apple on-device model for personality lines (template fallback), XcodeGen + Xcode Cloud → TestFlight.
- Gates: A TikTok reach (2/15 videos >10k views, 300+ waitlist) · B prototype (median 2+ breed links per active player/week) · C beta (D1 35%, D7 12%, D30 trend 5%, k ≥0.3) · D soft launch (D30 6%+, pay 2.3%+, crash-free 99.5%).
- Roadmap: Stage 0 design (done) → Stage 1 TikTok test + prototype (Nov 2–15) → Stage 2 MVP 6 sprints (to Feb 7) → Stage 3 beta 5 weeks → Stage 4 soft launch (Mar 15–Apr 30 2027) → Stage 5 global (May 2027).

## Repo layout (/home/claude/mixlings)
docs/ · engine-ts/ (reference engine, tests) · MixlingsKit/ (Swift) · art/ (Python renderer + golden) · App/ (iOS app source, XcodeGen) · design/ (mockup .dc.html + assets) · marketing/tiktok-test-plan.md

## Blockers
Private GitHub repo + personal Apple Developer account pending (founder). No Swift compiler in the cloud workspace.
