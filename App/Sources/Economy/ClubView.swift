import SwiftUI

/// C7 Mix Club paywall: price, period, when the trial converts, how to cancel,
/// Restore Purchases, Terms and Privacy. Same odds for everyone (stated on screen).
///
/// TODO(storekit): load `Product`s for the ids below, show `product.displayPrice` and
/// `subscription.introductoryOffer`, purchase with `product.purchase()`, restore with
/// `AppStore.sync()`, and set membership from `Transaction.currentEntitlements` only.
/// Prices below are placeholders (project brief: $3.99/mo, $24.99/yr, 7-day trial).
struct ClubView: View {
    @Environment(GameModel.self) private var model

    enum Plan: String, CaseIterable, Identifiable {
        case yearly, monthly
        var id: String { rawValue }

        /// TODO(storekit): real product ids in App Store Connect.
        var productId: String { "com.orizolabs.mixlings.club.\(rawValue)" }
        /// Placeholder; replace with `Product.displayPrice` (localized by the App Store).
        var placeholderPrice: String { self == .yearly ? "$24.99" : "$3.99" }
        var period: LocalizedStringResource {
            switch self {
            case .yearly: return "per year"
            case .monthly: return "per month"
            }
        }
    }

    static let trialDays = 7
    /// TODO(legal): real URLs.
    static let termsURL = URL(string: "https://mix.orizolabs.app/terms")!
    static let privacyURL = URL(string: "https://mix.orizolabs.app/privacy")!

    @State private var plan: Plan = .yearly
    @State private var restoreMessage: LocalizedStringResource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("More room and more style for your Mixlings. Odds are the same for every player.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.inkSoft)

                VStack(alignment: .leading, spacing: 8) {
                    perk("\(EconomyEngine.clubSlots) active slots instead of \(EconomyEngine.freeSlots)", "square.grid.3x3.fill")
                    perk("Every widget size and theme", "rectangle.3.group.fill")
                    perk("Season palettes", "paintpalette.fill")
                    perk("More personality lines", "text.bubble.fill")
                    perk("Biome decorations", "leaf.fill")
                    Text("The sanctuary is free and unlimited for everyone.")
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.inkSoft)
                }
                .card()

                ForEach(Plan.allCases) { p in
                    Button {
                        plan = p
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p == .yearly ? LocalizedStringKey("Yearly") : LocalizedStringKey("Monthly"))
                                    .font(Theme.body(16))
                                Text(verbatim: p.placeholderPrice + " ")
                                    .font(Theme.title(20))
                                + Text(p.period)
                                    .font(Theme.caption(12))
                            }
                            Spacer()
                            Image(systemName: plan == p ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(plan == p ? Theme.accent : Theme.cardStroke)
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: Theme.minTapTarget)
                        .card(fill: plan == p ? Theme.preview : Theme.card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(plan == p ? .isSelected : [])
                }

                Button {
                    // TODO(storekit): purchase `plan.productId`.
                } label: {
                    Text("Try \(Self.trialDays) days free")
                }
                .buttonStyle(PixelButtonStyle(tint: Theme.accent))

                // C7 disclosures: trial conversion date, price, period, cancel.
                Text(disclosure)
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.inkSoft)

                HStack(spacing: 4) {
                    Button("Restore Purchases") {
                        // TODO(storekit): try await AppStore.sync(), then re-check entitlements.
                        restoreMessage = "No purchases to restore yet."
                    }
                    .minTapTarget()
                    Spacer()
                    Link("Terms", destination: Self.termsURL).minTapTarget()
                    Link("Privacy", destination: Self.privacyURL).minTapTarget()
                }
                .font(Theme.caption(13))

                if let restoreMessage {
                    Text(restoreMessage)
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.inkSoft)
                }

                OddsLink()

                #if DEBUG
                Toggle("Debug: Club member", isOn: Binding(get: { model.save.isClubMember },
                                                          set: { model.setClubMember($0) }))
                    .font(Theme.caption(12))
                #endif
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Mix Club")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Free for 7 days, then $24.99 per year starting <date>. Renews automatically until you cancel..."
    private var disclosure: Text {
        let conversion = Calendar.current.date(byAdding: .day, value: Self.trialDays, to: .now) ?? .now
        return Text("Free for \(Self.trialDays) days, then \(plan.placeholderPrice) \(Text(plan.period)) starting \(Text(conversion, format: .dateTime.day().month().year())). Renews automatically until you cancel. Cancel any time in Settings > Apple ID > Subscriptions at least 24 hours before the trial ends and you won't be charged.")
    }

    private func perk(_ text: LocalizedStringKey, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(Theme.body(14))
            .foregroundStyle(Theme.ink)
    }
}
