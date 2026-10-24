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
    /// Mood expression layer (A1, art v2). Eggs have no face, so it only shows after hatching.
    var condition: Condition? = nil

    var body: some View {
        Group {
            #if MIXLINGS_ART_V2
            // A3: MixlingsArt draws the egg itself (stage 0: the egg's own expressed palette +
            // shift, its pattern on the shell; body/eyes/head/tail/aura ignored).
            spriteBody
            #else
            if stage == .egg {
                EggView(traits: PhenotypeMapper.traits(for: creature))
                    .modifier(SilhouetteModifier(enabled: silhouette))
            } else {
                spriteBody
            }
            #endif
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var spriteBody: some View {
        let p = PhenotypeMapper.phenotype(for: creature, stage: stage, condition: condition)
        #if MIXLINGS_ART_V2
        if silhouette, let cg = PhenotypeMapper.silhouetteImage(p) {
            Rectangle().fill(.primary).mask {
                Image(decorative: cg, scale: 1).interpolation(.none).resizable().aspectRatio(1, contentMode: .fit)
            }
        } else {
            MixlingView(p).modifier(SilhouetteModifier(enabled: silhouette))
        }
        #else
        // Babies are drawn smaller; same art until MixlingsArt draws stages (see PhenotypeMapper).
        MixlingView(p)
            .scaleEffect(scale)
            .modifier(SilhouetteModifier(enabled: silhouette))
        #endif
    }

    private var scale: CGFloat {
        if PhenotypeMapper.artDrawsStages { return 1 }
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
/// Fallback only: with `MIXLINGS_ART_V2` eggs are drawn by MixlingsArt (stage 0).
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
