import Foundation

/// Decoration layers a holiday switches on (room garland, widget accents, line flavour).
struct Decorations: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int
    static let garland = Decorations(rawValue: 1 << 0)
    static let lights = Decorations(rawValue: 1 << 1)
    static let snow = Decorations(rawValue: 1 << 2)
    static let hearts = Decorations(rawValue: 1 << 3)
    static let flowers = Decorations(rawValue: 1 << 4)
    static let vyshyvanka = Decorations(rawValue: 1 << 5)
    static let pumpkins = Decorations(rawValue: 1 << 6)
}

/// Local holiday table (§4; MVP per the §0 stage split). Remote Config dates come later.
/// All holidays are free: decorations only, cosmetics earnable, nothing sold.
enum Holiday: String, Codable, CaseIterable, Sendable {
    case winter          // Christmas + New Year (Ukraine celebrates Christmas on Dec 25)
    case valentines
    case spring          // first week of spring (Ukraine counts spring from March 1)
    case independenceDay // Ukraine, Aug 24 (vyshyvanka); Flag Day Aug 23 included
    case halloween

    var title: LocalizedStringResource {
        switch self {
        case .winter: return "Winter holidays"
        case .valentines: return "Valentine's Day"
        case .spring: return "Hello, spring"
        case .independenceDay: return "Independence Day of Ukraine"
        case .halloween: return "Halloween"
        }
    }

    var decorations: Decorations {
        switch self {
        case .winter: return [.garland, .lights, .snow]
        case .valentines: return [.hearts]
        case .spring: return [.flowers]
        case .independenceDay: return [.vyshyvanka, .garland]
        case .halloween: return [.pumpkins, .lights]
        }
    }

    var systemImage: String {
        switch self {
        case .winter: return "snowflake"
        case .valentines: return "heart.fill"
        case .spring: return "camera.macro"
        case .independenceDay: return "flag.fill"
        case .halloween: return "moon.haze.fill"
        }
    }
}

enum HolidayCalendar {
    /// Inclusive (month, day) ranges. A range whose start is after its end wraps the year end.
    struct Window: Sendable {
        let holiday: Holiday
        let start: (month: Int, day: Int)
        let end: (month: Int, day: Int)
    }

    static let table: [Window] = [
        Window(holiday: .winter, start: (12, 20), end: (1, 7)),
        Window(holiday: .valentines, start: (2, 13), end: (2, 15)),
        Window(holiday: .spring, start: (3, 1), end: (3, 7)),
        Window(holiday: .independenceDay, start: (8, 23), end: (8, 25)),
        Window(holiday: .halloween, start: (10, 24), end: (10, 31)),
    ]

    static func holiday(on date: Date, timeZone: TimeZone = .current) -> Holiday? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.month, .day], from: date)
        guard let m = c.month, let d = c.day else { return nil }
        let key = m * 100 + d
        for w in table {
            let s = w.start.month * 100 + w.start.day
            let e = w.end.month * 100 + w.end.day
            let inside = s <= e ? (key >= s && key <= e) : (key >= s || key <= e)
            if inside { return w.holiday }
        }
        return nil
    }
}
