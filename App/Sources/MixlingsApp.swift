import SwiftUI

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
                .onChange(of: scenePhase) { _, phase in
                    // Widget intents write to the shared file while we're backgrounded.
                    if phase == .active { model.reload() }
                }
        }
    }
}

struct RootView: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.needsOnboarding {
                OnboardingView()
            } else {
                MainTabs()
            }
        }
        .tint(Theme.accent)
        .sheet(item: $model.incomingOffer) { offer in
            IncomingOfferView(offer: offer)
                .presentationDetents([.medium])
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            CollectionView()
                .tabItem { Label("Collection", systemImage: "square.grid.2x2.fill") }
            BreedView()
                .tabItem { Label("Breed", systemImage: "heart.circle.fill") }
        }
    }
}

/// Stub for an opened breeding link.
struct IncomingOfferView: View {
    let offer: GameModel.IncomingOffer
    @Environment(\.dismiss) private var dismiss

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
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
