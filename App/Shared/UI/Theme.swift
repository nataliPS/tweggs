import SwiftUI

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

    static let cornerRadius: CGFloat = 18

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

/// Chunky pill button used for care actions.
struct PixelButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(15))
            .foregroundStyle(Theme.ink)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
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
