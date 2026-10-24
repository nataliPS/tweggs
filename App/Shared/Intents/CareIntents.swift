import AppIntents
import WidgetKit

/// Interactive widget buttons (iOS 17 `Button(intent:)`). Compiled into both the app and the
/// widget extension: WidgetKit runs `perform()` in the extension process, which writes the
/// shared App Group save and reloads timelines. The app re-reads the save when it becomes active.
struct FeedMixlingIntent: AppIntent {
    static let title: LocalizedStringResource = "Feed Mixling"

    init() {}

    func perform() async throws -> some IntentResult {
        CreatureStore.shared.apply(.feed, at: .now)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct PetMixlingIntent: AppIntent {
    static let title: LocalizedStringResource = "Pet Mixling"

    init() {}

    func perform() async throws -> some IntentResult {
        CreatureStore.shared.apply(.pet, at: .now)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
