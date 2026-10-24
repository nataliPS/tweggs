import WidgetKit
import SwiftUI
import MixlingsArt

/// §9 pair life on the Home / Lock Screen: what the two housemates are doing right now.
/// Reuses `MixlingProvider` (same 30-min schedule from `ActivityStateMachine`). Static frames only.
/// Lock Screen accessory families show a one-colour scene glyph (art glyph or SF Symbol fallback).
struct HouseWidget: Widget {
    static let kind = "MixlingHouseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: MixlingProvider()) { entry in
            HouseWidgetView(entry: entry)
        }
        .configurationDisplayName("Mixling house")
        .description("See what your Mixlings are up to at home.")
        .supportedFamilies([.systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct HouseWidgetView: View {
    let entry: MixlingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            inline.containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            rectangular.containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                SceneGlyph(scene: entry.activity?.scene, isNight: entry.activity?.isNight ?? false,
                           weather: entry.activity?.weather ?? WeatherKind.none)
                    .padding(10)
            }
            .widgetAccentable()
            .containerBackground(for: .widget) { Color.clear }
        default:
            room.containerBackground(for: .widget) { Theme.background }
                .widgetURL(URL(string: "mixlings://home"))
        }
    }

    private var title: Text {
        guard let a = entry.activity else { return Text("At home") }
        if let s = a.scene { return Text(s.title) }
        if a.isNight { return Text("Sleeping") }
        return Text(a.weather.title)
    }

    private var inline: some View {
        Label { title } icon: { Image(systemName: symbol) }
    }

    private var symbol: String {
        guard let a = entry.activity else { return "house.fill" }
        if let s = a.scene { return s.systemImage }
        if a.isNight { return "moon.zzz.fill" }
        return a.weather.systemImage
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            SceneGlyph(scene: entry.activity?.scene, isNight: entry.activity?.isNight ?? false,
                       weather: entry.activity?.weather ?? WeatherKind.none)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                if let c = entry.creature {
                    Text(verbatim: entry.partner.map { "\(c.name) & \($0.name)" } ?? c.name)
                        .font(Theme.caption(12))
                        .lineLimit(1)
                }
                title
                    .font(Theme.body(13))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .widgetAccentable()
    }

    @ViewBuilder
    private var room: some View {
        if let a = entry.creature, let act = entry.activity {
            VStack(alignment: .leading, spacing: 4) {
                WidgetRoom(a: a, b: entry.partner, stage: entry.stage, date: entry.date, activity: act, look: entry.look)
                HStack {
                    Image(systemName: symbol).foregroundStyle(Theme.accent)
                    title.font(Theme.caption(12)).foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    if let h = act.holiday {
                        Image(systemName: h.systemImage).foregroundStyle(Theme.accent)
                    }
                }
                .font(Theme.caption(12))
            }
        } else {
            Text("Open Mixlings to hatch your egg")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.inkSoft)
        }
    }
}

/// One-colour scene glyph: MixlingsArt 16x16 glyph when available, else an SF Symbol.
struct SceneGlyph: View {
    let scene: LifeScene?
    let isNight: Bool
    let weather: WeatherKind

    var body: some View {
        if let scene, let cg = ArtAdapter.glyphImage(scene: scene) {
            Rectangle().fill(.primary).mask {
                Image(decorative: cg, scale: 1).interpolation(.none).resizable().aspectRatio(1, contentMode: .fit)
            }
            .aspectRatio(1, contentMode: .fit)
        } else {
            Image(systemName: scene?.systemImage ?? (isNight ? "moon.zzz.fill" : weather.systemImage))
                .resizable()
                .scaledToFit()
        }
    }
}

private struct WidgetRoom: View {
    let a: Creature
    let b: Creature?
    let stage: Stage
    let date: Date
    let activity: Activity
    let look: LivingLook
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let pa = PhenotypeMapper.phenotype(for: a, stage: stage)
        let pb = b.map { PhenotypeMapper.phenotype(for: $0, stage: CareEngine.stage($0, at: date)) }
        if renderingMode == .fullColor, let pb,
           let cg = ArtAdapter.roomImage(pa, pb, scene: activity.scene, night: activity.isNight,
                                         weather: activity.weather, decorations: activity.holiday?.decorations ?? []) {
            Image(decorative: cg, scale: 1)
                .interpolation(.none)
                .resizable()
                .aspectRatio(ArtAdapter.sceneSize, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .bottom, spacing: 6) {
                CreatureSprite(creature: a, stage: stage, silhouette: renderingMode != .fullColor, look: look)
                    .scaleEffect(x: -1, y: 1)
                if let b {
                    CreatureSprite(creature: b, stage: CareEngine.stage(b, at: date),
                                   silhouette: renderingMode != .fullColor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
