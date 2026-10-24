import SwiftUI
import MixlingsGenome

/// Breeding (prototype stub).
/// - Pick one of your adults.
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let adults = model.creatures.filter { CareEngine.stage($0, at: .now) == .adult }
                    if adults.isEmpty {
                        Text("Only adults can breed. Keep caring for your Mixling!")
                            .font(Theme.body())
                            .foregroundStyle(Theme.inkSoft)
                            .card()
                    } else {
                        Text("Choose a parent")
                            .font(Theme.title(18))
                            .foregroundStyle(Theme.ink)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(adults) { adult in
                                    parentCell(adult, selected: adult.id == currentParent(adults)?.id)
                                }
                            }
                        }
                        if let parent = currentParent(adults) {
                            actions(parent: parent)
                        }
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
        }
    }

    private func currentParent(_ adults: [Creature]) -> Creature? {
        adults.first(where: { $0.id == selectedId }) ?? adults.first
    }

    private func parentCell(_ c: Creature, selected: Bool) -> some View {
        Button {
            selectedId = c.id
            preview = nil
        } label: {
            VStack(spacing: 4) {
                CreatureSprite(creature: c, stage: .adult)
                    .frame(width: 84, height: 84)
                Text(c.name)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.ink)
            }
            .card(fill: selected ? Theme.preview : Theme.card)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actions(parent: Creature) -> some View {
        VStack(spacing: 10) {
            ShareLink(
                item: Self.offerURL(offerId),
                subject: Text("Breed with my Mixling!"),
                message: Text("Let's mix our Mixlings! \(parent.name) is waiting.")
            ) {
                Label("Share link", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PixelButtonStyle(tint: Theme.accent))

            Button {
                preview = makePreview(parent: parent)
            } label: {
                Label("Preview a hybrid", systemImage: "wand.and.stars")
            }
            .buttonStyle(PixelButtonStyle(tint: Theme.joy))
            .disabled(partner(for: parent) == nil)

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
                CreatureSprite(creature: p.parentA, stage: .adult).frame(width: 64, height: 64)
                Text(verbatim: "+").font(Theme.title(20)).foregroundStyle(Theme.inkSoft)
                CreatureSprite(creature: p.parentB, stage: .adult).frame(width: 64, height: 64)
                Text(verbatim: "=").font(Theme.title(20)).foregroundStyle(Theme.inkSoft)
                CreatureSprite(creature: p.child, stage: .adult).frame(width: 64, height: 64)
                CreatureSprite(creature: p.twin, stage: .adult).frame(width: 64, height: 64)
            }
            HStack(spacing: 8) {
                Pill(text: Text(p.tier.title))
                if p.mutated { Pill(text: Text("Mutation!")) }
            }
            Text("Your hybrid and your friend's twin")
                .font(Theme.caption(11))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .card(fill: Theme.preview)
    }

    // MARK: Logic

    /// Partner for the local preview: another of the player's own adults/creatures.
    /// TODO(server): partner comes from the friend's offer.
    private func partner(for parent: Creature) -> Creature? {
        model.creatures.first(where: {
            $0.id != parent.id && CareEngine.stage($0, at: .now) == .adult
        })
    }

    private func makePreview(parent: Creature) -> BreedPreview? {
        guard let other = partner(for: parent) else { return nil }
        // TODO(server): nonce MUST come from the server; a local nonce is preview-only.
        let localNonce = UUID().uuidString.lowercased()
        let input = BreedInput(
            parentA: Parent(id: parent.id, genome: parent.genome, owner: model.save.playerId),
            parentB: Parent(id: other.id, genome: other.genome, owner: "friend-preview"),
            nonce: localNonce,
            unlockedMutations: [] // TODO: player's unlocked mutations
        )
        guard let result = try? Genetics.breed(input),
              let rarity = try? Genetics.rarity(result.genome) else { return nil }
        let myShift = result.paletteShift[model.save.playerId] ?? 0
        let friendShift = result.paletteShift["friend-preview"] ?? 1
        let now = Date.now
        func child(shift: Int) -> Creature {
            Creature(id: result.id, name: "?", genome: result.genome, origin: .bred,
                     paletteShift: shift, bornAt: now, hatchedAt: now)
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
