import SwiftUI
import UIKit
import MixlingsGenome

/// "Картка істоти": collectible card face for one creature (mockup design/mockup/Card.dc.html).
/// Rarity-coloured frame, sprite, name, tier, generation, hatch date, serial, parents, Discoverer badge.
/// Pure view of its inputs (no environment), so `ImageRenderer` draws it identically.
struct CreatureCardFace: View {
    let creature: Creature
    /// Parents in `creature.parentIds` order; nil entries are parents not in this save (friend's).
    let parents: [Creature?]
    var now: Date = .now

    private var tier: RarityTier { (try? Genetics.rarity(creature.genome))?.tier ?? .common }
    private var stage: Stage { CareEngine.stage(creature, at: now) }
    private var traits: ExpressedTraits { PhenotypeMapper.traits(for: creature) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: ShareCopy.brand.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .kerning(2)
                    .foregroundStyle(Theme.cardLabel)
                Spacer()
                if let serial = creature.serial {
                    // TODO(server): global serial; this is the local hatch counter.
                    Text(verbatim: "№ " + CollectingEngine.groupedSerial(serial))
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.cardHighlight)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(creature.name)
                    .font(Theme.title(26))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(tier.title)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.rarity(tier))
            }

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.cardPanel)
                CreatureSprite(creature: creature, stage: stage)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .trailing, spacing: 4) {
                    if creature.discoveredFirst {
                        DiscovererBadge()
                    }
                    // G8: generation ladder badges.
                    ForEach(EconomyEngine.genBadges(generation: creature.generation), id: \.self) { level in
                        GenerationCardBadge(level: level)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 210)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    stat("Generation", value: Text(verbatim: "\(creature.generation)"))
                    stat("Hatched", value: hatchedText)
                }
                GridRow {
                    stat("Temper", value: Text(verbatim: CollectingNames.variant(gene: PhenotypeMapper.Gene.temper,
                                                                                variant: traits.temper)))
                    stat("Look", value: Text(verbatim: comboShort))
                }
            }

            Spacer(minLength: 0)

            parentsRow
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardFace)
        )
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.rarity(tier))
        )
        .accessibilityElement(children: .combine)
    }

    private var hatchedText: Text {
        if stage == .egg { return Text(verbatim: "—") }
        return Text(CareEngine.hatchDate(creature), format: .dateTime.day(.twoDigits).month(.twoDigits).year())
    }

    /// Short, stable look code shown on the card (first 6 hex of fnv1a32(comboKey)).
    private var comboShort: String {
        guard let key = creature.comboKey else { return "—" }
        return "#" + Hash.hex8(Hash.fnv1a32(key)).prefix(6).uppercased()
    }

    private func stat(_ label: LocalizedStringKey, value: Text) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(Theme.caption(12))
                .foregroundStyle(Theme.cardLabel)
            value
                .font(Theme.body(13))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var parentsRow: some View {
        if !parents.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(parents.enumerated()), id: \.offset) { index, parent in
                    if index > 0 {
                        Text(verbatim: "+")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Theme.cardLabel)
                    }
                    if let parent {
                        CreatureSprite(creature: parent, stage: .adult)
                            .frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.cardLabel)
                            .frame(width: 34, height: 34)
                    }
                }
                Text(verbatim: parents.map { $0?.name ?? "?" }.joined(separator: " + "))
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.cardLabel)
                    .lineLimit(1)
            }
        } else {
            Text(creature.generation == 0 ? LocalizedStringKey("First generation") : LocalizedStringKey("Parents unknown"))
                .font(Theme.caption(12))
                .foregroundStyle(Theme.cardLabel)
        }
    }
}

/// G8: "GEN 5" / "GEN 10" card badge.
struct GenerationCardBadge: View {
    let level: Int
    var body: some View {
        Text("Gen \(level)")
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .textCase(.uppercase)
            .foregroundStyle(Theme.cardFace)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(level >= 10 ? Theme.rarityLegendary : Theme.cardLabel))
            .accessibilityLabel(Text("Generation \(level) badge"))
    }
}

/// "Відкривач" badge (first local discovery of this look).
struct DiscovererBadge: View {
    var body: some View {
        Text("Discoverer")
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .textCase(.uppercase)
            .foregroundStyle(Theme.cardFace)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.cardHighlight))
    }
}

