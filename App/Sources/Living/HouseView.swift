import SwiftUI
import MixlingsArt

/// §9 pair life: the tiny house where two of your creatures live their own day.
struct HouseView: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        ScrollView {
            if let a = model.active {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HouseContent(a: a, b: model.partner, now: context.date)
                }
                .padding(16)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("House")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HouseContent: View {
    @Environment(GameModel.self) private var model
    let a: Creature
    let b: Creature?
    let now: Date

    var body: some View {
        let act = model.activity(at: now)
        VStack(spacing: 16) {
            RoomView(a: a, b: b, activity: act, now: now)
            VStack(spacing: 6) {
                if let scene = act.scene {
                    Label { Text(scene.title) } icon: { Image(systemName: scene.systemImage) }
                        .font(Theme.title(18))
                        .foregroundStyle(Theme.ink)
                } else if act.isNight {
                    Label("Sleeping", systemImage: "moon.zzz.fill")
                        .font(Theme.title(18))
                        .foregroundStyle(Theme.ink)
                } else {
                    Label { Text(act.weather.title) } icon: { Image(systemName: act.weather.systemImage) }
                        .font(Theme.title(18))
                        .foregroundStyle(Theme.ink)
                }
                if act.scene == .chatting {
                    Text(verbatim: LineService.chatBubble(seed: "\(a.id)|\(Int(now.timeIntervalSince1970 / 600))"))
                        .font(.system(size: 22))
                }
                if let h = act.holiday {
                    Label { Text(h.title) } icon: { Image(systemName: h.systemImage) }
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.accent)
                }
            }
            .card()

            if b == nil {
                Text("Hatch or welcome a second Mixling and they'll move in together.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .card()
            } else {
                partnerPicker
            }

            upcoming
        }
    }

    private var partnerPicker: some View {
        let others = model.creatures.filter { $0.id != a.id && CareEngine.stage($0, at: now) != .egg }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Housemate")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(others) { c in
                        Button { model.setHousePartner(c) } label: {
                            VStack(spacing: 2) {
                                CreatureSprite(creature: c, stage: CareEngine.stage(c, at: now))
                                    .frame(width: 48, height: 48)
                                Text(c.name).font(Theme.caption(11)).lineLimit(1)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(c.id == b?.id ? Theme.accent : Theme.cardStroke, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }

    private var upcoming: some View {
        let next = ActivityStateMachine.schedule(from: now, context: model.activityContext(now: now),
                                                 step: 3600, horizon: 6 * 3600).dropFirst()
        return VStack(alignment: .leading, spacing: 6) {
            Text("Later today")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.inkSoft)
            ForEach(Array(next.enumerated()), id: \.offset) { _, e in
                HStack {
                    Text(e.date, format: .dateTime.hour().minute())
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 56, alignment: .leading)
                    if let s = e.activity.scene {
                        Label { Text(s.title) } icon: { Image(systemName: s.systemImage) }
                    } else if e.activity.isNight {
                        Label("Sleeping", systemImage: "moon.zzz.fill")
                    } else {
                        Label { Text(e.activity.weather.title) } icon: { Image(systemName: e.activity.weather.systemImage) }
                    }
                    Spacer()
                }
                .font(Theme.body(13))
                .foregroundStyle(Theme.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// The 64x48 room from MixlingsArt, or a SwiftUI fallback (two sprites + symbol + sky tint).
struct RoomView: View {
    @Environment(GameModel.self) private var model
    let a: Creature
    let b: Creature?
    let activity: Activity
    let now: Date

    var body: some View {
        let sa = CareEngine.stage(a, at: now)
        let pa = PhenotypeMapper.phenotype(for: a, stage: sa)
        let pb = b.map { PhenotypeMapper.phenotype(for: $0, stage: CareEngine.stage($0, at: now)) }
        Group {
            if let pb, let cg = ArtAdapter.roomImage(pa, pb, scene: activity.scene, night: activity.isNight,
                                                     weather: activity.weather,
                                                     decorations: activity.holiday?.decorations ?? []) {
                Image(decorative: cg, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(ArtAdapter.sceneSize, contentMode: .fit)
            } else {
                ZStack {
                    LinearGradient(colors: activity.isNight
                                   ? [Color(red: 0.16, green: 0.14, blue: 0.32), Color(red: 0.28, green: 0.24, blue: 0.45)]
                                   : [Theme.preview, Theme.background],
                                   startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .bottom, spacing: 8) {
                        CreatureSprite(creature: a, stage: sa,
                                       look: model.look(for: a, activity: activity, now: now))
                            .scaleEffect(x: -1, y: 1)
                        if let b {
                            CreatureSprite(creature: b, stage: CareEngine.stage(b, at: now))
                        }
                    }
                    .padding(12)
                    if let s = activity.scene {
                        Image(systemName: s.systemImage)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(activity.isNight ? .white : Theme.ink)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    if let h = activity.holiday {
                        Image(systemName: h.systemImage)
                            .foregroundStyle(Theme.accent)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .aspectRatio(ArtAdapter.sceneSize, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(Text(activity.scene?.title ?? activity.weather.title))
    }
}

/// "While you were away" sheet (§9).
struct AwayDiaryView: View {
    let diary: AwayDiary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("While you were away")
                .font(Theme.title(22))
                .foregroundStyle(Theme.ink)
            ForEach(Array(diary.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "book.closed.fill").foregroundStyle(Theme.accent)
                    Text(verbatim: line)
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.ink)
                }
            }
            if diary.moreCount > 0 {
                Text("…and more")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
            }
            Button("Nice!") { dismiss() }
                .buttonStyle(PixelButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
    }
}
