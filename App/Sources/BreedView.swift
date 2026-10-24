import SwiftUI
import MixlingsGenome

/// Breeding (prototype stub).
/// - Pick one of your teens or adults (G4: breeding from day 3).
/// - "Share link" shares a placeholder offer URL with a friend.
/// - "Preview" breeds locally against another of your own creatures with a LOCAL nonce,
///   just to show what a hybrid looks like.
///
/// TODO(server): the real flow is: create offer on server -> server returns offerId + nonce ->
/// friend opens link -> server runs `breed` with its nonce and validates (genome-spec §7).
struct BreedView: View {
    @Environment(GameModel.self) private var model

    @State private var selectedId: String?
    /// Stable per screen visit so the share link doesn't change on every redraw.
    @State private var offerId = BreedView.makeOfferId()
    @State private var preview: BreedPreview?
    @State private var tradeCreature: Creature?
    @State private var cardCreature: Creature?
    @State private var showGeneHint = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let now = Date.now
                    // Sanctuary creatures rest; only active-slot creatures breed.
                    let breeders = model.save.activeSlotCreatures.filter { CareEngine.canBreed($0, at: now) }
                    if !model.socialAllowed {
                        OfflineModeNote()
                    } else if breeders.isEmpty {
                        emptyState(now: now)
                    } else {
                        Text("Choose a parent")
                            .font(Theme.title(18))
                            .foregroundStyle(Theme.ink)
                        if pityActive {
                            pityBanner
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(breeders) { c in
                                    parentCell(c, selected: c.id == currentParent(breeders)?.id,
                                               carrier: pityActive && carrierIds.contains(c.id), now: now)
                                }
                            }
                        }
                        if let parent = currentParent(breeders) {
                            actions(parent: parent)
                        }
                        geneHintRow
                    }
                    if let preview {
                        previewCard(preview)
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Breed")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .sheet(item: $tradeCreature) { c in
                TradeView(creature: c)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $cardCreature) { c in
                CreatureCardScreen(creature: c)
            }
            .sheet(isPresented: $showGeneHint) {
                GeneHintView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Empty state

    /// U1: no teens/adults yet. Says when the first one can breed.
    @ViewBuilder
    private func emptyState(now: Date) -> some View {
        let soonest = model.save.activeSlotCreatures
            .map { CareEngine.breedingDate($0) }
            .filter { $0 > now }
            .min()
        EmptyStateCard(
            systemImage: "heart.circle",
            title: "No parents yet",
            message: soonest.map { Text("Teens and adults can breed. Your first one is ready in \(Text($0, style: .relative)).") }
                ?? Text("Teens and adults can breed. Keep caring for your Mixlings!")
        )
    }

    // MARK: Pity hint (G7)

    private var season: Collecting.Season? { CollectingEngine.currentSeason(now: .now) }

    private var pityActive: Bool { EconomyEngine.pityHintActive(model.save) && season != nil }

    private var carrierIds: Set<String> {
        guard let season else { return [] }
        return EconomyEngine.carrierIds(season: season, creatures: model.save.activeSlotCreatures)
    }

    private var pityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(Theme.rarityLegendary)
            Text("Tip: parents with a glow carry a gene your season album is missing.")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.ink)
        }
        .card(fill: Theme.preview)
    }

    private var geneHintRow: some View {
        Button {
            showGeneHint = true
        } label: {
            Label("Gene hint · \(EconomyEngine.geneHintCost) sparks", systemImage: "sparkle.magnifyingglass")
        }
        .buttonStyle(PixelButtonStyle(tint: Theme.rarityLegendary))
    }

    private func currentParent(_ breeders: [Creature]) -> Creature? {
        breeders.first(where: { $0.id == selectedId }) ?? breeders.first
    }

    private func parentCell(_ c: Creature, selected: Bool, carrier: Bool, now: Date) -> some View {
        let stage = CareEngine.stage(c, at: now)
        return Button {
            selectedId = c.id
            preview = nil
        } label: {
            VStack(spacing: 4) {
                CreatureSprite(creature: c, stage: stage)
                    .frame(width: 84, height: 84)
                Text(c.name)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(stage.title)
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.inkSoft)
            }
            .card(fill: selected ? Theme.preview : Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.rarityLegendary, lineWidth: carrier ? 3 : 0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(c.name))
        .accessibilityHint(carrier ? Text("Carries a missing season gene") : Text(verbatim: ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func actions(parent: Creature) -> some View {
        VStack(spacing: 10) {
            ShareLink(
                item: Self.offerURL(offerId),
                subject: Text(ShareCopy.breedSubject),
                message: Text(ShareCopy.breedMessage(parentName: parent.name))
            ) {
                // U1: the breed rule sits on the button itself.
                VStack(spacing: 2) {
                    Label("Breed with a friend", systemImage: "square.and.arrow.up")
                    Text("Your pet + a friend's = 2 eggs, one each")
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .buttonStyle(PixelButtonStyle(tint: Theme.accent))

            Button {
                preview = makePreview(parent: parent)
            } label: {
                Label("Preview a hybrid", systemImage: "wand.and.stars")
            }
            .buttonStyle(PixelButtonStyle(tint: Theme.joy))
            .disabled(partner(for: parent) == nil)

            // Friend trade stub (free swap, no tokens/fees). TODO(server).
            Button {
                tradeCreature = parent
            } label: {
                Label("Trade", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(PixelButtonStyle(tint: Theme.mood))

            Text("Preview uses a local random seed. Real results are decided when your friend accepts.")
                .font(Theme.caption(11))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private func previewCard(_ p: BreedPreview) -> some View {
        VStack(spacing: 10) {
            Text("Preview")
                .font(Theme.title(16))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                CreatureSprite(creature: p.parentA, stage: CareEngine.stage(p.parentA, at: .now)).frame(width: 64, height: 64)
                Text(verbatim: "+").font(Theme.title(20)).foregroundStyle(Theme.inkSoft)
                CreatureSprite(creature: p.parentB, stage: CareEngine.stage(p.parentB, at: .now)).frame(width: 64, height: 64)
                Text(verbatim: "=").font(Theme.title(20)).foregroundStyle(Theme.inkSoft)
                CreatureSprite(creature: p.child, stage: .adult).frame(width: 64, height: 64)
                CreatureSprite(creature: p.twin, stage: .adult).frame(width: 64, height: 64)
            }
            HStack(spacing: 8) {
                Pill(text: Text(p.tier.title))
                Pill(text: Text("Gen \(p.child.generation)"))
                if p.mutated { Pill(text: Text("Mutation!")) }
            }
            if pityActive, carrierIds.contains(p.parentA.id) || carrierIds.contains(p.parentB.id) {
                Label("A carrier parent is in this pairing", systemImage: "lightbulb.fill")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.ink)
            }
            Button {
                cardCreature = p.child
            } label: {
                Label("Creature card", systemImage: "rectangle.portrait.fill")
            }
            .buttonStyle(PixelButtonStyle(tint: Theme.rarity(p.tier)))
            Text("Your hybrid and your friend's twin")
                .font(Theme.caption(11))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .card(fill: Theme.preview)
    }

    // MARK: Logic

    /// Partner for the local preview: another of the player's own teens/adults.
    /// With the pity hint on, a carrier partner is preferred.
    /// TODO(server): partner comes from the friend's offer.
    private func partner(for parent: Creature) -> Creature? {
        let now = Date.now
        let candidates = model.save.activeSlotCreatures.filter { $0.id != parent.id && CareEngine.canBreed($0, at: now) }
        if pityActive, let carrier = candidates.first(where: { carrierIds.contains($0.id) }) { return carrier }
        return candidates.first
    }

    private func makePreview(parent: Creature) -> BreedPreview? {
        guard let other = partner(for: parent) else { return nil }
        // TODO(server): nonce MUST come from the server; a local nonce is preview-only.
        let localNonce = UUID().uuidString.lowercased()
        let input = BreedInput(
            parentA: Parent(id: parent.id, genome: parent.genome, owner: model.save.playerId),
            parentB: Parent(id: other.id, genome: other.genome, owner: "friend-preview"),
            nonce: localNonce,
            unlockedMutations: [] // TODO: player's unlocked mutations (see Odds screen: 10% once unlocked)
        )
        guard let result = try? Genetics.breed(input),
              let rarity = try? Genetics.rarity(result.genome) else { return nil }
        let myShift = result.paletteShift[model.save.playerId] ?? 0
        let friendShift = result.paletteShift["friend-preview"] ?? 1
        let now = Date.now
        func child(shift: Int) -> Creature {
            // Preview only: not saved, so no serial and no discovery claim.
            let c = Creature(id: result.id, name: "?", genome: result.genome, origin: .bred,
                             paletteShift: shift, bornAt: now, hatchedAt: now)
            return CollectingEngine.withLineage(c, parents: [parent, other])
        }
        return BreedPreview(parentA: parent, parentB: other,
                            child: child(shift: myShift), twin: child(shift: friendShift),
                            tier: rarity.tier, mutated: result.mutation != nil)
    }

    static func offerURL(_ offerId: String) -> URL {
        // TODO(server): offerId is issued by the server; this is a placeholder.
        URL(string: "https://mix.orizolabs.app/b/\(offerId)") ?? URL(string: "https://mix.orizolabs.app")!
    }

    static func makeOfferId() -> String {
        String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12))
    }
}

struct BreedPreview: Equatable {
    let parentA: Creature
    let parentB: Creature
    let child: Creature
    let twin: Creature
    let tier: RarityTier
    let mutated: Bool
}
