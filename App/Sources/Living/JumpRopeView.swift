import SwiftUI
import MixlingsArt

/// Pure jump-rope rules (§8), separate from the view so they are testable.
/// The rope turns once per `period`; the player taps when the rope is under the feet
/// (phase ≈ 0.5). The rope speeds up as the combo grows. A miss resets the combo, never the score.
struct JumpRopeGame: Equatable, Sendable {
    static let duration: TimeInterval = 30          // within the 20–40 s spec window
    static let startPeriod: TimeInterval = 1.0
    static let minPeriod: TimeInterval = 0.5
    static let speedUpPerJump: TimeInterval = 0.02
    /// Half-width of the "good" window around the under-the-feet phase, in rope turns.
    static let window: Double = 0.18

    var startedAt: Date
    var score = 0
    var combo = 0
    var bestCombo = 0
    var misses = 0
    /// Rope phase accumulated up to `phaseAnchor` (turns), so speed changes don't jump the rope.
    var phaseAtAnchor: Double = 0
    var phaseAnchor: Date
    var period: TimeInterval = JumpRopeGame.startPeriod
    /// Turn index already jumped (one jump per turn).
    var lastJumpTurn: Int = -1
    var lastTripAt: Date?
    var lastJumpAt: Date?

    init(startedAt: Date) {
        self.startedAt = startedAt
        self.phaseAnchor = startedAt
    }

    func phase(at date: Date) -> Double {
        phaseAtAnchor + max(0, date.timeIntervalSince(phaseAnchor)) / period
    }

    func isOver(at date: Date) -> Bool { date.timeIntervalSince(startedAt) >= Self.duration }

    func timeLeft(at date: Date) -> TimeInterval { max(0, Self.duration - date.timeIntervalSince(startedAt)) }

    enum TapResult: Equatable { case jump, miss, ignored }

    mutating func tap(at date: Date) -> TapResult {
        guard !isOver(at: date) else { return .ignored }
        let p = phase(at: date)
        let turn = Int(p.rounded(.down))
        let frac = p - Double(turn)
        if abs(frac - 0.5) <= Self.window, turn != lastJumpTurn {
            lastJumpTurn = turn
            combo += 1
            bestCombo = max(bestCombo, combo)
            score += 1 + min(combo / 5, 4) // combo bonus, capped
            lastJumpAt = date
            // Re-anchor, then speed up.
            phaseAtAnchor = p
            phaseAnchor = date
            period = max(Self.minPeriod, period - Self.speedUpPerJump)
            return .jump
        }
        combo = 0
        misses += 1
        lastTripAt = date
        return .miss
    }

    /// Art frame: 0...3 rope loop, 4 trip, 5 cheer.
    func frame(at date: Date) -> Int {
        if isOver(at: date) { return ArtAdapter.jumpRopeCheerFrame }
        if let t = lastTripAt, date.timeIntervalSince(t) < 0.35 { return ArtAdapter.jumpRopeTripFrame }
        let p = phase(at: date)
        let f = Int(((p - p.rounded(.down)) * Double(ArtAdapter.jumpRopeLoopFrames)).rounded(.down))
        return min(max(0, f), ArtAdapter.jumpRopeLoopFrames - 1)
    }
}

