import Foundation

/// A rendering value, independent of the development-only editor and storage.
/// Release builds always render `defaults`; no preferences are read here.
nonisolated struct TabBarReflectionSettings: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case faceAndEdges
        case mostlyEdges
    }

    var mode: Mode = .faceAndEdges
    var surfaceOpacity: Double = 0.88
    var faceWash: Double = 0.10
    var reflectionStrength: Double = 1.15
    var reflectionWidth: Double = 11
    var saturation: Double = 1.10
    var softness: Double = 1
    var samplingDistance: Double = 96
    var sharpHighlight: Double = 1.5
    var sharpHighlightWidth: Double = 0.38
    var softGlow: Double = 1.5
    var softGlowWidth: Double = 3.5
    var lightDirectionDegrees: Double = -25
    var warmCoolBalance: Double = 0
    var edgeDarkening: Double = 1

    static let defaults = Self()

    func sanitized() -> Self {
        var result = self
        for parameter in Parameter.allCases {
            result[keyPath: parameter.keyPath] = parameter.clamp(result[keyPath: parameter.keyPath])
        }
        return result
    }

    /// One range definition is shared by loading, live editing, and the renderer.
    enum Parameter: String, CaseIterable, Sendable {
        case surfaceOpacity, faceWash, reflectionStrength, reflectionWidth
        case saturation, softness, samplingDistance, sharpHighlight
        case sharpHighlightWidth, softGlow, softGlowWidth, lightDirectionDegrees
        case warmCoolBalance, edgeDarkening

        var range: ClosedRange<Double> {
            switch self {
            case .surfaceOpacity: 0.5...1
            case .faceWash: 0...0.25
            case .reflectionStrength, .saturation, .edgeDarkening: 0...2
            case .reflectionWidth: 2...14
            case .softness: 0.5...1.5
            case .samplingDistance: 24...96
            case .sharpHighlight, .softGlow: 0...3
            case .sharpHighlightWidth: 0.25...1.5
            case .softGlowWidth: 1...6
            case .lightDirectionDegrees: -180...180
            case .warmCoolBalance: -1...1
            }
        }

        var keyPath: WritableKeyPath<TabBarReflectionSettings, Double> {
            switch self {
            case .surfaceOpacity: \.surfaceOpacity
            case .faceWash: \.faceWash
            case .reflectionStrength: \.reflectionStrength
            case .reflectionWidth: \.reflectionWidth
            case .saturation: \.saturation
            case .softness: \.softness
            case .samplingDistance: \.samplingDistance
            case .sharpHighlight: \.sharpHighlight
            case .sharpHighlightWidth: \.sharpHighlightWidth
            case .softGlow: \.softGlow
            case .softGlowWidth: \.softGlowWidth
            case .lightDirectionDegrees: \.lightDirectionDegrees
            case .warmCoolBalance: \.warmCoolBalance
            case .edgeDarkening: \.edgeDarkening
            }
        }

        func clamp(_ value: Double) -> Double {
            guard value.isFinite else { return TabBarReflectionSettings.defaults[keyPath: keyPath] }
            return min(range.upperBound, max(range.lowerBound, value))
        }
    }
}
