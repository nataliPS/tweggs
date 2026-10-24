import SwiftUI
import BackgroundTasks

@main
@MainActor
struct MixlingsApp: App {
    @State private var model = GameModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { url in
                    model.handle(url: url)
                }
                // Cold launch: scenePhase may already be .active, so onChange won't fire.
                .task { model.livingDidBecomeActive() }
                .onChange(of: scenePhase) { _, phase in
                    // Widget intents write to the shared file while we're backgrounded.
                    if phase == .active {
                        model.reload()
                        model.livingDidBecomeActive()
                    } else if phase == .background {
                        model.livingWillResignActive()
                        LivingWeatherService.shared.scheduleBackgroundRefresh()
                    }
                }
        }
        // §1: weather refresh at most every 3 h (BGAppRefresh; id listed in Info.plist).
        .backgroundTask(.appRefresh(LivingWeatherService.refreshTaskId)) {
            await LivingWeatherService.shared.refreshInBackground()
        }
    }
}

struct RootView: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.needsAgeCheck {
                // C2: asked once, before anything else (also for players from older saves).
                AgeGateView()
            } else if model.needsOnboarding {
                OnboardingView()
            } else {
                MainTabs()
            }
        }
        .tint(Theme.accent)
        .sheet(item: $model.incomingOffer) { offer in
            if model.socialAllowed {
                IncomingOfferView(offer: offer)
                    .presentationDetents([.medium, .large])
            } else {
                // C2 offline mode: links from friends don't open social flows.
                OfflineModeNote()
                    .padding(24)
                    .presentationDetents([.medium])
            }
        }
        .sheet(item: $model.newGift) { gift in
            DayTwoGiftView(gift: gift)
                .presentationDetents([.medium])
        }
        // §9: "While you were away" (after the gift sheet, never both at once).
        .sheet(item: Binding(get: { model.newGift == nil && !model.needsOnboarding ? model.awayDiary : nil },
                             set: { model.awayDiary = $0 })) { diary in
            AwayDiaryView(diary: diary)
                .presentationDetents([.medium, .large])
        }
    }
}

struct MainTabs: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            CollectionView()
                .tabItem { Label("Collection", systemImage: "square.grid.2x2.fill") }
            // C2: no Breed tab in offline mode (under 13).
            if model.socialAllowed {
                BreedView()
                    .tabItem { Label("Breed", systemImage: "heart.circle.fill") }
            }
        }
    }
}

/// G4: the day-2 starter baby.
struct DayTwoGiftView: View {
    let gift: Creature
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("A new baby arrived!")
                .font(Theme.title(24))
                .foregroundStyle(Theme.ink)
            CreatureSprite(creature: gift, stage: .baby)
                .frame(width: 140, height: 140)
                .card()
            Text("\(gift.name) can breed once it's a teen, in 2 days.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Button("Yay!") { dismiss() }
                .buttonStyle(PixelButtonStyle())
                .frame(maxWidth: 200)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// Stub for an opened breeding link, with C3 safety entry points (Report / Block).
struct IncomingOfferView: View {
    @Environment(GameModel.self) private var model
    let offer: GameModel.IncomingOffer
    @Environment(\.dismiss) private var dismiss
    @State private var confirmBlock = false
    @State private var reported = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("A friend wants to breed!")
                .font(Theme.title(22))
                .foregroundStyle(Theme.ink)
            Text("Offer \(offer.id)")
                .font(Theme.caption(13))
                .foregroundStyle(Theme.inkSoft)
            // TODO(server): load friend's creature + server nonce, let player pick a parent, breed.
            Text("Breeding with friends is coming soon.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Button("OK") { dismiss() }
                .buttonStyle(PixelButtonStyle())
                .frame(maxWidth: 200)

            // C3: report / block cover the sender's creature names too.
            // TODO(server): send the report (offer id, reason) and block by sender account.
            HStack(spacing: 12) {
                Button {
                    model.report(offer: offer)
                    reported = true
                } label: {
                    Label(reported ? LocalizedStringKey("Reported") : LocalizedStringKey("Report"),
                          systemImage: "exclamationmark.bubble")
                }
                .disabled(reported)
                Button(role: .destructive) {
                    confirmBlock = true
                } label: {
                    Label("Block", systemImage: "hand.raised.fill")
                }
            }
            .font(Theme.caption(13))
            .buttonStyle(.bordered)
            .controlSize(.large)
            .confirmationDialog("Block this player?", isPresented: $confirmBlock, titleVisibility: .visible) {
                Button("Block", role: .destructive) { model.block(offer: offer) }
            } message: {
                Text("You won't see their breeding or trade links any more.")
            }
            if reported {
                Text("Thanks. We'll take a look.")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
