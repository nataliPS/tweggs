import WidgetKit
import SwiftUI
import AppIntents
import MixlingsGenome

@main
struct MixlingsWidgetBundle: WidgetBundle {
    var body: some Widget {
        MixlingWidget()
        HouseWidget()
    }
}

struct MixlingWidget: Widget {
    static let kind = "MixlingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: MixlingProvider()) { entry in
            MixlingWidgetView(entry: entry)
        }
        .configurationDisplayName("Mixling")
        .description("Check on your Mixling and give it a snack or a pat.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

// MARK: - Timeline

struct MixlingEntry: TimelineEntry {
    let date: Date
    /// Creature with stats already projected to `date`. Nil before onboarding.
    let creature: Creature?
    let stage: Stage
    let condition: Condition
    /// Today's free daily surprise is still unopened at `date`.
    var surpriseWaiting: Bool = false
    /// Living world (§0): what the creature is doing at `date` (ActivityStateMachine).
    var activity: Activity? = nil
    var look: LivingLook = .plain
    /// Housemate for pair scenes (§9), projected to `date`.
    var partner: Creature? = nil
    /// Short template line for the medium widget.
    var line: String? = nil
}

struct MixlingProvider: TimelineProvider {
    /// 30-minute steps for 12 hours (25 entries incl. now). Static frames only.
    static let step: TimeInterval = 30 * 60
    static let horizon: TimeInterval = 12 * 60 * 60

    func placeholder(in context: Context) -> MixlingEntry {
        Self.entry(for: Self.sampleCreature, at: .now)
    }

    // T4: the widget reads ONLY active.json (never the full collection, never Firebase).
    func getSnapshot(in context: Context, completion: @escaping (MixlingEntry) -> Void) {
        let snap = CreatureStore.shared.loadActive()
        var creature: Creature? = snap?.creature
        if context.isPreview && creature == nil {
            creature = Self.sampleCreature // widget gallery before onboarding
        }
        let ctx = Self.context(snap: snap)
        let act = ActivityStateMachine.activity(at: .now, context: ctx)
        completion(Self.entry(for: creature, at: .now, lastSurpriseDay: snap?.lastSurpriseDay,
                              activity: act, partner: snap?.partner, givenItems: snap?.givenItems ?? [:]))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MixlingEntry>) -> Void) {
        let snap = CreatureStore.shared.loadActive()
        completion(Self.timeline(for: snap?.creature, from: .now, lastSurpriseDay: snap?.lastSurpriseDay,
                                 partner: snap?.partner, givenItems: snap?.givenItems ?? [:],
                                 context: Self.context(snap: snap)))
    }

    /// Cached weather + device state + pair id. The widget never fetches anything (§1).
    static func context(snap: ActiveSnapshot?) -> ActivityContext {
        var pairId: String?
        if let a = snap?.creature, let b = snap?.partner { pairId = HousePair.pairId(a, b) }
        return ActivityContext(timeZone: .current, weather: LivingCache.shared.loadWeather(),
                               device: LivingCache.shared.loadDevice(), pairId: pairId,
                               calmUntil: snap?.calmUntil, windDown: snap?.windDown ?? false)
    }

    /// Pure, testable timeline builder. `lastSurpriseDay` drives the "surprise waiting" hint,
    /// which flips on by itself at local midnight because each entry checks its own date.
    /// Living world: one `ActivityStateMachine.schedule` entry per step (scene, night, weather,
    /// alive frames; the first entry after the night gets the morning stretch).
    static func timeline(for creature: Creature?, from now: Date,
                         lastSurpriseDay: String? = nil, partner: Creature? = nil,
                         givenItems: [String: Int] = [:],
                         context: ActivityContext = ActivityContext()) -> Timeline<MixlingEntry> {
        guard let creature else {
            // Not onboarded yet: one entry, refresh in an hour (the app also reloads on change).
            return Timeline(entries: [entry(for: nil, at: now)],
                            policy: .after(now.addingTimeInterval(3600)))
        }
        let schedule = ActivityStateMachine.schedule(from: now, context: context, step: step, horizon: horizon)
        let entries = schedule.map { s in
            entry(for: creature, at: s.date, lastSurpriseDay: lastSurpriseDay, activity: s.activity,
                  partner: partner, givenItems: givenItems, timeZone: context.timeZone)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    static func entry(for creature: Creature?, at date: Date, lastSurpriseDay: String? = nil,
                      activity: Activity? = nil, partner: Creature? = nil,
                      givenItems: [String: Int] = [:], timeZone: TimeZone = .current) -> MixlingEntry {
        guard let creature else {
            return MixlingEntry(date: date, creature: nil, stage: .egg, condition: .okay)
        }
        var look = LivingLook.plain
        var line: String?
        if let a = activity {
            var item = LivingEngine.displayedItem(givenItems: givenItems, weather: a.weather, at: date, timeZone: timeZone)
            if a.alive == .lowPower { item = .blanket }
            look = LivingLook(weather: a.weather, item: item, alive: a.alive)
            if CareEngine.stage(creature, at: date) != .egg {
                line = LineService.homeLine(for: creature, activity: a, now: date, timeZone: timeZone).text
            }
        }
        return MixlingEntry(
            date: date,
            creature: CareEngine.decay(creature, to: date),
            stage: CareEngine.stage(creature, at: date),
            condition: CareEngine.condition(creature, at: date),
            surpriseWaiting: CollectingEngine.canOpenSurprise(lastSurpriseDay: lastSurpriseDay, now: date),
            activity: activity,
            look: look,
            partner: partner.map { CareEngine.decay($0, to: date) },
            line: line
        )
    }

    static let sampleCreature: Creature = {
        let genome = (try? Genetics.starter(playerId: "widget-placeholder", slot: 0))
            ?? Array(repeating: [0, 0], count: Catalog.geneCount)
        let born = Date.now.addingTimeInterval(-2 * CareEngine.day)
        return Creature(id: "s_placeholder", name: "Mixy", genome: genome, origin: .starter,
                        bornAt: born, hatchedAt: born.addingTimeInterval(CareEngine.hatchAfter))
    }()
}

// MARK: - Views

struct MixlingWidgetView: View {
    let entry: MixlingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(Self.homeURL)
        case .systemMedium:
            MediumView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
                .widgetURL(Self.homeURL)
        default:
            SmallView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
                .widgetURL(Self.homeURL)
        }
    }

    static let homeURL = URL(string: "mixlings://home")
}

