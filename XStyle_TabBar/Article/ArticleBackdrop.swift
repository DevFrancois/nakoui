import SwiftUI

/// Colors for the article page, taken from its image: four lights across the
/// top, left to right like the image's top half, fading into a base taken from
/// its bottom half. A tone makes them dark or light.
struct ArticleBackdrop: Equatable {
    let lights: [SIMD3<Float>]
    let base: SIMD3<Float>

    /// Side of the square the image is shrunk to before averaging.
    private static let sampleSize = 32

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
        lights = (0..<4).map { band in
            Self.toned(
                average(rows: 0..<half, columns: band * bandWidth..<(band + 1) * bandWidth),
                brightness: tone.lightBrightness,
                saturationScale: tone.lightSaturationScale,
                maximumSaturation: tone.maximumLightSaturation
            )
        }
        base = Self.toned(
            average(rows: half..<size, columns: 0..<size),
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
