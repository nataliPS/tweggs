import SwiftUI

/// Home speech bubble (§2). Template line by default; an on-device AI line when one was made.
/// The "Lines written by on-device AI" label shows only when the line really came from AI.
struct LivingLineBubble: View {
    @Environment(GameModel.self) private var model
    let creature: Creature
    let activity: Activity
    let now: Date

    var body: some View {
        let line = (model.aiLine.flatMap { $0.byAI ? $0 : nil })
            ?? LineService.homeLine(for: creature, activity: activity, now: now)
        VStack(spacing: 2) {
            Text(verbatim: line.text)
                .font(Theme.body(14))
                .italic()
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            if line.byAI {
                Text("Lines written by on-device AI")
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

/// Likes & dislikes chip row (§13), shown on Home and the card.
struct LikesRow: View {
    let likes: Likes
    var onDark = false

    var body: some View {
        HStack(spacing: 10) {
            Label { Text("Loves \(Text(likes.likes.title))") } icon: { Image(systemName: "heart.fill") }
            Label { Text("Not a fan of \(Text(likes.dislikes.title))") } icon: { Image(systemName: "hand.thumbsdown.fill") }
        }
        .font(Theme.caption(11))
        .foregroundStyle(onDark ? Theme.cardLabel : Theme.inkSoft)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Living-world card on Home: what the creature is up to, weather care items, idea bubble,
/// links to the house and the jump rope.
struct LivingHomeCard: View {
    @Environment(GameModel.self) private var model
    let creature: Creature
    let activity: Activity
    let now: Date

    @State private var showRope = false
    @State private var showHouse = false
    @State private var lastOutcome: LivingEngine.ItemOutcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow
            if activity.weather != .none {
                itemTray
            }
            if model.ideaAvailable(now: now) {
                ideaBubble
            }
            HStack(spacing: 10) {
                Button { showHouse = true } label: { Label("House", systemImage: "house.lodge.fill") }
                    .buttonStyle(PixelButtonStyle(tint: Theme.cardStroke))
                Button { showRope = true } label: { Label("Jump rope", systemImage: "figure.jumprope") }
                    .buttonStyle(PixelButtonStyle(tint: Theme.joy))
                    .disabled(CareEngine.stage(creature, at: now) == .egg)
            }
        }
        .card()
        .sheet(isPresented: $showRope) { JumpRopeView(creature: creature) }
        .sheet(isPresented: $showHouse) {
            NavigationStack {
                HouseView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { showHouse = false } }
                    }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: activity.isNight ? "moon.zzz.fill" : (activity.scene?.systemImage ?? activity.weather.systemImage))
                .foregroundStyle(Theme.accent)
            if activity.isNight {
                Text("Sleepy time").font(Theme.body(14))
            } else if let s = activity.scene {
                Text(s.title).font(Theme.body(14))
            } else {
                Text(activity.weather.title).font(Theme.body(14))
            }
            Spacer()
            if let h = activity.holiday {
                Label { Text(h.title) } icon: { Image(systemName: h.systemImage) }
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.ink)
    }

    private var itemTray: some View {
        let suggested = LivingEngine.suggestedItems(for: activity.weather)
        let feeling = Likes.derive(for: creature).feeling(about: activity.weather)
        return VStack(alignment: .leading, spacing: 6) {
            switch feeling {
            case .loves:
                Text("\(creature.name) loves this weather!").font(Theme.caption(12)).foregroundStyle(Theme.joy)
            case .dislikes:
                Text("\(creature.name) isn't a fan of this weather. A little help?")
                    .font(Theme.caption(12)).foregroundStyle(Theme.inkSoft)
            case .neutral:
                EmptyView()
            }
            if suggested.isEmpty {
                // Wind: no item (§1). Just a comment.
                Text("Hold on to your ears!").font(Theme.caption(12)).foregroundStyle(Theme.inkSoft)
            } else {
                HStack(spacing: 8) {
                    ForEach(suggested) { item in
                        Button {
                            lastOutcome = model.giveItem(item, now: .now)
                        } label: {
                            Label { Text(item.title) } icon: { Image(systemName: item.systemImage) }
                                .font(Theme.caption(12))
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                    }
                }
            }
            if let lastOutcome {
                outcomeText(lastOutcome)
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.joy)
            }
        }
    }

    @ViewBuilder
    private func outcomeText(_ o: LivingEngine.ItemOutcome) -> some View {
        switch o {
        case .rewarded(let sparks) where sparks > 0:
            Text("Thank you! +\(sparks) sparks")
        case .rewarded, .alreadyRewarded:
            Text("Thank you! So cosy.")
        case .notNeeded:
            Text("Thanks! Maybe another day.")
        case .noCreature:
            EmptyView()
        }
    }

    private var ideaBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill").foregroundStyle(Theme.hunger)
            Text("I have an idea! Jump rope?")
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button("Let's go") { model.consumeIdea(); showRope = true }
                .font(Theme.caption(12))
                .buttonStyle(.borderedProminent)
                .tint(Theme.joy)
            Button { model.consumeIdea() } label: {
                Image(systemName: "xmark").accessibilityLabel(Text("Not now"))
            }
            .font(Theme.caption(12))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.inkSoft)
            .minTapTarget()
        }
    }
}
