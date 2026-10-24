import SwiftUI
import MixlingsGenome

/// C5 "Шанси" (Odds): every random outcome in the game, published in-app. Values are read from
/// MixlingsGenome so the screen can't drift from the engine. Randomness is never sold.
/// TODO(server): when live-ops values move to Remote Config (T5), read them from there.
enum Odds {
    static var surpriseSparksPercent: Int { Collecting.surpriseSparksChance }
    static var surpriseCosmeticPercent: Int { 100 - Collecting.surpriseSparksChance }
    static var sparksMin: Int { Collecting.surpriseSparksMin }
    static var sparksMax: Int { Collecting.surpriseSparksMax }
    static var cosmeticCount: Int { Collecting.surpriseCosmetics.count }
    static var mutationPercent: Int { Int((Genetics.mutationChance * 100).rounded()) }
}

struct OddsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("The same odds for everyone, Club or not. You can never buy a re-roll.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)

                section(title: "Daily surprise", systemImage: "gift.fill") {
                    row(Text("Sparks (\(Odds.sparksMin)–\(Odds.sparksMax), each amount equally likely)"),
                        percent: Odds.surpriseSparksPercent)
                    row(Text("Souvenir (one of \(Odds.cosmeticCount), equally likely)"),
                        percent: Odds.surpriseCosmeticPercent)
                    Text("One free surprise per day. It's decided by the day, so opening it later doesn't change it.")
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.inkSoft)
                }

                section(title: "Mutations", systemImage: "wand.and.stars") {
                    row(Text("Chance per breed, once you've unlocked a mutation"), percent: Odds.mutationPercent)
                    Text("Before any mutation is unlocked the chance is 0%. Each gene a baby gets is one of the two genes from each parent, picked at random.")
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Odds")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<Content: View>(title: LocalizedStringKey, systemImage: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(Theme.title(17))
                .foregroundStyle(Theme.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func row(_ label: Text, percent: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            label
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Text(verbatim: "\(percent)%")
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.rarityRare)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small link used on Home and Club.
struct OddsLink: View {
    var body: some View {
        NavigationLink {
            OddsView()
        } label: {
            Label("Odds", systemImage: "percent")
                .font(Theme.caption(13))
                .minTapTarget()
        }
    }
}
