import SwiftUI
import AVFoundation
import CoreVideo
import MixlingsGenome

// H2: 9:16 hatch clip (7 s) built from the A7 hatch storyboard:
// egg wobble -> cracks -> flash -> creature drop -> rarity pill -> end card.
// Each frame is a SwiftUI view rendered with ImageRenderer and appended to an H.264 .mp4 in tmp
// with AVAssetWriter. Watermark "Tweggs" (placeholder brand) and an end card are baked in.
// Content stays inside TikTok/Reels safe zones (no text in the top ~8% / bottom ~20%, right rail).
//
// RISKY APIs (verify on device):
// - ImageRenderer per frame on the main actor: ~170 renders at 1080x1920. Measured budget unknown;
//   if too slow, drop `fps` to 20 or render at scale 2 (720x1280).
// - AVAssetWriterInputPixelBufferAdaptor pool is nil until `startWriting()`; we fall back to
//   CVPixelBufferCreate.
// - `isReadyForMoreMediaData` polling with Task.sleep (simple, not the most efficient).

/// Pure timeline (testable): which storyboard phase is shown at time `t`.
enum HatchClipTimeline {
    static let duration: Double = 7.0
    static let fps: Int32 = 24
    static var frameCount: Int { Int(duration * Double(fps)) }
    /// Layout size in points; rendered at `scale` -> 1080 x 1920 px.
    static let size = CGSize(width: 360, height: 640)
    static let scale: CGFloat = 3

    enum Phase: Equatable { case wobble, cracks, flash, drop, reveal, endCard }

    static func phase(at t: Double) -> Phase {
        switch t {
        case ..<1.2: return .wobble
        case ..<2.2: return .cracks
        case ..<2.6: return .flash
        case ..<3.4: return .drop
        case ..<5.6: return .reveal
        default: return .endCard
        }
    }

    /// 0...1 progress inside `[start, end)`.
    static func local(_ t: Double, _ start: Double, _ end: Double) -> Double {
        min(1, max(0, (t - start) / (end - start)))
    }
}

/// One frame of the clip. Pure function of `t` (seconds), so preview and export match.
struct HatchClipFrame: View {
    let creature: Creature
    let t: Double

    private var tier: RarityTier { (try? Genetics.rarity(creature.genome))?.tier ?? .common }

    var body: some View {
        let phase = HatchClipTimeline.phase(at: t)
        ZStack {
            LinearGradient(colors: [Theme.cardFace, Theme.cardPanel], startPoint: .top, endPoint: .bottom)

            if phase == .endCard {
                endCard
            } else {
                stage(phase)
            }

            // Watermark: inside the safe zone (below the top ~8%).
            VStack {
                Text(verbatim: ShareCopy.brand)
                    .font(Theme.title(18))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 64)
                Spacer()
            }
        }
        .frame(width: HatchClipTimeline.size.width, height: HatchClipTimeline.size.height)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func stage(_ phase: HatchClipTimeline.Phase) -> some View {
        let traits = PhenotypeMapper.traits(for: creature)
        ZStack {
            if phase == .wobble || phase == .cracks || phase == .flash {
                let wobble: Double = phase == .wobble
                    ? sin(t * 14) * 6 * HatchClipTimeline.local(t, 0, 1.2)
                    : sin(t * 30) * 3
                EggView(traits: traits)
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(wobble))
                    .overlay {
                        CrackShape(progress: HatchClipTimeline.local(t, 1.2, 2.2))
                            .stroke(Theme.cardFace, style: StrokeStyle(lineWidth: 4, lineCap: .square, lineJoin: .miter))
                            .frame(width: 120, height: 60)
                            .opacity(phase == .wobble ? 0 : 1)
                    }
            } else {
                let y = Self.dropOffset(HatchClipTimeline.local(t, 2.6, 3.4))
                CreatureSprite(creature: creature, stage: .baby)
                    .frame(width: 230, height: 230)
                    .offset(y: y)
                if phase == .reveal {
                    let pop = HatchClipTimeline.local(t, 3.4, 3.8)
                    VStack(spacing: 8) {
                        Text(creature.name)
                            .font(Theme.title(28))
                            .foregroundStyle(.white)
                        Text(tier.title)
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.cardFace)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.rarity(tier)))
                    }
                    .scaleEffect(0.6 + 0.4 * pop)
                    .opacity(pop)
                    .offset(y: 170)
                }
            }
            // Flash
            Color.white
                .opacity(phase == .flash ? Self.flashOpacity(t) : 0)
        }
    }

    static func flashOpacity(_ t: Double) -> Double {
        1 - abs(HatchClipTimeline.local(t, 2.2, 2.6) * 2 - 1)
    }

    /// Ease-out fall from above with a small bounce at the end.
    static func dropOffset(_ drop: Double) -> CGFloat {
        let fall: Double = -260 * (1 - drop) * (1 - drop)
        var bounce: Double = 0
        if drop > 0.85 { bounce = -8 * sin((drop - 0.85) / 0.15 * Double.pi) }
        return CGFloat(fall + bounce)
    }

    private var endCard: some View {
        let fade = HatchClipTimeline.local(t, 5.6, 6.0)
        return VStack(spacing: 16) {
            CreatureSprite(creature: creature, stage: .baby)
                .frame(width: 140, height: 140)
            Text(verbatim: ShareCopy.brand)
                .font(Theme.title(40))
                .foregroundStyle(.white)
            Text(ShareCopy.clipMessage(name: creature.name))
                .font(Theme.body(17))
                .foregroundStyle(Theme.cardLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            // TODO(H1): QR / short code to the breed link once the landing page exists.
        }
        .opacity(fade)
        .offset(y: -40) // keep clear of the bottom caption zone
    }
}

