# Mixlings iOS app (Stage 1 prototype)

iOS 17+, SwiftUI, WidgetKit, App Intents. No third-party dependencies.
The Xcode project is **generated** from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not committed.

## Layout

```
App/
  project.yml              XcodeGen spec (targets, Info.plist keys, entitlements)
  Sources/                 app only: MixlingsApp, GameModel, Onboarding/Home/Collection/Breed views
  Shared/                  compiled into BOTH app and widget
    Model/Creature.swift       Creature, Stage, Condition, SaveData
    Engine/CareEngine.swift    pure care + growth rules (decay, feed/play/pet, egg→baby→teen→adult)
    Engine/CreatureFactory.swift  starter creatures via MixlingsGenome.starter
    Engine/PhenotypeMapper.swift  genome → MixlingsArt.Phenotype (the only file that builds Phenotype)
    Persistence/CreatureStore.swift  JSON save in the App Group container
    Intents/CareIntents.swift  Feed / Pet App Intents (widget buttons)
    UI/                        Theme, CreatureSprite (incl. lock-screen silhouette), EggView
    Resources/Localizable.xcstrings  en + uk
  MixlingsWidget/          widget extension (small, medium, accessoryCircular)
  Tests/                   CareEngine + phenotype mapping unit tests
  Resources/Assets.xcassets  app icon, accent colour
  ci_scripts/ci_post_clone.sh  Xcode Cloud: install XcodeGen + generate project
```

Depends on the local package `../MixlingsKit` (products `MixlingsGenome`, `MixlingsArt`).

## Generate and run on a Mac

Needs Xcode 16 or later (iOS 17 SDK or newer) and Homebrew.

```sh
brew install xcodegen
cd App
xcodegen generate          # writes Mixlings.xcodeproj (+ Generated/ plists & entitlements)
open Mixlings.xcodeproj
```

1. Select the **Mixlings** target, open **Signing & Capabilities**, and pick your team. You can also set `DEVELOPMENT_TEAM` in `project.yml` once, so every regeneration keeps it.
2. Do the same for **MixlingsWidget**. Both targets need the App Group `group.com.orizolabs.mixlings`. With automatic signing, Xcode registers it.
3. Run the **Mixlings** scheme on an iOS 17+ simulator or device. To test the widget, long-press the Home Screen, choose Edit, then Add Widget, and pick Mixlings.
4. Press ⌘U to run the tests.

Edit `project.yml` rather than the project, and run `xcodegen generate` again after you add or remove files.

**Deep-link testing** (the universal link needs the domain to be live):
```sh
xcrun simctl openurl booted "mixlings://b/test123"
```

**Associated domains:** `applinks:mix.orizolabs.app` is a placeholder. If signing complains before the domain and its `apple-app-site-association` file exist, remove that key from `project.yml`.

## Xcode Cloud → TestFlight

1. Commit and push the repo with `App/project.yml`, `App/ci_scripts/`, and `MixlingsKit/`. Do not commit `Mixlings.xcodeproj`, because `.gitignore` excludes it.
2. On a Mac, run `xcodegen generate` once and open the project. In Xcode, choose Product, then Xcode Cloud, then Create Workflow. Connect the Git repo and choose the **Mixlings** scheme.
3. In the workflow:
   - **Start condition:** branch changes on `main`.
   - **Actions:** add Archive for iOS with the Mixlings scheme. You can also add Test on an iOS 17+ simulator.
   - **Post-actions:** TestFlight Internal Testing, then pick a tester group.
4. In App Store Connect, create the app record (`com.orizolabs.mixlings`) and register the App Group and the widget bundle id (`com.orizolabs.mixlings.widget`) in Certificates, Identifiers & Profiles. Automatic signing on Xcode Cloud handles them once they exist.
5. Every build runs `ci_scripts/ci_post_clone.sh` after cloning. It installs XcodeGen with Homebrew and runs `xcodegen generate`, so the runner always builds a fresh project. Xcode Cloud finds `ci_scripts/` because it sits next to `Mixlings.xcodeproj`.

Build numbers: Xcode Cloud sets `CURRENT_PROJECT_VERSION` itself. Change `MARKETING_VERSION` in `project.yml`.

## Design notes

- **Mixlings never die.** Stats (belly, fun, mood, each 0 to 100) decay gently and stop at a floor of 10. At that floor the creature is "sleepy" but can still grow and recover.
- **Growth:** an egg hatches on day 1, becomes a teen on day 3 and an adult on day 7. The schedule is anchored on the hatch moment, so tapping to hatch early during onboarding moves the whole schedule forward.
- **Persistence (T4):** two JSON files in the App Group. `collection.json` holds the full save (app only). `active.json` holds just the active creature and egg timer for the widget, which reads nothing else; its Feed/Pet intents append care events (id + time) to `active.json`, and the app replays each event exactly once into the collection when it becomes active, then drops merged events. Writes are coordinated and atomic. The old `mixlings-save.json` moves to `collection.json` on first launch. SaveData is v3 and stores the starter genomes (T2).
- **Widget:** 25 entries, one every 30 minutes for 12 hours, all computed with `CareEngine.decay`. The Feed and Pet buttons write to the store and reload timelines. On the Lock Screen and in tinted modes the creature is drawn as a single-colour silhouette.
- **Breeding:** for now, *Share link* sends a placeholder `https://mix.orizolabs.app/b/<offerId>`. *Preview* runs `Genetics.breed` locally against another of your own creatures with a **local nonce**. That is preview only, and real breeding needs the server nonce (genome-spec §7).

## Living world (MVP, docs/living-world-spec.md)

- `Shared/Engine/ActivityStateMachine.swift`: the one state machine (focus → night → weather → pair scene → daily routine; alive overlay). Pure; feeds Home, House, diary and the widget timeline (30 min × 12 h). Pair scenes are seeded with `fnv1a32("<pairId>|<localDay>")`.
- `Shared/Engine/WeatherModel.swift` + `Sources/Living/WeatherService.swift`: opt-in WeatherKit, approximate When-In-Use location or a manual city, ≤ 1 fetch / 3 h (app open + BGAppRefresh), cached in the App Group as `weather.json` (the widget reads only the cache). Attribution in Home > More > Living world. Needs the WeatherKit capability + App Service on the App ID.
- `Shared/Engine/LineService.swift`: en/uk templates + guardrails; on-device Foundation Models only on iOS 26 (`#if canImport(FoundationModels)`), filtered and capped. The AI label shows only for AI lines. ≤ 2 notifications/day (`NudgePlanner`).
- `Shared/Engine/LivingEngine.swift`: weather care items (reward once per weather event), jump-rope rewards, idea bubbles (≤ 2/day), "While you were away" diary (≤ 6 entries + "…and more"), gene-based likes. New sparks go through `EconomyEngine.grantCappedSparks` (60/day across sources).
- `Shared/Engine/ArtAdapter.swift`: the ONLY user of MixlingsArt's living-world API. Behind `MIXLINGS_ART_LIVING` (off): add it to SWIFT_ACTIVE_COMPILATION_CONDITIONS of app, widget and tests to draw weather/items/alive frames, rooms, the rope and Lock Screen glyphs; with it off, SwiftUI fallbacks are drawn.
- Widget: tapping the creature pokes it (`PokeMixlingIntent`, a `pendingCare` event); new "Mixling house" widget (medium + Lock Screen accessories with a scene glyph).

