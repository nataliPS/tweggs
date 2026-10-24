import Foundation
import MixlingsGenome

/// Wellbeing texts (en/uk) from `Resources/Wellbeing/WellbeingContent.json`.
/// Templates only, never AI. Every text has an id and reviewedBy / reviewedAt (null until the
/// external psychologist signs off; see docs/wellbeing-spec.md "Content pipeline").
struct WellbeingContent: Decodable, Sendable {
    struct Item: Decodable, Equatable, Sendable {
        var id: String
        var text_en: String
        var text_uk: String
        var reviewedBy: String?
        var reviewedAt: String?

        var isReviewed: Bool { reviewedBy != nil && reviewedAt != nil }
    }

    var version: Int
    var items: [Item]

    static let resourceName = "WellbeingContent"

    /// Loaded once from the app bundle. Missing / broken file = empty (texts fall back to ids
    /// in DEBUG so the gap is obvious; never crashes).
    static let shared: WellbeingContent = load(bundle: .main) ?? WellbeingContent(version: 0, items: [])

    static func load(bundle: Bundle) -> WellbeingContent? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    static func decode(_ data: Data) throws -> WellbeingContent {
        try JSONDecoder().decode(WellbeingContent.self, from: data)
    }

    func item(_ id: String) -> Item? { items.first { $0.id == id } }

    func text(_ id: String, language: LineLanguage = .current) -> String {
        guard let i = item(id) else { return id }
        return language == .uk ? i.text_uk : i.text_en
    }

    /// True while any text still lacks expert sign-off (drives the DEBUG banner).
    var pendingReview: Bool { items.isEmpty || items.contains { !$0.isReviewed } }

    /// Kind thoughts for the evening wind-down ("winddown.thought.N").
    var windDownThoughtIds: [String] { items.map(\.id).filter { $0.hasPrefix("winddown.thought.") }.sorted() }

    /// One kind thought per local day (deterministic, no history kept).
    func windDownThought(now: Date, timeZone: TimeZone = .current, language: LineLanguage = .current) -> String {
        let ids = windDownThoughtIds
        guard !ids.isEmpty else { return "" }
        let day = CollectingEngine.dayKey(now, timeZone: timeZone)
        let i = Int(Hash.fnv1a32("winddown|\(day)") % UInt32(ids.count))
        return text(ids[i], language: language)
    }
}

/// Static, offline crisis helplines (`Resources/Wellbeing/Helplines.json`).
/// TODO: verify numbers before release (Щит). An empty number means "not verified": the UI
/// shows the name and the fallback "find a helpline" link instead. Nothing is collected.
struct HelplineDirectory: Decodable, Equatable, Sendable {
    struct Line: Decodable, Equatable, Identifiable, Sendable {
        var id: String
        var name: String
        /// Digits only, or "" when not verified yet.
        var number: String
        var website: String?
        /// "crisis" or "youth".
        var kind: String

        var hasNumber: Bool { !number.isEmpty }
        var telURL: URL? {
            let digits = number.filter(\.isNumber)
            return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
        }
        var websiteURL: URL? { website.flatMap(URL.init(string:)) }
    }

    struct Country: Decodable, Equatable, Identifiable, Sendable {
        /// ISO 3166-1 alpha-2 (the UK is "GB").
        var code: String
        var emergency: String?
        var lines: [Line]

        var id: String { code }
        var displayName: String { Locale.current.localizedString(forRegionCode: code) ?? code }
    }

    struct Fallback: Decodable, Equatable, Sendable {
        var name: String
        var website: String

        var url: URL? { URL(string: website) }
    }

    var version: Int
    var verified: Bool
    var fallback: Fallback
    var countries: [Country]

    static let resourceName = "Helplines"
    static let fallbackURL = URL(string: "https://findahelpline.com")!

    static let shared: HelplineDirectory = load(bundle: .main)
        ?? HelplineDirectory(version: 0, verified: false,
                             fallback: Fallback(name: "Find A Helpline", website: fallbackURL.absoluteString),
                             countries: [])

    static func load(bundle: Bundle) -> HelplineDirectory? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    static func decode(_ data: Data) throws -> HelplineDirectory {
        try JSONDecoder().decode(HelplineDirectory.self, from: data)
    }

    /// "UK" is accepted as an alias of "GB".
    func country(_ code: String?) -> Country? {
        guard var c = code?.uppercased() else { return nil }
        if c == "UK" { c = "GB" }
        return countries.first { $0.code == c }
    }

    /// The device region's country first, then the rest.
    func ordered(region: String?) -> (local: Country?, others: [Country]) {
        let local = country(region)
        return (local, countries.filter { $0.code != local?.code })
    }

    static var deviceRegion: String? { Locale.current.region?.identifier }
}
