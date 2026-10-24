import SwiftUI

/// Hatch the first egg: tap the egg a few times -> it hatches -> name the baby ->
/// receive a free starter adult so breeding is possible from day one.
struct OnboardingView: View {
    @Environment(GameModel.self) private var model

    private enum Step { case egg, name, starter }

    @State private var step: Step = .egg
    @State private var taps = 0
    @State private var name = ""
    @State private var egg: Creature?

    private let tapsToHatch = 3

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            switch step {
            case .egg: eggStep
            case .name: nameStep
            case .starter: starterStep
            }
            Spacer(minLength: 12)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            if egg == nil { egg = model.prepareFirstEgg() }
        }
    }

    private var eggStep: some View {
        VStack(spacing: 20) {
            Text("Welcome to Mixlings")
                .font(Theme.title(28))
                .foregroundStyle(Theme.ink)
            Text("Your first egg is ready. Tap it to help it hatch!")
                .font(Theme.body())
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            if let egg {
                Button {
                    taps += 1
                    if taps >= tapsToHatch { step = .name }
                } label: {
                    CreatureSprite(creature: egg, stage: .egg)
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(taps.isMultiple(of: 2) ? -4 : 4))
                        .card()
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact, trigger: taps)
                Text("\(tapsToHatch - min(taps, tapsToHatch)) taps left")
                    .font(Theme.caption(13))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private var nameStep: some View {
        VStack(spacing: 20) {
            Text("It hatched!")
                .font(Theme.title(28))
                .foregroundStyle(Theme.ink)
            if let egg {
                CreatureSprite(creature: egg, stage: .baby)
                    .frame(width: 200, height: 200)
                    .card()
            }
            TextField("Name your Mixling", text: $name)
                .font(Theme.body(18))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(12)
                .card()
            Button("Continue") {
                model.completeOnboarding(babyName: name)
                step = .starter
            }
            .buttonStyle(PixelButtonStyle())
        }
    }

    private var starterStep: some View {
        VStack(spacing: 20) {
            Text("A gift for you")
                .font(Theme.title(28))
                .foregroundStyle(Theme.ink)
            Text("Here is a grown-up Mixling to keep your baby company. Adults can breed with friends' Mixlings.")
                .font(Theme.body())
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            if let adult = model.pendingStarter {
                CreatureSprite(creature: adult, stage: .adult)
                    .frame(width: 180, height: 180)
                    .card()
                Text(adult.name)
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.ink)
            }
            Button("Let's play!") {
                model.finishOnboarding()
            }
            .buttonStyle(PixelButtonStyle())
        }
    }
}
