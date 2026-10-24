import SwiftUI

struct HomeView: View {
    @Environment(GameModel.self) private var model

    enum Route: Hashable { case club, shop, odds, living }
    @State private var route: Route?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let creature = model.active {
                    // Re-evaluates every minute so decay and countdowns stay fresh.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        HomeContent(creature: creature, now: context.date)
                    }
                    .padding(16)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Mixlings")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SparkBalance(sparks: model.save.sparks)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { route = .club } label: { Label("Mix Club", systemImage: "crown.fill") }
                        Button { route = .shop } label: { Label("Spark shop", systemImage: "bag.fill") }
                        Button { route = .odds } label: { Label("Odds", systemImage: "percent") }
                        Button { route = .living } label: { Label("Living world", systemImage: "cloud.sun.fill") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .minTapTarget()
                            .accessibilityLabel(Text("More"))
                    }
                }
            }
            .navigationDestination(item: $route) { r in
                switch r {
                case .club: ClubView()
                case .shop: CosmeticShopView()
                case .odds: OddsView()
                case .living: LivingSettingsView()
                }
            }
        }
    }
}

private struct HomeContent: View {
    @Environment(GameModel.self) private var model
    let creature: Creature
    let now: Date

    var body: some View {
        let current = CareEngine.decay(creature, to: now)
        let stage = CareEngine.stage(creature, at: now)
        let condition = CareEngine.condition(creature, at: now)
        let activity = model.activity(at: now)

        VStack(spacing: 16) {
            VStack(spacing: 8) {
                CreatureSprite(creature: creature, stage: stage, condition: condition,
                               look: model.look(for: creature, activity: activity, now: now))
                    .frame(maxWidth: 260, maxHeight: 260)
                    .frame(maxWidth: .infinity)
                    .opacity(condition == .sleepy ? 0.85 : 1)
                Text(creature.name)
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    Pill(text: Text(stage.title))
                    Pill(text: Text(condition.title))
                    Pill(text: Text(verbatim: CollectingNames.variant(gene: PhenotypeMapper.Gene.temper,
                                                                      variant: PhenotypeMapper.traits(for: creature).temper)))
                }
                if stage != .egg {
                    LikesRow(likes: Likes.derive(for: creature))
                    LivingLineBubble(creature: creature, activity: activity, now: now)
                }
            }
            .card()

            LivingHomeCard(creature: creature, activity: activity, now: now)

            VStack(alignment: .leading, spacing: 10) {
                StatBar(label: "Belly", systemImage: "fork.knife", value: current.hungerValue, tint: Theme.hunger)
                StatBar(label: "Fun", systemImage: "star.fill", value: current.joyValue, tint: Theme.joy)
                StatBar(label: "Mood", systemImage: "heart.fill", value: current.moodValue, tint: Theme.mood)
            }
            .card()

            HStack(spacing: 10) {
                Button { model.care(.feed) } label: { Label("Feed", systemImage: "fork.knife") }
                    .buttonStyle(PixelButtonStyle(tint: Theme.hunger))
                    .disabled(stage == .egg)
                Button { model.care(.play) } label: { Label("Play", systemImage: "star.fill") }
                    .buttonStyle(PixelButtonStyle(tint: Theme.joy))
                    .disabled(stage == .egg)
                Button { model.care(.pet) } label: { Label("Pet", systemImage: "heart.fill") }
                    .buttonStyle(PixelButtonStyle(tint: Theme.mood))
            }
            .sensoryFeedback(.success, trigger: creature.lastUpdated)

            growthCard(stage: stage)

            HatchRushButton(creature: creature, now: now)

            DailySurpriseCard(now: now)

            HStack {
                Spacer()
                OddsLink()
            }

            if condition == .sleepy {
                Text("\(creature.name) is feeling sleepy. A little care will cheer them up!")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func growthCard(stage: Stage) -> some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.accent)
            if let next = CareEngine.nextGrowth(creature, at: now) {
                Text("Becomes \(Text(next.stage.title)) in \(Text(next.date, style: .relative))")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink)
            } else {
                Text("Fully grown — ready to breed!")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink)
            }
            if stage == .teen {
                Text("Can breed")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.joy)
            }
            Spacer()
        }
        .card()
    }
}

struct Pill: View {
    let text: Text
    var body: some View {
        text
            .font(Theme.caption(12))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.background))
            .overlay(Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1))
    }
}

/// Legacy fixed line (superseded on Home by `LivingLineBubble` + `LineService`, §2).
/// No AI label here: these lines are templates.
struct PersonalityLine: View {
    let creature: Creature
    let condition: Condition

    var body: some View {
        VStack(spacing: 2) {
            Text(line)
                .font(Theme.body(14))
                .italic()
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
        }
    }

    private var line: LocalizedStringResource {
        switch condition {
        case .happy: return "Best day ever! Let's play again."
        case .okay: return "Hmm… a snack would be nice."
        case .sleepy: return "So sleepy… a little cuddle?"
        }
    }
}
