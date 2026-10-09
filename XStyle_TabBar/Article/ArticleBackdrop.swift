import SwiftUI

/// Colors for the article page, taken from its image: four lights across the
/// top of the page from the image's top half, four across the bottom from its
/// bottom half, both left to right, fading into a base from the whole image.
/// A tone makes them dark or light.
struct ArticleBackdrop: Equatable {
    let topLights: [SIMD3<Float>]
    let bottomLights: [SIMD3<Float>]
    let base: SIMD3<Float>

    /// Side of the square the image is shrunk to before averaging.
    private static let sampleSize = 32

    private init(topLights: [SIMD3<Float>], bottomLights: [SIMD3<Float>], base: SIMD3<Float>) {
        self.topLights = topLights
        self.bottomLights = bottomLights
        self.base = base
    }

    /// The backdrop for a gallery at a fractional page, blending each page's
    /// colors into the next with the same easing as the home pager.
    static func blending(_ backdrops: [ArticleBackdrop], at position: CGFloat) -> ArticleBackdrop? {
        guard !backdrops.isEmpty else { return nil }
        let clamped = min(max(position.isNaN ? 0 : position, 0), CGFloat(backdrops.count - 1))
        let lower = Int(clamped)
        let fraction = Float(clamped - CGFloat(lower))
        guard fraction > 0, lower + 1 < backdrops.count else { return backdrops[lower] }

        // Quintic smootherstep has zero velocity and acceleration at page edges.
        let amount = fraction * fraction * fraction * (fraction * (6 * fraction - 15) + 10)
        let from = backdrops[lower]
        let to = backdrops[lower + 1]
        func mix(_ start: [SIMD3<Float>], _ end: [SIMD3<Float>]) -> [SIMD3<Float>] {
            zip(start, end).map { $0 + ($1 - $0) * amount }
        }
        return ArticleBackdrop(
            topLights: mix(from.topLights, to.topLights),
            bottomLights: mix(from.bottomLights, to.bottomLights),
            base: from.base + (to.base - from.base) * amount
        )
    }

    /// Samples any image, such as an article's cover once it has loaded.
    init?(sampling image: CGImage, tone: Tone) {
        let size = Self.sampleSize
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: buffer.baseAddress,
                    width: size,
                    height: size,
                    bitsPerComponent: 8,
                    bytesPerRow: size * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard didDraw else { return nil }

        // Bitmap rows run top to bottom.
        func average(rows: Range<Int>, columns: Range<Int>) -> SIMD3<Float> {
            var sum = SIMD3<Float>.zero
            for row in rows {
                for column in columns {
                    let index = (row * size + column) * 4
                    sum += SIMD3(Float(pixels[index]), Float(pixels[index + 1]), Float(pixels[index + 2]))
                }
            }
            return sum / Float(rows.count * columns.count * 255)
        }

        let half = size / 2
        let bandWidth = size / 4
        func lights(rows: Range<Int>) -> [SIMD3<Float>] {
            (0..<4).map { band in
                Self.toned(
                    average(rows: rows, columns: band * bandWidth..<(band + 1) * bandWidth),
                    brightness: tone.lightBrightness,
                    saturationScale: tone.lightSaturationScale,
                    maximumSaturation: tone.maximumLightSaturation
                )
            }
        }

        topLights = lights(rows: 0..<half)
        bottomLights = lights(rows: half..<size)
        base = Self.toned(
            average(rows: 0..<size, columns: 0..<size),
            brightness: tone.baseBrightness,
            saturationScale: tone.baseSaturationScale,
            maximumSaturation: tone.maximumBaseSaturation
        )
    }

    /// Samples a SwiftUI view, such as the article's hero image as it is shown.
    @MainActor
    init?(rendering illustration: some View, tone: Tone) {
        let renderer = ImageRenderer(
            content: illustration.frame(width: Double(Self.sampleSize * 2), height: Double(Self.sampleSize * 2))
        )
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        self.init(sampling: image, tone: tone)
    }

    /// Keeps the hue, sets the brightness, and scales back the saturation.
    private static func toned(
        _ color: SIMD3<Float>,
        brightness: Float,
        saturationScale: Float,
        maximumSaturation: Float
    ) -> SIMD3<Float> {
        let maximum = color.max()
        guard maximum > 0 else { return SIMD3(repeating: brightness) }

        let saturation = (maximum - color.min()) / maximum
        guard saturation > 0 else { return SIMD3(repeating: brightness) }

        // At full brightness, saturation is the distance of the smallest component from 1.
        let normalized = color / maximum
        let targetSaturation = min(saturation * saturationScale, maximumSaturation)
        let desaturated = 1 - (1 - normalized) * (targetSaturation / saturation)
        return desaturated * brightness
    }
}
