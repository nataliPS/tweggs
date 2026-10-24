import Foundation

/// H4: copy that goes OUT with shares (cards, links, clips). English-first: the English source
/// strings are written for a global TikTok/Instagram audience; Ukrainian is in the catalog too.
/// Brand name in copy: "Tweggs" (placeholder; code identifiers stay "Mixlings").
/// TODO(brand): one place to change the brand name once the rename is final.
enum ShareCopy {
    static let brand = "Tweggs"

    static var breedSubject: LocalizedStringResource { "Breed with my pet on Tweggs!" }

    static func breedMessage(parentName: String) -> LocalizedStringResource {
        "Let's hatch a baby together! \(parentName) is waiting. The rarest pets only hatch with friends."
    }

    static func cardMessage(name: String) -> LocalizedStringResource {
        "Meet \(name), my one-of-a-kind pixel pet. Hatch yours on Tweggs!"
    }

    static var cardFooter: LocalizedStringResource { "Hatch yours on Tweggs" }

    static func clipMessage(name: String) -> LocalizedStringResource {
        "\(name) just hatched! Breed with me on Tweggs."
    }

    static var tradeSubject: LocalizedStringResource { "Swap pets on Tweggs?" }

    static func tradeMessage(name: String) -> LocalizedStringResource {
        "Want to swap pets? I'm offering \(name)."
    }
}
