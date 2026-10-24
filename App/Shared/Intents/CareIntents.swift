import AppIntents
import WidgetKit

/// Interactive widget buttons (iOS 17 `Button(intent:)`). Compiled into both the app and the
/// widget extension: WidgetKit runs `perform()` in the extension process, which appends a
/// `CareEvent` to `active.json` only (T4) and reloads timelines. The app replays each event once
/// into `collection.json` when it next reads the save (on becoming active).
struct FeedMixlingIntent: AppIntent {
    static let title: LocalizedStringResource = "Feed Mixling"

    init() {}

    func perform() async throws -> some IntentResult {
        CreatureStore.shared.applyToActive(.feed, at: .now)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct PetMixlingIntent: AppIntent {
    static let title: LocalizedStringResource = "Pet Mixling"

    init() {}

    func perform() async throws -> some IntentResult {
        CreatureStore.shared.applyToActive(.pet, at: .now)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// §13 widget tap reaction: tapping the creature itself gives it a playful poke (pendingCare
/// event, merged by the app like Feed / Pet).
struct PokeMixlingIntent: AppIntent {
    static let title: LocalizedStringResource = "Poke Mixling"

    init() {}

    func perform() async throws -> some IntentResult {
        CreatureStore.shared.applyToActive(.poke, at: .now)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
