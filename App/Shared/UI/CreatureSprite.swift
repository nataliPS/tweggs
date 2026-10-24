import SwiftUI
import MixlingsArt

/// Draws a creature at its current stage. Static frame only (safe for widgets).
///
/// - `silhouette`: renders a single-colour shape (uses the sprite's alpha as a mask filled with
///   the current foreground style). Used on the Lock Screen, where the system tints/monochromes
///   widgets and a full-colour pixel sprite turns into mud.
struct CreatureSprite: View {
    let creature: Creature
    let stage: Stage
    var silhouette: Bool = false

    var body: some View {
        Group {
            if stage == .egg {
                EggView(traits: PhenotypeMapper.traits(for: creature))
            } else {
                // Babies are drawn smaller; same art for now.
                // TODO(art): per-stage art (baby/teen proportions) once MixlingsArt supports it.
                MixlingView(PhenotypeMapper.phenotype(for: creature))
                    .scaleEffect(scale)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .modifier(SilhouetteModifier(enabled: silhouette))
        .accessibilityHidden(true)
    }

    private var scale: CGFloat {
        switch stage {
        case .egg: return 1
        case .baby: return 0.72
        case .teen: return 0.86
        case .adult: return 1
        }
    }
}

private struct SilhouetteModifier: ViewModifier {
    let enabled: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            Rectangle()
                .fill(.primary)
                .mask { content }
        } else {
            content
        }
    }
}

/// Simple pixel egg drawn with Canvas (no MixlingsArt dependency), tinted by the
/// creature's expressed palette so each egg hints at what will hatch.
struct EggView: View {
    let traits: ExpressedTraits

    // 12 x 16 egg mask; 1 = shell, 2 = spot.
    private static let rows: [String] = [
        "....1111....",
        "...111111...",
        "..11111111..",
        "..11211111..",
        ".1122111111.",
        ".1111111211.",
        ".1111112211.",
        "111111111111",
        "112111111111",
        "122111111211",
        "111111112211",
        "111111111111",
        ".1111211111.",
        ".1112211111.",
        "..11111111..",
        "....1111....",
    ]

    var body: some View {
        Canvas { ctx, size in
            let cols = 12, rowsCount = 16
            let cell = max(1, (min(size.width / CGFloat(cols + 4), size.height / CGFloat(rowsCount))).rounded(.down))
            let w = cell * CGFloat(cols), h = cell * CGFloat(rowsCount)
            let ox = (size.width - w) / 2, oy = (size.height - h) / 2
            let spot = Self.spotColor(palette: traits.palette, shift: traits.shift)
            for (y, row) in Self.rows.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    let rect = CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell,
                                      width: cell + 0.5, height: cell + 0.5)
                    let color: Color = ch == "2" ? spot : Self.shell
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
    }

    private static let shell = Color(red: 1.0, green: 0.97, blue: 0.9)

    /// Rough hue per palette index; only a hint, the real palette lives in MixlingsArt.
    static func spotColor(palette: Int, shift: Int) -> Color {
        let hue = (Double(palette % 16) / 16.0 + 0.035 * Double(shift)).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.55, brightness: 0.9)
    }
}
