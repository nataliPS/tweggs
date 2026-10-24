import SwiftUI
import MixlingsGenome

/// G6 spark sinks. Sparks are EARNED only (daily surprise); there is no way to buy them,
/// and nothing here buys randomness.

/// Small spark balance chip.
struct SparkBalance: View {
    let sparks: Int
    var body: some View {
        Label {
            Text(verbatim: "\(sparks)")
        } icon: {
            Image(systemName: "sparkle")
        }
        .font(Theme.caption(13))
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(sparks) sparks"))
    }
}

/// Hatch-rush: −1 day of growth for 30 sparks, max once per day. Shown on Home.
struct HatchRushButton: View {
    @Environment(GameModel.self) private var model
    let creature: Creature
    let now: Date

    @State private var error: EconomyEngine.SinkError?

    var body: some View {
        let check = EconomyEngine.canHatchRush(model.save, creature: creature, now: now)
        if CareEngine.nextGrowth(creature, at: now) != nil {
            VStack(spacing: 4) {
                Button {
                    if case .failure(let e) = model.hatchRush(creature, now: now) { error = e } else { error = nil }
                } label: {
                    Label("Grow faster · \(EconomyEngine.hatchRushCost) sparks", systemImage: "hare.fill")
                }
                .buttonStyle(PixelButtonStyle(tint: Theme.rarityLegendary))
                .disabled(!check.isSuccess)
                Text(caption(check))
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.inkSoft)
            }
            .sensoryFeedback(.success, trigger: creature.bornAt)
        }
    }

    private func caption(_ check: Result<Void, EconomyEngine.SinkError>) -> LocalizedStringResource {
        switch check {
        case .success: return "Skips 1 day of growing. Once a day."
        case .failure(.alreadyUsedToday): return "Used today. Back tomorrow!"
        case .failure(.notEnoughSparks): return "Earn sparks from the daily surprise."
        case .failure: return "Skips 1 day of growing. Once a day."
        }
    }
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Gene hint (20 sparks per season entry): which of your pairings can produce a missing entry.
struct GeneHintView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Shows which of your pairs can hatch a missing album look. It never changes the odds.")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.inkSoft)
                        Spacer(minLength: 8)
                        SparkBalance(sparks: model.save.sparks)
                    }
                    if let season = CollectingEngine.currentSeason(now: .now) {
                        let missing = EconomyEngine.missingEntries(season, creatures: model.save.activeSlotCreatures)
                        if missing.isEmpty {
                            EmptyStateCard(systemImage: "checkmark.seal.fill", title: "Album complete!",
                                           message: Text("You've found every look this season."))
                        }
                        ForEach(missing, id: \.self) { entry in
                            GeneHintRow(season: season, entry: entry)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Gene hint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

private struct GeneHintRow: View {
    @Environment(GameModel.self) private var model
    let season: Collecting.Season
    let entry: Collecting.SeasonEntry

    var body: some View {
        let unlocked = model.hasGeneHint(season: season, entry: entry)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: CollectingNames.variant(gene: entry.gene, variant: entry.variant))
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !unlocked {
                    Button {
                        model.buyGeneHint(season: season, entry: entry)
                    } label: {
                        Label { Text(verbatim: "\(EconomyEngine.geneHintCost)") } icon: { Image(systemName: "sparkle") }
                    }
                    .buttonStyle(PixelButtonStyle(tint: Theme.rarityLegendary))
                    .frame(width: 110)
                    .disabled(model.save.sparks < EconomyEngine.geneHintCost)
                    .accessibilityLabel(Text("Unlock hint for \(EconomyEngine.geneHintCost) sparks"))
                }
            }
            if unlocked {
                let hint = EconomyEngine.geneHint(entry: entry, creatures: model.save.activeSlotCreatures, now: .now)
                if hint.pairs.isEmpty {
                    Text("None of your pairs can hatch this yet. A friend's Mixling might!")
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.inkSoft)
                } else {
                    ForEach(hint.pairs, id: \.self) { pair in
                        Text(verbatim: pair.compactMap { model.save.creature(id: $0)?.name }.joined(separator: " + "))
                            .font(Theme.caption(13))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
        }
        .card()
    }
}

/// Cosmetic shop (placeholder list, 100–300 sparks). Looks only; never odds.
struct CosmeticShopView: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Decorations for your Mixlings. Sparks come from the daily surprise and can't be bought.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 8)
                    SparkBalance(sparks: model.save.sparks)
                }
                ForEach(EconomyEngine.shopItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.accent)
                            .minTapTarget()
                            .accessibilityHidden(true)
                        Text(verbatim: CollectingNames.cosmetic(item.id))
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        let owned = model.save.cosmetics.filter { $0 == item.id }.count
                        if owned > 0 {
                            Text("Owned ×\(owned)")
                                .font(Theme.caption(11))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Button {
                            model.buy(item)
                        } label: {
                            Label { Text(verbatim: "\(item.price)") } icon: { Image(systemName: "sparkle") }
                        }
                        .buttonStyle(PixelButtonStyle(tint: Theme.rarityLegendary))
                        .frame(width: 110)
                        .disabled(model.save.sparks < item.price)
                        .accessibilityLabel(Text("Buy for \(item.price) sparks"))
                    }
                    .card()
                }
                // TODO(art): real cosmetics (wearable on the sprite); TODO(server): prices via Remote Config.
                Text("Placeholder items. Coming soon: wear them on your Mixlings.")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Spark shop")
        .navigationBarTitleDisplayMode(.inline)
    }
}
