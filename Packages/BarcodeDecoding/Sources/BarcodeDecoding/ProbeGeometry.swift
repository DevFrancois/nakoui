/// A code's axes for probing: unit reading direction u, unit "down" direction v, where the bars
/// start along u and how wide a module is, and the statistics of the module-pattern template.
struct ProbeGeometry {
    var ux: Double
    var uy: Double
    var vx: Double
    var vy: Double
    var start: Double
    var module: Double
    var moduleCount: Int
    var templateMean: Float
    var templateVariance: Float
}
