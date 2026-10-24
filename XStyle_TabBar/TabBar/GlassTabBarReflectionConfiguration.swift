import Foundation

struct GlassTabBarReflectionConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var saturation: Double
    var brightness: Double
    var blurRadius: Double
    var opacity: Double
    var isMirrored: Bool
    var rimRadius: Double
    var rimOpacity: Double
    var rimOffsetX: Double
    var rimOffsetY: Double
    var rimExpansion: Double
    var edgeCoverage: Double

    static let reference = Self(
        isEnabled: true, saturation: 2.5, brightness: 0.1, blurRadius: 15,
        opacity: 1, isMirrored: true, rimRadius: 5, rimOpacity: 1,
        rimOffsetX: 0, rimOffsetY: -3, rimExpansion: 10, edgeCoverage: 0.5
    )

    enum Ranges {
        static let saturation = 0.0...5.0
        static let brightness = -1.0...1.0
        static let blurRadius = 0.0...40.0
        static let opacity = 0.0...1.0
        static let rimRadius = 0.0...20.0
        static let rimOffset = -20.0...20.0
        static let rimExpansion = 0.0...30.0
        static let edgeCoverage = 0.05...1.0
    }

    /// Keep persisted or programmatic values safe for the native filters and
    /// geometry. Nonfinite numbers restore that field's reference value.
    var normalized: Self {
        var result = self
        result.saturation = Self.clamp(saturation, to: Ranges.saturation, fallback: Self.reference.saturation)
        result.brightness = Self.clamp(brightness, to: Ranges.brightness, fallback: Self.reference.brightness)
        result.blurRadius = Self.clamp(blurRadius, to: Ranges.blurRadius, fallback: Self.reference.blurRadius)
        result.opacity = Self.clamp(opacity, to: Ranges.opacity, fallback: Self.reference.opacity)
        result.rimRadius = Self.clamp(rimRadius, to: Ranges.rimRadius, fallback: Self.reference.rimRadius)
        result.rimOpacity = Self.clamp(rimOpacity, to: Ranges.opacity, fallback: Self.reference.rimOpacity)
        result.rimOffsetX = Self.clamp(rimOffsetX, to: Ranges.rimOffset, fallback: Self.reference.rimOffsetX)
        result.rimOffsetY = Self.clamp(rimOffsetY, to: Ranges.rimOffset, fallback: Self.reference.rimOffsetY)
        result.rimExpansion = Self.clamp(rimExpansion, to: Ranges.rimExpansion, fallback: Self.reference.rimExpansion)
        result.edgeCoverage = Self.clamp(edgeCoverage, to: Ranges.edgeCoverage, fallback: Self.reference.edgeCoverage)
        return result
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}
