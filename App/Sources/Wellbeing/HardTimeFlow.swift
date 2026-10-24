import SwiftUI

private func wtext(_ id: String) -> String { WellbeingContent.shared.text(id) }

/// "I'm having a hard time": breathe → grounding → helplines. Every step can be skipped and
/// "Talk to a person now" jumps straight to the helplines. No judgement, nothing collected
/// (only the anonymous open count). Works offline and in under-13 offline mode.
struct HardTimeFlow: View {
    @Environment(GameModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Step: Int, CaseIterable { case intro, breathe, grounding, helplines }
    @State private var step: Step = .intro

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if step != .helplines {
                    Button { go(.helplines) } label: {
                        Label { Text(verbatim: wtext("hardtime.talkNow")) } icon: { Image(systemName: "phone.fill") }
                            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.mood)
                    .padding(16)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(verbatim: wtext("hardtime.close")) }
                }
                if step == .breathe || step == .grounding {
                    ToolbarItem(placement: .primaryAction) {
                        Button { advance() } label: { Text(verbatim: wtext("hardtime.skip")) }
                    }
                }
            }
        }
        .onAppear { model.recordWellbeingOpen(.hardTime) }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro:
            VStack(spacing: 18) {
                WellbeingReviewBanner()
                Spacer(minLength: 0)
                if let c = model.active {
                    CreatureSprite(creature: c, stage: CareEngine.stage(c, at: .now))
                        .frame(width: 150, height: 150)
                }
                Text(verbatim: wtext("hardtime.intro"))
                    .font(Theme.title(22)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                Button { advance() } label: { Text(verbatim: wtext("hardtime.next")) }
                    .buttonStyle(PixelButtonStyle(tint: Theme.joy))
                Spacer(minLength: 0)
            }
            .padding(16)
        case .breathe:
            BreatheView(practice: .hardTime, autoStart: true, onFinish: { advance() })
        case .grounding:
            GroundingView(countsAsOpen: false, onFinish: { advance() })
        case .helplines:
            HelplinesView()
        }
    }

    private func advance() {
        go(Step(rawValue: step.rawValue + 1) ?? .helplines)
    }

    private func go(_ s: Step) {
        withAnimation(.easeInOut(duration: 0.3)) { step = s }
    }
}

/// Static, offline helpline table (`Helplines.json`). TODO: verify numbers before release (Щит).
/// The device region comes first; lines without a verified number show only the name + the
/// "find a helpline" link. Nothing is logged except one anonymous open count.
struct HelplinesView: View {
    @Environment(GameModel.self) private var model
    var directory: HelplineDirectory = .shared
    var region: String? = HelplineDirectory.deviceRegion

    var body: some View {
        let split = directory.ordered(region: region)
        List {
            Section {
                WellbeingReviewBanner()
                    .listRowInsets(EdgeInsets())
                Text(verbatim: wtext("helplines.intro"))
                    .font(Theme.body(15)).foregroundStyle(Theme.ink)
                Text(verbatim: wtext("helplines.emergency"))
                    .font(Theme.caption(12)).foregroundStyle(Theme.inkSoft)
            }
            if let local = split.local {
                countrySection(local)
            }
            Section {
                fallbackLink
            }
            if !split.others.isEmpty {
                Section {
                    ForEach(split.others) { c in
                        DisclosureGroup {
                            countryRows(c)
                        } label: {
                            Text(verbatim: c.displayName)
                        }
                    }
                } header: {
                    Text(verbatim: wtext("helplines.otherCountries"))
                }
            }
            Section {
                Text(verbatim: wtext("helplines.private"))
                    .font(Theme.caption(11)).foregroundStyle(Theme.inkSoft)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: wtext("helplines.title")))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.recordWellbeingOpen(.helplines) }
    }

    private func countrySection(_ c: HelplineDirectory.Country) -> some View {
        Section {
            countryRows(c)
        } header: {
            Text(verbatim: c.displayName)
        }
    }

    @ViewBuilder
    private func countryRows(_ c: HelplineDirectory.Country) -> some View {
        if let e = c.emergency, !e.isEmpty, let url = URL(string: "tel:\(e.filter(\.isNumber))") {
            Link(destination: url) {
                Label { Text(verbatim: "\(e)") } icon: { Image(systemName: "staroflife.fill") }
            }
        }
        ForEach(c.lines) { line in
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: line.name).font(Theme.body(15)).foregroundStyle(Theme.ink)
                HStack(spacing: 10) {
                    if let tel = line.telURL {
                        Link(destination: tel) {
                            Label { Text(verbatim: "\(wtext("helplines.call")) \(line.number)") } icon: {
                                Image(systemName: "phone.fill")
                            }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text(verbatim: wtext("helplines.numberPending"))
                            .font(Theme.caption(11)).foregroundStyle(Theme.inkSoft)
                    }
                    if let web = line.websiteURL {
                        Link(destination: web) { Text(verbatim: wtext("helplines.website")) }
                            .buttonStyle(.bordered)
                    }
                }
                .font(Theme.caption(12))
            }
            .padding(.vertical, 4)
        }
    }

    private var fallbackLink: some View {
        Link(destination: directory.fallback.url ?? HelplineDirectory.fallbackURL) {
            Label { Text(verbatim: wtext("helplines.find")) } icon: { Image(systemName: "globe") }
        }
    }
}
