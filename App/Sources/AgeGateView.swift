import SwiftUI

/// C2: neutral age screen. Asks for a birth year with no default and no hint of a "right"
/// answer; only the resulting band is stored (on device). Under 13 -> offline mode.
/// Shown by `RootView` whenever `model.needsAgeCheck` (new players and v2 saves, once).
/// TODO(age-range): try `AgeGate.declaredAgeBand()` (Declared Age Range API) before showing this.
struct AgeGateView: View {
    @Environment(GameModel.self) private var model

    @State private var year: Int?
    @State private var savedBand: AgeBand?

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            if let savedBand, !savedBand.socialAllowed {
                offlineNotice
            } else {
                question
            }
            Spacer(minLength: 12)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .task {
            if let band = await AgeGate.declaredAgeBand() { save(band) }
        }
    }

    private var question: some View {
        VStack(spacing: 20) {
            Image(systemName: "birthday.cake.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("What year were you born?")
                .font(Theme.title(26))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("This stays on your phone and helps us set up the game for you.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Picker("Birth year", selection: $year) {
                Text("Choose a year").tag(Int?.none)
                ForEach(AgeGate.selectableYears(), id: \.self) { y in
                    Text(verbatim: String(y)).tag(Int?.some(y))
                }
            }
            .pickerStyle(.wheel)
            .frame(maxHeight: 160)
            .card()
            Button("Continue") {
                guard let year else { return }
                save(AgeGate.band(birthYear: year))
            }
            .buttonStyle(PixelButtonStyle())
            .disabled(year == nil)
        }
    }

    private var offlineNotice: some View {
        VStack(spacing: 20) {
            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.joy)
                .accessibilityHidden(true)
            Text("You're all set!")
                .font(Theme.title(26))
                .foregroundStyle(Theme.ink)
            Text("You can hatch, care for and collect Mixlings. Breeding with friends, trading and sharing stay off for now.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Button("Let's go") { model.setAgeBand(.under13) }
                .buttonStyle(PixelButtonStyle(tint: Theme.joy))
        }
    }

    /// 13+: saved at once (RootView moves on). Under 13: show the friendly notice first and
    /// save on "Let's go".
    private func save(_ band: AgeBand) {
        if band.socialAllowed {
            model.setAgeBand(band)
        } else {
            savedBand = band
        }
    }
}

/// Shown where a social feature would be, for under-13 (offline mode) players.
struct OfflineModeNote: View {
    var body: some View {
        EmptyStateCard(
            systemImage: "house.and.flag.fill",
            title: "Offline mode",
            message: Text("Breeding with friends, trading and sharing are turned off. You can still hatch, care for and collect Mixlings.")
        )
    }
}
