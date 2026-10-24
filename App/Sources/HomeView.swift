import SwiftUI

struct HomeView: View {
    @Environment(GameModel.self) private var model

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

        VStack(spacing: 16) {
            VStack(spacing: 8) {
                CreatureSprite(creature: creature, stage: stage)
                    .frame(maxWidth: 260, maxHeight: 260)
                    .frame(maxWidth: .infinity)
                    .opacity(condition == .sleepy ? 0.85 : 1)
                Text(creature.name)
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    Pill(text: Text(stage.title))
                    Pill(text: Text(condition.title))
                    Pill(text: Text(PhenotypeMapper.temperName(PhenotypeMapper.traits(for: creature)).capitalized))
                }
            }
            .card()

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
