import Foundation

/// C2: coarse age band from the neutral age screen. Only the band is stored (locally, in the
/// save), never the birth year itself.
///
/// Raw values match the server (`functions/src/domain/types.ts` AGE_BANDS). Ordered youngest
/// first (`Comparable`). Legacy values are read conservatively (see `normalized`).
enum AgeBand: String, Codable, Sendable, CaseIterable, Comparable {
    case under13 = "under13"
    case teen13to15 = "13to15"
    case teen16to17 = "16to17"
    case adult18plus = "18plus"

    /// Pre-split values still found in saves / sent by old builds. "13to17" (server) and
    /// "teen13to17" (app saves up to 0.1) map to the YOUNGER band, 13to15 (safe side).
    static let legacy: [String: AgeBand] = [
        "13to17": .teen13to15,
        "teen13to17": .teen13to15,
        "adult18plus": .adult18plus,
    ]

    /// Current or legacy raw value -> band; nil for anything unknown.
    static func normalized(_ raw: String) -> AgeBand? {
        AgeBand(rawValue: raw) ?? legacy[raw]
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let band = AgeBand.normalized(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unknown age band \(raw)"))
        }
        self = band
    }

    /// Under-13 players get offline mode: no breeding links, trading, sharing or Duo.
    var socialAllowed: Bool { self != .under13 }

    /// Duo (future) is for 13+ (server `DUO_MIN_AGE_BAND`).
    var duoAllowed: Bool { self >= .teen13to15 }

    private var order: Int { AgeBand.allCases.firstIndex(of: self) ?? 0 }

    static func < (lhs: AgeBand, rhs: AgeBand) -> Bool { lhs.order < rhs.order }
}

/// How a Duo is presented (§11). There is no romantic framing.
enum DuoFraming: String, Codable, Sendable {
    case duo
    case bestFriends
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
        if youngestAge < 16 { return .teen13to15 }
        if youngestAge < 18 { return .teen16to17 }
        return .adult18plus
    }

    /// Youngest band that may pick the "duo" framing (server `DUO_FRAMING_MIN_BAND`).
    static let duoFramingMinBand: AgeBand = .teen16to17

    /// Duo UI framing (§11, mirrors server `framingFor`): forced "Best friends" if ANY member is
    /// under 16 or of unknown age (fail closed); otherwise the members' choice.
    static func duoFraming(for members: [AgeBand?], wanted: DuoFraming = .duo) -> DuoFraming {
        guard !members.isEmpty else { return .bestFriends }
        return members.allSatisfy { ($0 ?? .under13) >= duoFramingMinBand } ? wanted : .bestFriends
    }

    /// Single-player form (e.g. what this player's own Duo UI may offer).
    static func duoFraming(for band: AgeBand?, wanted: DuoFraming = .duo) -> DuoFraming {
        duoFraming(for: [band], wanted: wanted)
    }

    /// TODO(age-range): when the Declared Age Range API (DeclaredAgeRange framework, iOS 26+)
    /// is available, ask it first (`AgeRangeService.shared.requestAgeRange(ageGates: 13, 16, 18)`)
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