// MARK: - Share layouts

enum CardShareLayout: CaseIterable {
    /// 9:16 story, 1080 x 1920 px.
    case story
    /// Square, 1080 x 1080 px.
    case square

    /// Layout size in points; rendered at `scale` 3 -> 1080 px wide.
    var size: CGSize {
        switch self {
        case .story: return CGSize(width: 360, height: 640)
        case .square: return CGSize(width: 360, height: 360)
        }
    }

    static let scale: CGFloat = 3
}

/// Full-bleed canvas that is turned into the shared image.
struct CardShareCanvas: View {
    let creature: Creature
    let parents: [Creature?]
    let layout: CardShareLayout
    var now: Date = .now

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.background, Theme.preview], startPoint: .top, endPoint: .bottom)
            switch layout {
            case .story:
                VStack(spacing: 18) {
                    Text(verbatim: ShareCopy.brand)
                        .font(Theme.title(28))
                        .foregroundStyle(Theme.ink)
                    CreatureCardFace(creature: creature, parents: parents, now: now)
                        .frame(width: 300, height: 500)
                    Text(ShareCopy.cardFooter)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.inkSoft)
                }
            case .square:
                // Same card, scaled to fit a chat-friendly square.
                CreatureCardFace(creature: creature, parents: parents, now: now)
                    .frame(width: 300, height: 500)
                    .scaleEffect(0.66)
                    .frame(width: 300 * 0.66, height: 500 * 0.66)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .environment(\.colorScheme, .light)
    }
}

@MainActor
enum CardImageRenderer {
    static func image(creature: Creature, parents: [Creature?], layout: CardShareLayout, now: Date = .now) -> Image? {
        let renderer = ImageRenderer(content: CardShareCanvas(creature: creature, parents: parents,
                                                              layout: layout, now: now))
        renderer.proposedSize = ProposedViewSize(layout.size)
        renderer.scale = CardShareLayout.scale
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}

// MARK: - Screen

/// Card screen with share buttons (story + square). Presented from Collection detail,
/// onboarding (hatch) and the breed preview.
struct CreatureCardScreen: View {
    @Environment(GameModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let creature: Creature

    @State private var storyImage: Image?
    @State private var squareImage: Image?
    @State private var showClip = false

    private var parents: [Creature?] {
        (creature.parentIds ?? []).map { model.save.creature(id: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    CreatureCardFace(creature: creature, parents: parents)
                        .frame(width: 300, height: 500)
                    if creature.discoveredFirst {
                        // TODO(server): "first in the world" once discoveries are claimed online.
                        Text("You were the first to hatch this look on this device.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    // C2: no sharing in offline mode (under 13).
                    if model.socialAllowed {
                        VStack(spacing: 10) {
                            if let storyImage {
                                ShareLink(item: storyImage,
                                          message: Text(ShareCopy.cardMessage(name: creature.name)),
                                          preview: SharePreview(creature.name, image: storyImage)) {
                                    Label("Share to Stories", systemImage: "rectangle.portrait.on.rectangle.portrait")
                                }
                                .buttonStyle(PixelButtonStyle(tint: Theme.rarityRare))
                            }
                            if let squareImage {
                                ShareLink(item: squareImage,
                                          message: Text(ShareCopy.cardMessage(name: creature.name)),
                                          preview: SharePreview(creature.name, image: squareImage)) {
                                    Label("Square card for chat", systemImage: "square.on.square")
                                }
                                .buttonStyle(PixelButtonStyle(tint: Theme.cardStroke))
                            }
                            if CareEngine.stage(creature, at: .now) != .egg {
                                Button {
                                    showClip = true
                                } label: {
                                    Label("Record hatch video", systemImage: "video.fill")
                                }
                                .buttonStyle(PixelButtonStyle(tint: Theme.accent))
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Creature card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: creature) {
                await renderShareImages()
            }
            .sheet(isPresented: $showClip) {
                HatchClipScreen(creature: creature)
            }
        }
    }

    @MainActor
    private func renderShareImages() async {
        let p = parents
        storyImage = CardImageRenderer.image(creature: creature, parents: p, layout: .story)
        squareImage = CardImageRenderer.image(creature: creature, parents: p, layout: .square)
    }
}
