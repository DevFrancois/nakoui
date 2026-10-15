/// Debug dials for the Home background's color wash, stored so they
/// survive relaunches. At their defaults the wash is unchanged.
enum AmbientGradientTuning {
    static let intensityKey = "ambientGradient.intensity"
    static let depthKey = "ambientGradient.depth"

    /// Multiplies the wash's opacity.
    static let defaultIntensity = 1.0
    static let intensityRange = 0.0...2.0

    /// Stretches how far down the screen the wash reaches.
    static let defaultDepth = 1.0
    static let depthRange = 0.3...2.5
}
