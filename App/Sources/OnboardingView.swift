import SwiftUI

/// Onboarding (after the C2 age screen in `RootView`): tap the egg a few times -> it hatches -> reveal:
/// "Name it" first, then "Record video" (U1) -> free starter adult -> first-share prompt
/// "Make a baby with a friend" with the breed link ready (U1/H3, 13+ only).
struct OnboardingView: View {
    @Environment(GameModel.self) private var model

    private enum Step { case egg, reveal, starter, share }

    @State private var step: Step = .egg
    @State private var taps = 0
    @State private var name = ""
    @State private var nameError: LocalizedStringResource?
    @State private var named = false
    @State private var egg: Creature?
    /// Creature whose card is shown (hatched baby).
    @State private var cardCreature: Creature?
    @State private var clipCreature: Creature?
    /// Stable for this onboarding so the shared link doesn't change.
    @State private var offerId = BreedView.makeOfferId()

    private let tapsToHatch = 3

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 12)
                switch step {
                case .egg: eggStep
                case .reveal: revealStep
                case .starter: starterStep
                case .share: shareStep
                }
                Spacer(minLength: 12)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            if egg == nil { egg = model.prepareFirstEgg() }
        }
        .sheet(item: $cardCreature) { c in
            CreatureCardScreen(creature: c)
        }
        .sheet(item: $clipCreature) { c in
            HatchClipScreen(creature: c)
        }
    }

    private var hatched: Creature? {
        guard let id = egg?.id else { return nil }
        return model.save.creature(id: id)
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
                    if taps >= tapsToHatch { step = .reveal }
                } label: {
                    CreatureSprite(creature: egg, stage: .egg)
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(taps.isMultiple(of: 2) ? -4 : 4))
                        .card()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Egg"))
                .sensoryFeedback(.impact, trigger: taps)
                Text("\(tapsToHatch - min(taps, tapsToHatch)) taps left")
                    .font(Theme.caption(13))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    /// Reveal: "Name it" comes before "Record video" (U1).
    private var revealStep: some View {
        VStack(spacing: 18) {
            Text("It hatched!")
                .font(Theme.title(28))
                .foregroundStyle(Theme.ink)
            if let egg {
                CreatureSprite(creature: hatched ?? egg, stage: .baby)
                    .frame(width: 200, height: 200)
                    .card()
            }
            if !named {
                TextField("Name your Mixling", text: $name)
                    .font(Theme.body(18))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(nameIt)
                    .frame(minHeight: Theme.minTapTarget)
                    .padding(.horizontal, 12)
                    .card()
                    .onChange(of: name) { _, _ in nameError = nil }
                if let nameError {
                    Text(nameError)
                        .font(Theme.caption(13))
                        .foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.center)
                }
                Button(action: nameIt) {
                    Label("Name it", systemImage: "pencil")
                }
                .buttonStyle(PixelButtonStyle())
            } else {
                if let hatched {
                    Text(hatched.name)
                        .font(Theme.title(24))
                        .foregroundStyle(Theme.ink)
                    if model.socialAllowed {
                        Button {
                            clipCreature = hatched
                        } label: {
                            Label("Record hatch video", systemImage: "video.fill")
                        }
                        .buttonStyle(PixelButtonStyle(tint: Theme.rarityRare))
                    }
                }
                Button("Continue") { step = .starter }
                    .buttonStyle(PixelButtonStyle())
            }
        }
    }

    private func nameIt() {
        let verdict = NameFilter.check(name)
        guard case .ok(let clean) = verdict else {
            nameError = NameFilter.message(for: verdict)
            return
        }
        model.completeOnboarding(babyName: clean)
        named = true
    }

    private var starterStep: some View {
        VStack(spacing: 20) {
            Text("A gift for you")
                .font(Theme.title(28))
                .foregroundStyle(Theme.ink)
            Text("Here is a grown-up Mixling to keep your baby company. Teens and adults can breed with friends' Mixlings.")
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
            Text("Another baby arrives tomorrow!")
                .font(Theme.caption(13))
                .foregroundStyle(Theme.inkSoft)
            if let baby = hatched {
                Button {
                    cardCreature = baby
                } label: {
                    Label("See \(baby.name)'s card", systemImage: "rectangle.portrait.fill")
                }
                .buttonStyle(PixelButtonStyle(tint: Theme.rarityRare))
            }
            Button("Let's play!") {
                if model.socialAllowed && !model.save.firstSharePromptShown {
                    step = .share
                } else {
                    model.finishOnboarding()
                }
            }
            .buttonStyle(PixelButtonStyle())
        }
    }

    /// U1/H3: first share within ~2 minutes. The breed link is ready to send.
    private var shareStep: some View {
        VStack(spacing: 20) {
            Text("Make a baby with a friend")
                .font(Theme.title(26))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            if let adult = model.pendingStarter {
                HStack(spacing: 10) {
                    CreatureSprite(creature: adult, stage: .adult)
                        .frame(width: 96, height: 96)
                    Text(verbatim: "+")
                        .font(Theme.title(26))
                        .foregroundStyle(Theme.inkSoft)
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.cardStroke)
                        .frame(width: 96, height: 96)
                }
                .card()
                Text("Send \(adult.name)'s link. The rarest Mixlings only hatch with friends!")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                ShareLink(
                    item: BreedView.offerURL(offerId),
                    subject: Text(ShareCopy.breedSubject),
                    message: Text(ShareCopy.breedMessage(parentName: adult.name))
                ) {
                    Label("Send to a friend", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PixelButtonStyle(tint: Theme.accent))
            }
            Button("Let's play!") {
                model.finishOnboarding()
            }
            .buttonStyle(PixelButtonStyle(tint: Theme.cardStroke))
        }
        .onAppear { model.markFirstSharePromptShown() }
    }
}