/// Zig-zag crack drawn left to right as `progress` goes 0 -> 1.
struct CrackShape: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = (0...6).map { i in
            CGPoint(x: rect.minX + rect.width * CGFloat(i) / 6,
                    y: rect.midY + (i.isMultiple(of: 2) ? -rect.height / 4 : rect.height / 4))
        }
        let visible = max(1, Int((Double(points.count - 1) * progress).rounded(.up)))
        var p = Path()
        p.move(to: points[0])
        for pt in points.dropFirst().prefix(visible) { p.addLine(to: pt) }
        return progress <= 0 ? Path() : p
    }
}

enum HatchClipError: Error { case writerSetup, frame, finish }

@MainActor
enum HatchClipExporter {
    /// Renders the clip to `tmp/hatch-<id>.mp4` and returns its URL. `progress` gets 0...1.
    static func export(creature: Creature, progress: (Double) -> Void = { _ in }) async throws -> URL {
        let pixelW = Int(HatchClipTimeline.size.width * HatchClipTimeline.scale)
        let pixelH = Int(HatchClipTimeline.size.height * HatchClipTimeline.scale)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatch-\(creature.id).mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelW,
            AVVideoHeightKey: pixelH,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: pixelW,
            kCVPixelBufferHeightKey as String: pixelH,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: attrs)
        guard writer.canAdd(input) else { throw HatchClipError.writerSetup }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? HatchClipError.writerSetup }
        writer.startSession(atSourceTime: .zero)

        let total = HatchClipTimeline.frameCount
        for i in 0..<total {
            try Task.checkCancellation()
            let t = Double(i) / Double(HatchClipTimeline.fps)
            let renderer = ImageRenderer(content: HatchClipFrame(creature: creature, t: t))
            renderer.proposedSize = ProposedViewSize(HatchClipTimeline.size)
            renderer.scale = HatchClipTimeline.scale
            guard let cg = renderer.cgImage,
                  let buffer = pixelBuffer(from: cg, pool: adaptor.pixelBufferPool, width: pixelW, height: pixelH)
            else { throw HatchClipError.frame }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            let time = CMTime(value: CMTimeValue(i), timescale: HatchClipTimeline.fps)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? HatchClipError.frame
            }
            progress(Double(i + 1) / Double(total))
            if i % 8 == 0 { await Task.yield() } // keep the progress UI alive
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? HatchClipError.finish }
        return url
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool?,
                                    width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        }
        guard let pb = buffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pb
    }
}

/// Sheet: live preview of the clip, "Make video" -> progress -> ShareLink to the .mp4.
struct HatchClipScreen: View {
    @Environment(\.dismiss) private var dismiss
    let creature: Creature

    @State private var progress: Double = 0
    @State private var exporting = false
    @State private var fileURL: URL?
    @State private var failed = false
    @State private var start = Date.now

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSince(start).truncatingRemainder(dividingBy: HatchClipTimeline.duration)
                    HatchClipFrame(creature: creature, t: t)
                        .scaleEffect(0.62)
                        .frame(width: HatchClipTimeline.size.width * 0.62,
                               height: HatchClipTimeline.size.height * 0.62)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .accessibilityHidden(true)

                if let fileURL {
                    ShareLink(item: fileURL, message: Text(ShareCopy.clipMessage(name: creature.name))) {
                        Label("Share video", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PixelButtonStyle(tint: Theme.accent))
                } else if exporting {
                    ProgressView(value: progress) { Text("Making your video…") }
                        .tint(Theme.accent)
                } else {
                    Button {
                        Task { await export() }
                    } label: {
                        Label("Make video", systemImage: "video.fill")
                    }
                    .buttonStyle(PixelButtonStyle(tint: Theme.accent))
                }
                if failed {
                    Text("Couldn't make the video. Please try again.")
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Hatch video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    @MainActor
    private func export() async {
        exporting = true
        failed = false
        defer { exporting = false }
        do {
            fileURL = try await HatchClipExporter.export(creature: creature) { progress = $0 }
        } catch {
            failed = true
        }
    }
}
