import SwiftUI
import MixlingsGenome

/// "Щоденний сюрприз": Home card. Once per local day, free, deterministic
/// (`Collecting.dailySurprise`). There is intentionally NO purchase, ad or re-roll path.
struct DailySurpriseCard: View {
    @Environment(GameModel.self) private var model
    let now: Date

    @State private var opened: Collecting.Souvenir?

    var body: some View {
        let canOpen = model.canOpenSurprise(now: now)
        HStack(spacing: 12) {
            Image(systemName: canOpen ? "gift.fill" : "gift")
                .font(.system(size: 26))
                .foregroundStyle(canOpen ? Theme.accent : Theme.inkSoft)
                .frame(width: 44, height: 44)
                .symbolEffect(.bounce, value: canOpen)
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily surprise")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.ink)
                if let opened, !canOpen {
                    SouvenirText(souvenir: opened)
                } else if canOpen {
                    Text("A free surprise is waiting!")
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.inkSoft)
                } else {
                    Text("Next surprise in \(Text(CollectingEngine.nextDayStart(after: now), style: .relative))")
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 0)
            if canOpen {
                Button("Open") {
                    opened = model.openDailySurprise(now: now)
                }
                .buttonStyle(PixelButtonStyle(tint: Theme.accent))
                .frame(width: 96)
            } else {
                Label {
                    Text(verbatim: "\(model.save.sparks)")
                } icon: {
                    Image(systemName: "sparkle")
                }
                .font(Theme.caption(13))
                .foregroundStyle(Theme.ink)
                .accessibilityLabel(Text("\(model.save.sparks) sparks"))
            }
        }
        .card()
        .sensoryFeedback(.success, trigger: opened)
    }
}

struct SouvenirText: View {
    let souvenir: Collecting.Souvenir

    var body: some View {
        switch souvenir {
        case .sparks(let amount):
            Text("You got \(amount) sparks!")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.ink)
        case .cosmetic(let id):
            // TODO(art): cosmetics are placeholders until they can be worn.
            Text("You got a souvenir: \(CollectingNames.cosmetic(id))")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.ink)
        }
    }
}
