import SwiftUI
import MixlingsGenome

/// "Обміняти" (friend trade) — PLACEHOLDER flow, UI + local model only.
///
/// Rules: a trade is a free swap between friends. No tokens, no fees, no money, no marketplace.
/// TODO(server): create the offer on the server, escrow the creature, let the friend pick one of
/// theirs in return, and swap on both confirmations. Until then nothing actually moves.
struct TradeView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let creature: Creature

    @State private var offer: TradeOffer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                CreatureSprite(creature: creature, stage: CareEngine.stage(creature, at: .now))
                    .frame(width: 120, height: 120)
                    .card()
                Text("Offer \(creature.name) to a friend")
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("Trades are free swaps between friends. Your friend picks a Mixling to give back, and nothing moves until you both agree.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)

                if let offer, offer.status == .draft {
                    ShareLink(
                        item: offer.url,
                        subject: Text(ShareCopy.tradeSubject),
                        message: Text(ShareCopy.tradeMessage(name: creature.name))
                    ) {
                        Label("Share trade link", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PixelButtonStyle(tint: Theme.accent))

                    Button(role: .destructive) {
                        model.cancelTradeOffer(offer)
                        self.offer = nil
                    } label: {
                        Label("Cancel offer", systemImage: "xmark")
                    }
                    .buttonStyle(PixelButtonStyle(tint: Theme.cardStroke))
                } else {
                    Button {
                        offer = model.createTradeOffer(for: creature)
                    } label: {
                        Label("Trade", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(PixelButtonStyle(tint: Theme.mood))
                }

                Text("Trading with friends is coming soon. For now this only creates a link.")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                offer = model.save.tradeOffers.first { $0.creatureId == creature.id && $0.status == .draft }
            }
        }
    }
}
