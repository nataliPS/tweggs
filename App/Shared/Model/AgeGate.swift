import Foundation

/// C2: coarse age band from the neutral age screen. Only the band is stored (locally, in the
/// save), never the birth year itself.
enum AgeBand: String, Codable, Sendable, CaseIterable {
    case under13
    case teen13to17
    case adult18plus

    /// Under-13 players get offline mode: no breeding links, trading or sharing.
    var socialAllowed: Bool { self != .under13 }
}

enum AgeGate {
    /// Years offered by the picker: this year back to 100 years ago (newest first).
    static func selectableYears(now: Date = .now, calendar: Calendar = Calendar(identifier: .gregorian)) -> [Int] {
        let year = calendar.component(.year, from: now)
        return Array(stride(from: year, through: year - 100, by: -1))
    }

    /// Band for a birth year. Year-only input can't tell if the birthday has passed, so this
    /// uses the YOUNGEST possible age (`year - birthYear - 1`): borderline players are treated
    /// as the younger band, which is the safe side.
    static func band(birthYear: Int, now: Date = .now,
                     calendar: Calendar = Calendar(identifier: .gregorian)) -> AgeBand {
        let year = calendar.component(.year, from: now)
        let youngestAge = year - birthYear - 1
        if youngestAge < 13 { return .under13 }
        if youngestAge < 18 { return .teen13to17 }
        return .adult18plus
    }

    /// TODO(age-range): when the Declared Age Range API (DeclaredAgeRange framework, iOS 26+)
    /// is available, ask it first (`AgeRangeService.shared.requestAgeRange(ageGates: 13, 18)`)
    /// and only fall back to the neutral age screen when the user declines or it's unavailable.
    /// Returns nil for now, which means "show the age screen".
    @MainActor
    static func declaredAgeBand() async -> AgeBand? {
        nil
    }
}

extension SaveData {
    /// Breeding links, trading and sharing are on only for a known 13+ band.
    /// Unknown (nil) counts as not allowed until the age screen has been answered.
    var socialAllowed: Bool { ageBand?.socialAllowed ?? false }
}
