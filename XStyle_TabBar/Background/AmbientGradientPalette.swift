import Foundation

/// A tab's one color, as it shows at the very top of the screen in each
/// appearance before it fades into the page.
struct AmbientGradientPalette: Equatable {
    let light: SIMD3<Float>
    let dark: SIMD3<Float>

    init(light: SIMD3<Float>, dark: SIMD3<Float>) {
        self.light = light
        self.dark = dark
    }

    init(light: UInt32, dark: UInt32) {
        self.init(light: Self.rgb(light), dark: Self.rgb(dark))
    }

    // Light tones are ZoomInUIKit's pastels at half strength over the page.
    // Dark tones share the OKLCH lightness and chroma of the lavender, a deep
    // muted violet, so no tab glows brighter than another.
    static let lavenderHealth = AmbientGradientPalette(light: 0xE8E2FE, dark: 0x3D3449)
    static let roseDawn = AmbientGradientPalette(light: 0xF6DEEC, dark: 0x48313C)
    static let peachBloom = AmbientGradientPalette(light: 0xFBE5DC, dark: 0x493327)
    static let meadowLight = AmbientGradientPalette(light: 0xDAF0E6, dark: 0x273F32)
    static let lagoonMist = AmbientGradientPalette(light: 0xDBEEF7, dark: 0x213E46)

    nonisolated private static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(
            Float((hex >> 16) & 0xFF) / 255,
            Float((hex >> 8) & 0xFF) / 255,
            Float(hex & 0xFF) / 255
        )
    }
}