/// Full-colour sprite on the Home Screen; single-colour silhouette when the system
/// tints / desaturates widgets (Lock Screen, StandBy night mode, tinted Home Screen).
private struct WidgetSprite: View {
    let creature: Creature
    let stage: Stage
    /// A1 mood layer (smile / "o" / hungry wobble) for this entry's moment.
    let condition: Condition
    var look: LivingLook = .plain
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        // §13 tap reaction: tapping the creature pokes it (pendingCare event) instead of opening the app.
        Button(intent: PokeMixlingIntent()) {
            CreatureSprite(creature: creature, stage: stage,
                           silhouette: renderingMode != .fullColor, condition: condition, look: look)
        }
        .buttonStyle(.plain)
        .disabled(stage == .egg)
        .accessibilityLabel(Text("Poke Mixling"))
    }
}

private struct SmallView: View {
    let entry: MixlingEntry

    var body: some View {
        if let c = entry.creature {
            VStack(spacing: 4) {
                WidgetSprite(creature: c, stage: entry.stage, condition: entry.condition, look: entry.look)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 4) {
                    Text(c.name)
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if entry.surpriseWaiting {
                        Image(systemName: "gift.fill")
                            .font(Theme.caption(10))
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel(Text("Surprise waiting"))
                    }
                    Image(systemName: "heart.fill")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.mood)
                    Text(verbatim: "\(c.moodValue)")
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.inkSoft)
                }
                CareButtons(compact: true, canFeed: entry.stage != .egg)
            }
        } else {
            EmptyStateView()
        }
    }
}

private struct MediumView: View {
    let entry: MixlingEntry

    var body: some View {
        if let c = entry.creature {
            HStack(spacing: 12) {
                WidgetSprite(creature: c, stage: entry.stage, condition: entry.condition, look: entry.look)
                    .frame(maxWidth: 120, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(c.name)
                            .font(Theme.title(16))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(entry.condition.title)
                            .font(Theme.caption(11))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    StatBar(label: "Belly", systemImage: "fork.knife", value: c.hungerValue, tint: Theme.hunger)
                    StatBar(label: "Fun", systemImage: "star.fill", value: c.joyValue, tint: Theme.joy)
                    StatBar(label: "Mood", systemImage: "heart.fill", value: c.moodValue, tint: Theme.mood)
                    if let line = entry.line {
                        Text(verbatim: line)
                            .font(Theme.caption(10))
                            .italic()
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                    }
                    if entry.surpriseWaiting {
                        Label("Surprise waiting", systemImage: "gift.fill")
                            .font(Theme.caption(11))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    CareButtons(compact: false, canFeed: entry.stage != .egg)
                }
            }
        } else {
            EmptyStateView()
        }
    }
}

private struct CircularView: View {
    let entry: MixlingEntry

    var body: some View {
        if let c = entry.creature {
            Gauge(value: Double(c.moodValue), in: 0...100) {
                Text("Mood")
            } currentValueLabel: {
                CreatureSprite(creature: c, stage: entry.stage, silhouette: true, condition: entry.condition)
                    .padding(6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "oval.portrait.fill")
                    .font(.system(size: 22))
            }
        }
    }
}

private struct CareButtons: View {
    let compact: Bool
    let canFeed: Bool

    var body: some View {
        HStack(spacing: 6) {
            if canFeed {
                Button(intent: FeedMixlingIntent()) {
                    buttonLabel("Feed", systemImage: "fork.knife")
                }
                .tint(Theme.hunger)
            }
            Button(intent: PetMixlingIntent()) {
                buttonLabel("Pet", systemImage: "heart.fill")
            }
            .tint(Theme.mood)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .font(Theme.caption(compact ? 11 : 12))
    }

    @ViewBuilder
    private func buttonLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        if compact {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(title))
        } else {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "oval.portrait.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.accent)
            Text("Open Mixlings to hatch your egg")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
    }
}
