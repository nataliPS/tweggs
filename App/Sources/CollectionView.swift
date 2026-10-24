import SwiftUI
import MixlingsGenome

struct CollectionView: View {
    @Environment(GameModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.creatures) { creature in
                        Button {
                            model.select(creature)
                        } label: {
                            CollectionCell(creature: creature,
                                           isActive: creature.id == model.active?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Collection")
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
    }
}

private struct CollectionCell: View {
    let creature: Creature
    let isActive: Bool

    var body: some View {
        let now = Date.now
        let stage = CareEngine.stage(creature, at: now)
        let tier = (try? Genetics.rarity(creature.genome))?.tier ?? .common
        VStack(spacing: 6) {
            CreatureSprite(creature: creature, stage: stage)
                .frame(width: 80, height: 80)
            Text(creature.name)
                .font(Theme.body(13))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text(tier.title)
                .font(Theme.caption(10))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .card(fill: isActive ? Theme.preview : Theme.card)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

extension RarityTier {
    var title: LocalizedStringResource {
        switch self {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .legendary: return "Legendary"
        }
    }
}
