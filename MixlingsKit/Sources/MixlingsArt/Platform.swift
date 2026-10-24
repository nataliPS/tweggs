// Apple-platform conveniences: CGImage (nearest-neighbour scaled) and a SwiftUI view.
import Foundation

extension PixelBuffer {
    /// Nearest-neighbour upscale by an integer factor (exactly like PIL `Image.NEAREST`
    /// with an integer ratio). Returns a new buffer.
    public func scaled(by scale: Int) -> PixelBuffer {
        let s = max(1, scale)
        if s == 1 { return self }
        let w = width * s, h = height * s
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let sy = y / s
            for x in 0..<w {
                let si = (sy * width + x / s) * 4
                let di = (y * w + x) * 4
                out[di] = rgba[si]; out[di + 1] = rgba[si + 1]; out[di + 2] = rgba[si + 2]; out[di + 3] = rgba[si + 3]
            }
        }
        return PixelBuffer(width: w, height: h, rgba: out)
    }
}

#if canImport(CoreGraphics)
import CoreGraphics

extension PixelBuffer {
    /// CGImage of this buffer scaled by `scale` with nearest-neighbour.
    /// CoreGraphics only supports premultiplied RGBA for 8-bit sRGB images, so the
    /// straight-alpha bytes are premultiplied here (only aura==2 pixels are translucent).
    public func cgImage(scale: Int = 1) -> CGImage? {
        let src = scaled(by: scale)
        var bytes = src.rgba
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let a = UInt16(bytes[i + 3])
            if a == 255 { continue }
            bytes[i] = UInt8((UInt16(bytes[i]) * a + 127) / 255)
            bytes[i + 1] = UInt8((UInt16(bytes[i + 1]) * a + 127) / 255)
            bytes[i + 2] = UInt8((UInt16(bytes[i + 2]) * a + 127) / 255)
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: src.width, height: src.height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: src.width * 4,
                       space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}

extension MixlingsRenderer {
    /// Render and return a CGImage upscaled with nearest-neighbour.
    public static func cgImage(_ p: Phenotype, scale: Int = 8) -> CGImage? {
        return render(p).cgImage(scale: scale)
    }
}
#endif

#if canImport(SwiftUI) && canImport(CoreGraphics)
import SwiftUI

/// Draws a Mixling crisply at any size (no smoothing).
public struct MixlingView: View {
    public let phenotype: Phenotype
    private let image: CGImage?

    public init(_ phenotype: Phenotype) {
        self.phenotype = phenotype
        self.image = MixlingsRenderer.render(phenotype).cgImage(scale: 1)
    }

    public var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
        } else {
            Color.clear.aspectRatio(1, contentMode: .fit)
        }
    }
}
#endif
