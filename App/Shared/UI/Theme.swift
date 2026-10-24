import SwiftUI
import MixlingsGenome

/// Light pixel-game look: warm off-white, white rounded cards, soft ink.
/// Values match the approved art sheet background (246, 243, 236).
enum Theme {
    static let background = Color(red: 246 / 255, green: 243 / 255, blue: 236 / 255)
    static let card = Color.white
    static let cardStroke = Color(red: 225 / 255, green: 220 / 255, blue: 208 / 255)
    static let ink = Color(red: 61 / 255, green: 56 / 255, blue: 47 / 255)
    static let inkSoft = Color(red: 110 / 255, green: 104 / 255, blue: 92 / 255)
    static let accent = Color(red: 255 / 255, green: 122 / 255, blue: 89 / 255)
    static let hunger = Color(red: 255 / 255, green: 176 / 255, blue: 59 / 255)
    static let joy = Color(red: 86 / 255, green: 196 / 255, blue: 160 / 255)
    static let mood = Color(red: 240 / 255, green: 110 / 255, blue: 150 / 255)
    static let preview = Color(red: 232 / 255, green: 240 / 255, blue: 255 / 255)

    // Collecting: rarity frame colours (common grey, uncommon green, rare violet, legendary gold).
    static let rarityCommon = Color(red: 158 / 255, green: 154 / 255, blue: 146 / 255)
    static let rarityUncommon = Color(red: 76 / 255, green: 175 / 255, blue: 110 / 255)
    static let rarityRare = Color(red: 128 / 255, green: 90 / 255, blue: 230 / 255)
    static let rarityLegendary = Color(red: 232 / 255, green: 183 / 255, blue: 48 / 255)

    /// Creature card face (approved mockup design/mockup/Card.dc.html).
    static let cardFace = Color(red: 43 / 255, green: 31 / 255, blue: 92 / 255)
    static let cardPanel = Color(red: 58 / 255, green: 44 / 255, blue: 120 / 255)
    static let cardLabel = Color(red: 169 / 255, green: 155 / 255, blue: 230 / 255)
    static let cardHighlight = Color(red: 255 / 255, green: 209 / 255, blue: 102 / 255)
    /// Season album: missing-slot fill and dashed outline.
    static let slotEmpty = Color(red: 251 / 255, green: 249 / 255, blue: 244 / 255)
    static let slotStroke = Color(red: 211 / 255, green: 201 / 255, blue: 182 / 255)

    static func rarity(_ tier: RarityTier) -> Color {
        switch tier {
        case .common: return rarityCommon
        case .uncommon: return rarityUncommon
        case .rare: return rarityRare
        case .legendary: return rarityLegendary
        }
    }

    static func rarity(score: Int) -> Color { rarity(Genetics.tier(forScore: score)) }

    static let cornerRadius: CGFloat = 18
    /// U1: Apple HIG minimum hit target.
    static let minTapTarget: CGFloat = 44

    static func title(_ size: CGFloat = 24) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func body(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func caption(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

/// Rounded white card with a thin warm outline.
struct CardBackground: ViewModifier {
    var fill: Color = Theme.card
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1.5)
            )
    }
}

extension View {
    func card(fill: Color = Theme.card) -> some View { modifier(CardBackground(fill: fill)) }
}

/// Chunky pill button used for care actions. Always at least 44 pt tall (U1 tap targets).
struct PixelButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(15))
            .foregroundStyle(Theme.ink)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.45 : 0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint.opacity(0.7), lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Horizontal stat bar, 0...100.
struct StatBar: View {
    let label: LocalizedStringKey
    let systemImage: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(Theme.caption(11))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(label)
                .font(Theme.caption(11))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .frame(minWidth: 40, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cardStroke.opacity(0.6))
                    Capsule().fill(tint)
                        .frame(width: max(4, geo.size.width * CGFloat(min(100, max(0, value))) / 100))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(value) percent"))
    }
}

extension View {
    /// U1: pads small controls (icons, chips) out to a 44 x 44 pt hit area.
    func minTapTarget() -> some View {
        frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget).contentShape(Rectangle())
    }
}

/// Friendly empty state used by Collection, Sanctuary and Breed.
struct EmptyStateCard: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: Text

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(Theme.title(18))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            message
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .card()
        .accessibilityElement(children: .combine)
    }
}
