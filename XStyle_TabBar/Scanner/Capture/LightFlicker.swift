/// How the scene's light pulses, as far as the frames show.
nonisolated enum LightFlicker: Equatable, Sendable {
    case steady
    /// At `ScannerMetrics.flickerRate`, alike every pulse: exposures of one
    /// whole pulse remove the bands.
    case pulsing
    /// With every other pulse brighter, as lamps lighting the two halves of a
    /// mains cycle unevenly do: exposures need two whole pulses.
    case unevenlyPulsing

    /// The fewest whole pulses an exposure must last.
    var minimumPulses: Int {
        self == .unevenlyPulsing ? 2 : 1
    }
}
