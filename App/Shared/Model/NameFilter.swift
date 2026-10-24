import Foundation

/// C3: creature names reach friends (cards, links, trades), so they are checked on device
/// before saving. Small, conservative lists for English, Ukrainian and Russian.
/// TODO(server): the server re-checks names on breed/trade and owns the real (larger) lists.
enum NameFilter {
    static let maxLength = 16

    enum Verdict: Equatable, Sendable {
        case ok(String)
        case empty
        case tooLong
        case invalidCharacters
        /// Looks like an email, phone number, URL or social handle.
        case contactInfo
        case blocked
    }

    /// Returns the cleaned name or why it was rejected.
    static func check(_ raw: String) -> Verdict {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if name.isEmpty { return .empty }
        if name.count > maxLength { return .tooLong }
        if !name.unicodeScalars.allSatisfy(isAllowed) { return .invalidCharacters }
        if looksLikeContactInfo(name) { return .contactInfo }
        if containsBlockedWord(name) { return .blocked }
        return .ok(name)
    }

    /// Convenience: cleaned name, or nil if rejected.
    static func clean(_ raw: String) -> String? {
        if case .ok(let n) = check(raw) { return n }
        return nil
    }

    static func message(for verdict: Verdict) -> LocalizedStringResource? {
        switch verdict {
        case .ok: return nil
        case .empty: return "Give your Mixling a name."
        case .tooLong: return "Names can be up to 16 letters."
        case .invalidCharacters: return "Use letters, numbers, spaces, - or '."
        case .contactInfo: return "No emails, phone numbers or links in names."
        case .blocked: return "Let's pick a kinder name."
        }
    }

    // MARK: Rules

    private static func isAllowed(_ s: Unicode.Scalar) -> Bool {
        if s == " " || s == "-" || s == "'" || s == "’" || s == "ʼ" || s == "." { return true }
        return s.properties.isAlphabetic || s.properties.numericType != nil
    }

    static func looksLikeContactInfo(_ name: String) -> Bool {
        let lower = name.lowercased()
        // Phone-ish: 5+ digits anywhere ("067 12 34" is still digits).
        if lower.filter(\.isNumber).count >= 5 { return true }
        // Email / handle.
        if lower.contains("@") { return true }
        // URL-ish: scheme, www, or a dot followed by a common TLD.
        if lower.contains("http") || lower.contains("www") { return true }
        let compact = lower.replacingOccurrences(of: " ", with: "")
        let tlds = ["com", "net", "org", "ua", "ru", "io", "me", "app", "gg", "tv", "ly", "co"]
        for tld in tlds where compact.contains("." + tld) {
            // ".co" is a prefix of ".com"; any match is enough.
            if let r = compact.range(of: "." + tld), r.upperBound == compact.endIndex
                || !(compact[r.upperBound...].first?.isLetter ?? false) {
                return true
            }
        }
        return false
    }

    static func containsBlockedWord(_ name: String) -> Bool {
        let tokens = normalized(name).split(separator: " ").map(String.init)
        let joined = tokens.joined()
        if tokens.contains(where: { exactNormalized.contains($0) }) { return true }
        if exactNormalized.contains(joined) { return true }
        return rootNormalized.contains { joined.contains($0) }
    }

    /// Lists go through the same normalization as input (diacritic folding turns "й" into "и").
    private static let exactNormalized: Set<String> = Set(exactWords.map { normalized($0) })
    private static let rootNormalized: [String] = rootWords.map { normalized($0) }

    /// Lowercased, diacritics folded, common leetspeak mapped, separators -> single spaces.
    static func normalized(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        let leet: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
                                            "$": "s", "@": "a", "ё": "е", "ї": "і", "ґ": "г"]
        var out = ""
        for ch in folded {
            let c = leet[ch] ?? ch
            if c.isLetter { out.append(c) } else { out.append(" ") }
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    // MARK: Lists (deliberately small; see TODO(server) above)

    /// Matched only as a whole word, so "Dickens" or "Cockatoo" stay fine.
    static let exactWords: Set<String> = [
        // en
        "fag", "cunt", "dick", "cock", "tits", "nazi", "hitler", "rape", "porn", "sex", "anal", "kkk",
        // uk / ru
        "хуй", "хуя", "бля", "блять", "сука", "суки", "лох", "даун", "жид", "секс",
        "хохол", "кацап", "москаль", "нацист", "гітлер", "гитлер",
    ]

    /// Matched anywhere in the joined name (distinctive roots only; no "rapist"/"boob": therapist, Booboo).
    static let rootWords: [String] = [
        // en
        "fuck", "shit", "nigg", "faggot", "retard", "whore", "slut", "bitch", "pussy",
        "pedophil", "penis", "vagina", "dildo",
        // uk / ru
        "хуй", "пизд", "пізд", "ебат", "ебан", "єбан", "їбан", "ебал", "залуп", "мудак", "гандон",
        "підор", "пидор", "педик", "педоф", "шлюх", "блядь", "блядин", "дроч", "сучк",
    ]
}
