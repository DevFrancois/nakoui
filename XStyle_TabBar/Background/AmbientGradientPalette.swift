import Foundation

/// Four colors for the soft light at the top of the screen.
/// Values come from ZoomInUIKit's `GridGradientPalette`.
struct AmbientGradientPalette: Equatable {
    let colors: [SIMD3<Float>]

    init(hexColors: [UInt32]) {
        precondition(hexColors.count == 4, "A gradient palette requires four colors.")
        colors = hexColors.map(Self.rgb)
    }

    /// The page colors the light fades into; they match the `PageBackground` asset.
    static let lightBackground = rgb(0xF7F5FC)
    static let darkBackground = SIMD3<Float>(repeating: 0)

    static let lavenderHealth = AmbientGradientPalette(hexColors: [
        0xD9CEFF, 0xEFCDFA, 0xAFD8FF, 0xB1F2E3
    ])
    static let roseDawn = AmbientGradientPalette(hexColors: [
        0xF4C6DC, 0xFFD8C2, 0xE1CCFA, 0xC7DDFF
    ])
    static let peachBloom = AmbientGradientPalette(hexColors: [
        0xFFD5BD, 0xF4C5D9, 0xDED0FA, 0xFFF0CD
    ])
    static let meadowLight = AmbientGradientPalette(hexColors: [
        0xBDEBD0, 0xD4F0C3, 0xBBE4EA, 0xD6D6FA
    ])

    nonisolated private static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(
            Float((hex >> 16) & 0xFF) / 255,
            Float((hex >> 8) & 0xFF) / 255,
            Float(hex & 0xFF) / 255
        )
    }
}
