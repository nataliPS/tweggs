import SwiftUI
import MixlingsArt

// "Хвилинка спокою" (docs/wellbeing-spec.md, MVP). Native to the creature's world, opt-in,
// templates only (no AI), no rewards, nothing leaves the device.

private func wtext(_ id: String) -> String { WellbeingContent.shared.text(id) }

/// DEBUG-only banner while any wellbeing text lacks expert sign-off.
struct WellbeingReviewBanner: View {
    var body: some View {
        #if DEBUG
        if WellbeingContent.shared.pendingReview {
            Label { Text(verbatim: wtext("review.pending")) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                .font(Theme.caption(12))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.orange)
                .accessibilityAddTraits(.isStaticText)
        }
        #else
        EmptyView()
        #endif
    }
}

/// Home chip near the creature.
struct CalmChip: View {
    var body: some View {
        NavigationLink {
            CalmView()
        } label: {
            Label { Text(verbatim: wtext("calm.title")) } icon: { Image(systemName: "leaf.fill") }
                .font(Theme.caption(12))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.joy.opacity(0.18)))
                .overlay(Capsule().strokeBorder(Theme.joy.opacity(0.6), lineWidth: 1))
                .frame(minHeight: Theme.minTapTarget)
        }
        .buttonStyle(.plain)
    }
}

/// "I'm having a hard time": always reachable (Home menu, Settings, Calm screen). Also shown
/// in under-13 offline mode.
struct HardTimeButton: View {
    @State private var show = false

    var body: some View {
        Button {
            show = true
        } label: {
            Label { Text(verbatim: wtext("hardtime.button")) } icon: { Image(systemName: "hand.raised.fill") }
                .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
        }
        .tint(Theme.mood)
        .fullScreenCover(isPresented: $show) { HardTimeFlow() }
    }
}

/// The Calm screen: three MVP practices + wind-down + the hard-time button.
struct CalmView: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                WellbeingReviewBanner()
                if let c = model.active {
                    CreatureSprite(creature: c, stage: CareEngine.stage(c, at: .now),
                                   condition: CareEngine.condition(c, at: .now))
                        .frame(width: 140, height: 140)
                }
                Text(verbatim: wtext("calm.subtitle"))
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)

                practiceLink(title: "breathe.title", subtitle: "breathe.intro", systemImage: "wind",
                             tint: Theme.joy) { BreatheView(practice: .breathe) }
                practiceLink(title: "grounding.title", subtitle: "grounding.subtitle", systemImage: "hand.tap.fill",
                             tint: Theme.accent) { GroundingView() }
                practiceLink(title: "winddown.title", subtitle: "winddown.toggleFooter", systemImage: "moon.haze.fill",
                             tint: Theme.cardLabel) { WindDownView() }

                HardTimeButton()
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 6)

                Text(verbatim: wtext("calm.private"))
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: wtext("calm.title")))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.recordWellbeingOpen(.calmScreen) }
    }

    private func practiceLink<Destination: View>(title: String, subtitle: String, systemImage: String, tint: Color,
                                                 @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: wtext(title)).font(Theme.body(16)).foregroundStyle(Theme.ink)
                    Text(verbatim: wtext(subtitle)).font(Theme.caption(12)).foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft).accessibilityHidden(true)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Breathe with me

