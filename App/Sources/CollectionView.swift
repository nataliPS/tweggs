import SwiftUI
import MixlingsGenome
import MixlingsArt

/// Collection tab: segmented "Колекція / Енциклопедія / Сезон".
struct CollectionView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case collection, encyclopedia, season
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .collection: return "Collection"
            case .encyclopedia: return "Encyclopedia"
            case .season: return "Season"
            }
        }
    }

    @State private var segment: Segment = .collection

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Section", selection: $segment) {
                        ForEach(Segment.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch segment {
                    case .collection: CollectionGrid()
                    case .encyclopedia: EncyclopediaView()
                    case .season: SeasonAlbumView()
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Collection")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                CreatureDetailView(creatureId: id)
            }
        }
    }
}

// MARK: - Collection grid

private struct CollectionGrid: View {
    @Environment(GameModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(model.creatures) { creature in
                NavigationLink(value: creature.id) {
                    CollectionCell(creature: creature, isActive: creature.id == model.active?.id)
                }
                .buttonStyle(.plain)
            }
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
            HStack(spacing: 4) {
                Circle().fill(Theme.rarity(tier)).frame(width: 7, height: 7)
                Text(tier.title)
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.inkSoft)
                if creature.discoveredFirst {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.rarityLegendary)
                        .accessibilityLabel(Text("Discoverer"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .card(fill: isActive ? Theme.preview : Theme.card)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Detail

/// Collection detail: sprite, facts, and actions (make active, card, trade).
struct CreatureDetailView: View {
    @Environment(GameModel.self) private var model
    let creatureId: String

    @State private var showCard = false
    @State private var showTrade = false

    var body: some View {
        if let creature = model.save.creature(id: creatureId) {
            let stage = CareEngine.stage(creature, at: .now)
            let tier = (try? Genetics.rarity(creature.genome))?.tier ?? .common
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        CreatureSprite(creature: creature, stage: stage)
                            .frame(width: 200, height: 200)
                        Text(creature.name)
                            .font(Theme.title(24))
                            .foregroundStyle(Theme.ink)
                        HStack(spacing: 8) {
                            Pill(text: Text(tier.title))
                            Pill(text: Text(stage.title))
                            Pill(text: Text("Gen \(creature.generation)"))
                            if creature.discoveredFirst { Pill(text: Text("Discoverer")) }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .card()

                    VStack(spacing: 10) {
                        Button {
                            showCard = true
                        } label: {
                            Label("Creature card", systemImage: "rectangle.portrait.fill")
                        }
                        .buttonStyle(PixelButtonStyle(tint: Theme.rarity(tier)))

                        if creature.id != model.active?.id {
                            Button {
                                model.select(creature)
                            } label: {
                                Label("Make active", systemImage: "house.fill")
                            }
                            .buttonStyle(PixelButtonStyle(tint: Theme.joy))
                        }

                        if stage != .egg {
                            Button {
                                showTrade = true
                            } label: {
                                Label("Trade", systemImage: "arrow.left.arrow.right")
                            }
                            .buttonStyle(PixelButtonStyle(tint: Theme.mood))
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(creature.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCard) {
                CreatureCardScreen(creature: creature)
            }
            .sheet(isPresented: $showTrade) {
                TradeView(creature: creature)
                    .presentationDetents([.medium, .large])
            }
        } else {
            Text("This Mixling is no longer here.")
                .font(Theme.body())
                .foregroundStyle(Theme.inkSoft)
        }
    }
}

// MARK: - Encyclopedia

/// Every look (combo key) ever seen on this device, from the local `DiscoveryLog`.
/// TODO(server): global encyclopedia with first discoverer's name.
private struct EncyclopediaView: View {
    @Environment(GameModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 10)]

    var body: some View {
        let entries = model.save.discoveries.entries
            .sorted { $0.value.date != $1.value.date ? $0.value.date < $1.value.date : $0.key < $1.key }
        VStack(alignment: .leading, spacing: 12) {
            Text("\(entries.count) looks discovered")
                .font(Theme.title(18))
                .foregroundStyle(Theme.ink)
            if entries.isEmpty {
                Text("Hatch and breed Mixlings to fill your encyclopedia.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(entries, id: \.key) { item in
                    if let t = CollectingEngine.traits(forComboKey: item.key, seedId: item.value.creatureId) {
                        MixlingView(PhenotypeMapper.phenotype(t))
                            .frame(width: 64, height: 64)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.cardStroke, lineWidth: 1.5))
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Season album

/// "Сезонні колекції": album of the current season. A slot is found when any owned creature
/// EXPRESSES that variant; missing slots show a silhouette.
struct SeasonAlbumView: View {
    @Environment(GameModel.self) private var model
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        if let season = CollectingEngine.currentSeason(now: .now) {
            let progress = CollectingEngine.seasonProgress(season, creatures: model.creatures)
            let found = progress.filter { $0 }.count
            let hasBadge = model.save.seasonBadges.contains(season.id)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: CollectingNames.season(season))
                            .font(Theme.title(24))
                            .foregroundStyle(Theme.ink)
                        if let left = CollectingEngine.daysLeft(season, now: .now) {
                            Text("\(left) days left")
                                .font(Theme.caption(13))
                                .foregroundStyle(Theme.inkSoft)
                        } else {
                            Text("Season ended")
                                .font(Theme.caption(13))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Spacer()
                    Text(verbatim: "\(found)/\(season.entries.count)")
                        .font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.rarityRare)
                }

                ProgressView(value: Double(found), total: Double(max(1, season.entries.count)))
                    .tint(Theme.rarityRare)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(season.entries.enumerated()), id: \.offset) { i, entry in
                        SeasonSlot(entry: entry, found: progress.indices.contains(i) && progress[i],
                                   owner: CollectingEngine.owner(of: entry, in: model.creatures))
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(hasBadge ? Theme.cardFace : Theme.inkSoft)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(hasBadge ? Theme.rarityLegendary : Theme.cardStroke))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasBadge ? LocalizedStringKey("Season badge earned!") : LocalizedStringKey("Season badge"))
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.ink)
                        Text("Find all variants to earn the badge. Breeding with friends helps!")
                            .font(Theme.caption(12))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                .card()
            }
        } else {
            Text("No season right now.")
                .font(Theme.body())
                .foregroundStyle(Theme.inkSoft)
        }
    }
}

private struct SeasonSlot: View {
    let entry: Collecting.SeasonEntry
    let found: Bool
    let owner: Creature?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if found, let owner {
                    CreatureSprite(creature: owner, stage: .adult)
                } else {
                    CreatureSprite(creature: CollectingEngine.sampleCreature(for: entry), stage: .adult,
                                   silhouette: true)
                        .foregroundStyle(Theme.ink.opacity(0.18))
                }
            }
            .frame(width: 56, height: 56)
            Text(verbatim: found ? CollectingNames.variant(gene: entry.gene, variant: entry.variant) : "???")
                .font(Theme.caption(11))
                .foregroundStyle(found ? Theme.ink : Theme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(found ? Theme.card : Theme.slotEmpty))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(found ? Theme.cardStroke : Theme.slotStroke,
                          style: StrokeStyle(lineWidth: 1.5, dash: found ? [] : [4, 3])))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(found
            ? Text(verbatim: CollectingNames.variant(gene: entry.gene, variant: entry.variant))
            : Text("Not found yet"))
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