struct JumpRopeView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let creature: Creature

    @State private var game: JumpRopeGame?
    @State private var result: LivingEngine.RopeResult?
    @State private var finalScore = 0
    @State private var finalCombo = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let game {
                    TimelineView(.animation) { context in
                        playfield(game: game, now: context.date)
                            .onChange(of: game.isOver(at: context.date)) { _, over in
                                if over { finish(game) }
                            }
                    }
                } else if let result {
                    resultCard(result)
                } else {
                    intro
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Jump rope")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private var intro: some View {
        VStack(spacing: 14) {
            yard(frame: 0, jumpHeight: 0)
            Text("Tap when the rope is under \(creature.name)'s feet!")
                .font(Theme.body(15))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            if model.living.jumpRopeBest > 0 {
                Text("Personal best: \(model.living.jumpRopeBest)")
                    .font(Theme.caption(13))
                    .foregroundStyle(Theme.inkSoft)
            }
            Button("Start") { game = JumpRopeGame(startedAt: .now) }
                .buttonStyle(PixelButtonStyle(tint: Theme.joy))
                .frame(maxWidth: 220)
        }
    }

    private func playfield(game: JumpRopeGame, now: Date) -> some View {
        let frame = game.frame(at: now)
        let p = game.phase(at: now)
        let frac = p - p.rounded(.down)
        let height = frame == ArtAdapter.jumpRopeTripFrame ? 0 : max(0, sin(frac * .pi)) * 18
        return VStack(spacing: 12) {
            HStack {
                Label { Text(verbatim: "\(Int(game.timeLeft(at: now).rounded(.up)))") } icon: { Image(systemName: "timer") }
                Spacer()
                Text("Combo \(game.combo)")
                Spacer()
                Text("Score \(game.score)")
            }
            .font(Theme.caption(14))
            .foregroundStyle(Theme.ink)
            .monospacedDigit()
            yard(frame: frame, jumpHeight: height, ropePhase: frac)
                .contentShape(Rectangle())
                .onTapGesture { tap() }
            Button { tap() } label: {
                Label("Jump!", systemImage: "arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PixelButtonStyle(tint: Theme.accent))
            .sensoryFeedback(.impact(weight: .light), trigger: game.score)
        }
    }

    private func tap() {
        guard var g = game else { return }
        _ = g.tap(at: .now)
        game = g
    }

    private func finish(_ g: JumpRopeGame) {
        guard game != nil else { return }
        finalScore = g.score
        finalCombo = g.bestCombo
        result = model.finishJumpRope(score: g.score, bestCombo: g.bestCombo)
        game = nil
    }

    private func resultCard(_ r: LivingEngine.RopeResult) -> some View {
        VStack(spacing: 12) {
            yard(frame: ArtAdapter.jumpRopeCheerFrame, jumpHeight: 0)
            Text(r.newBest ? LocalizedStringKey("New personal best!") : LocalizedStringKey("Great jumping!"))
                .font(Theme.title(22))
                .foregroundStyle(Theme.ink)
            Text("Score \(finalScore) · best combo \(finalCombo)")
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkSoft)
            if r.sparks > 0 {
                Label("+\(r.sparks) sparks", systemImage: "sparkles")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.accent)
            }
            if r.gotRope {
                Label("The jump rope joined your collection!", systemImage: "figure.jumprope")
                    .font(Theme.caption(13))
                    .foregroundStyle(Theme.joy)
            }
            HStack {
                Button("Again") { result = nil; game = JumpRopeGame(startedAt: .now) }
                    .buttonStyle(PixelButtonStyle(tint: Theme.joy))
                Button("Done") { dismiss() }
                    .buttonStyle(PixelButtonStyle(tint: Theme.cardStroke))
            }
        }
    }

    /// Art frame when available, else a Canvas rope around the sprite.
    @ViewBuilder
    private func yard(frame: Int, jumpHeight: Double, ropePhase: Double = 0) -> some View {
        let stage = CareEngine.stage(creature, at: .now)
        let p = PhenotypeMapper.phenotype(for: creature, stage: stage, condition: .happy)
        if let cg = ArtAdapter.jumpRopeImage(p, frame: frame) {
            Image(decorative: cg, scale: 1)
                .interpolation(.none)
                .resizable()
                .aspectRatio(ArtAdapter.sceneSize, contentMode: .fit)
                .card()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.joy.opacity(0.18))
                Canvas { ctx, size in
                    // Rope: an ellipse arc whose vertical position follows the phase.
                    let cx = size.width / 2, w = size.width * 0.38
                    let y = size.height * (0.5 - 0.42 * cos(ropePhase * 2 * .pi))
                    var path = Path()
                    path.move(to: CGPoint(x: cx - w, y: size.height * 0.55))
                    path.addQuadCurve(to: CGPoint(x: cx + w, y: size.height * 0.55), control: CGPoint(x: cx, y: y))
                    let front = ropePhase > 0.25 && ropePhase < 0.75
                    ctx.stroke(path, with: .color(front ? Theme.mood : Theme.mood.opacity(0.45)), lineWidth: 3)
                }
                CreatureSprite(creature: creature, stage: stage, condition: .happy)
                    .frame(width: 120, height: 120)
                    .offset(y: -jumpHeight)
                    .rotationEffect(.degrees(frame == ArtAdapter.jumpRopeTripFrame ? 12 : 0))
            }
            .aspectRatio(ArtAdapter.sceneSize, contentMode: .fit)
        }
    }
}