/// The creature inflates as you breathe in and deflates as you breathe out.
/// Art hook: `ArtAdapter.breathingFrame(phase:phenotype:)`; until the artist adds frames the
/// normal sprite is scaled.
struct BreatheView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which practice this counts as (the hard-time flow reuses it).
    var practice: WellbeingPractice = .breathe
    /// Hard-time flow: start at once with 1 min 4-6 and call `onFinish` at the end.
    var autoStart = false
    var onFinish: (() -> Void)? = nil

    @State private var rhythm: BreathingRhythm = .fourSix
    @State private var minutes = 1
    @State private var haptics = false
    @State private var startedAt: Date?
    @State private var finished = false
    @State private var calmerAnswered = false

    var body: some View {
        VStack(spacing: 16) {
            WellbeingReviewBanner()
            if let startedAt {
                TimelineView(.animation) { ctx in
                    let session = BreathingSession(rhythm: rhythm, minutes: minutes)
                    let state = session.state(elapsed: ctx.date.timeIntervalSince(startedAt))
                    running(state: state)
                        .onChange(of: state.phase == .done) { _, done in if done { finish() } }
                }
            } else if finished {
                doneView
            } else {
                setup
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: wtext("breathe.title")))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if practice == .breathe { model.recordWellbeingOpen(.breathe) }
            if autoStart, startedAt == nil, !finished { startedAt = .now }
        }
    }

    private var setup: some View {
        VStack(spacing: 16) {
            sprite(fill: 0.5)
            Text(verbatim: wtext("breathe.intro"))
                .font(Theme.body(15)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Picker(selection: $rhythm) {
                ForEach(BreathingRhythm.allCases) { r in Text(verbatim: r.rawValue).tag(r) }
            } label: { Text(verbatim: wtext("breathe.rhythm")) }
                .pickerStyle(.segmented)
            Picker(selection: $minutes) {
                Text(verbatim: wtext("breathe.minutes1")).tag(1)
                Text(verbatim: wtext("breathe.minutes2")).tag(2)
            } label: { Text(verbatim: wtext("breathe.length")) }
                .pickerStyle(.segmented)
            Toggle(isOn: $haptics) { Text(verbatim: wtext("breathe.haptic")).font(Theme.body(15)) }
            Button { startedAt = .now } label: { Text(verbatim: wtext("breathe.start")) }
                .buttonStyle(PixelButtonStyle(tint: Theme.joy))
        }
    }

    private func running(state: BreathingSession.State) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            sprite(fill: state.fill)
            Text(verbatim: wtext(state.phase == .breatheIn ? "breathe.in" : "breathe.out"))
                .font(Theme.title(26))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 0)
            Button { finish() } label: { Text(verbatim: wtext("breathe.stop")) }
                .buttonStyle(PixelButtonStyle(tint: Theme.cardStroke))
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: state.step) { _, _ in haptics }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            sprite(fill: 0.3)
            Text(verbatim: wtext("breathe.done"))
                .font(Theme.body(16)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            if onFinish == nil {
                if calmerAnswered {
                    Text(verbatim: wtext("calmer.thanks")).font(Theme.caption(12)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text(verbatim: wtext("calmer.question")).font(Theme.caption(13)).foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 10) {
                        Button { answer(true) } label: { Text(verbatim: wtext("calmer.yes")) }
                            .buttonStyle(.bordered)
                        Button { answer(false) } label: { Text(verbatim: wtext("calmer.no")) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sprite(fill: Double) -> some View {
        if let c = model.active {
            let stage = CareEngine.stage(c, at: .now)
            let p = PhenotypeMapper.phenotype(for: c, stage: stage)
            let amplitude = reduceMotion ? 0.08 : 0.28
            Group {
                if let cg = ArtAdapter.breathingFrame(phase: fill, phenotype: p) {
                    Image(decorative: cg, scale: 1).interpolation(.none).resizable().aspectRatio(1, contentMode: .fit)
                } else {
                    CreatureSprite(creature: c, stage: stage)
                        .scaleEffect(x: 0.82 + amplitude * fill, y: 0.82 + amplitude * 0.8 * fill)
                }
            }
            .frame(width: 200, height: 200)
            .accessibilityHidden(true)
        }
    }

    private func finish() {
        guard !finished else { return }
        let completed = startedAt.map { Date.now.timeIntervalSince($0) >= 20 } ?? false
        startedAt = nil
        finished = true
        // The calm pose shows for any real attempt; no reward of any kind.
        if completed { model.finishBreathing() }
        onFinish?()
    }

    private func answer(_ yes: Bool) {
        model.recordCalmer(yes)
        calmerAnswered = true
    }
}

// MARK: - Grounding 5-4-3-2-1

enum GroundingStep: Int, CaseIterable, Sendable {
    case see = 5, touch = 4, hear = 3, smell = 2, taste = 1

    var count: Int { rawValue }
    var textId: String {
        switch self {
        case .see: return "grounding.see"
        case .touch: return "grounding.touch"
        case .hear: return "grounding.hear"
        case .smell: return "grounding.smell"
        case .taste: return "grounding.taste"
        }
    }
    var systemImage: String {
        switch self {
        case .see: return "eye.fill"
        case .touch: return "hand.raised.fill"
        case .hear: return "ear.fill"
        case .smell: return "nose.fill"
        case .taste: return "mouth.fill"
        }
    }

    /// Steps in order: 5 see … 1 taste.
    static let ordered: [GroundingStep] = [.see, .touch, .hear, .smell, .taste]
}

/// Tap-to-advance only: no typing, nothing stored except an anonymous completion count.
struct GroundingView: View {
    @Environment(GameModel.self) private var model
    var countsAsOpen = true
    var onFinish: (() -> Void)? = nil

    @State private var stepIndex = 0
    @State private var taps = 0

    private var done: Bool { stepIndex >= GroundingStep.ordered.count }

    var body: some View {
        VStack(spacing: 18) {
            WellbeingReviewBanner()
            if let c = model.active {
                CreatureSprite(creature: c, stage: CareEngine.stage(c, at: .now))
                    .frame(width: 120, height: 120)
            }
            if done {
                Text(verbatim: wtext("grounding.done"))
                    .font(Theme.title(22)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            } else {
                let step = GroundingStep.ordered[stepIndex]
                Text(verbatim: wtext("grounding.intro"))
                    .font(Theme.caption(12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                Image(systemName: step.systemImage)
                    .font(.system(size: 40)).foregroundStyle(Theme.accent).accessibilityHidden(true)
                Text(verbatim: wtext(step.textId))
                    .font(Theme.title(22)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    ForEach(0..<step.count, id: \.self) { i in
                        Circle()
                            .fill(i < taps ? Theme.joy : Theme.cardStroke)
                            .frame(width: 18, height: 18)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(taps) / \(step.count)"))
                Button { tap(step) } label: { Text(verbatim: wtext("grounding.tap")) }
                    .buttonStyle(PixelButtonStyle(tint: Theme.joy))
                    .sensoryFeedback(.selection, trigger: taps)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: wtext("grounding.subtitle")))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if countsAsOpen { model.recordWellbeingOpen(.grounding) } }
    }

    private func tap(_ step: GroundingStep) {
        taps += 1
        guard taps >= step.count else { return }
        taps = 0
        stepIndex += 1
        if done {
            model.recordWellbeingCompletion(.grounding)
            onFinish?()
        }
    }
}

// MARK: - Evening wind-down

/// The creature yawns, the lights dim, one kind thought about the day.
struct WindDownView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var dim = false
    @State private var yawn = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            // "Lights dim": a soft dark layer under the content, so the text stays readable.
            Color.black.opacity(dim ? 0.6 : 0).ignoresSafeArea()
            VStack(spacing: 18) {
                WellbeingReviewBanner()
                Spacer(minLength: 0)
                if let c = model.active {
                    CreatureSprite(creature: c, stage: CareEngine.stage(c, at: .now), condition: .sleepy,
                                   look: LivingLook(weather: .night))
                        .frame(width: 180, height: 180)
                        .scaleEffect(x: yawn ? 1.06 : 1, y: yawn ? 0.92 : 1, anchor: .bottom)
                }
                Text(verbatim: wtext("winddown.yawn"))
                    .font(Theme.body(16)).italic()
                    .foregroundStyle(dim ? Color.white.opacity(0.85) : Theme.inkSoft)
                Text(verbatim: WellbeingContent.shared.windDownThought(now: .now))
                    .font(Theme.title(22))
                    .foregroundStyle(dim ? Color.white : Theme.ink)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Button { dismiss() } label: { Text(verbatim: wtext("winddown.goodnight")) }
                    .buttonStyle(PixelButtonStyle(tint: Theme.cardLabel))
            }
            .padding(16)
        }
        .navigationTitle(Text(verbatim: wtext("winddown.title")))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.recordWellbeingOpen(.windDown)
            withAnimation(.easeInOut(duration: 1.2).repeatCount(3, autoreverses: true)) { yawn = true }
            withAnimation(.easeInOut(duration: 3)) { dim = true }
        }
        .onDisappear { model.recordWellbeingCompletion(.windDown) }
    }
}
