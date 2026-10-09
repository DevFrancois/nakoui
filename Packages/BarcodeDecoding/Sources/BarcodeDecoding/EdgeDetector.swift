/// Sub-pixel edge detector modelled on ZBar's scanner (algorithm re-expressed from its
/// description; ZBar is LGPL-2.1). The profile is lightly smoothed, an edge sits where the
/// second difference changes sign (the inflection point of a blurred step, which stays put
/// under any symmetric blur, gain or shading), and it only counts when its slope reaches an
/// adaptive threshold: 0.44 of the previous edge's slope, fading to `minSlope` over eight
/// widths of the last element. Of several same-polarity inflections the steepest wins.
enum EdgeDetector {
    /// Smoothing weight of the new sample, in 1/32 (0.78).
    private static let smoothing = 25
    /// Fraction of an edge's slope the next edge must reach, in 1/32 (0.44).
    private static let thresholdRatio = 14
    /// Elements over which the threshold fades back to the floor.
    private static let fadeElements = 8

    /// Appends the edges of `profile[0..<count]` to `edges` (which it clears first).
    static func detect(_ profile: UnsafePointer<Int32>, count: Int, minSlope: Int, into edges: inout EdgeList) {
        edges.count = 0
        edges.startsDark = false
        guard count >= 4 else { return }
        let floor = minSlope
        // Smoothed sample, its last two differences and the curvature one sample back.
        var s1 = Int(profile[0])
        var d1 = 0, d2 = 0, c2 = 0
        var tracked = 0          // signed slope of the edge being tracked; 0 before the first
        var trackedPosition = 0  // its position + 2 samples, 1/32 sample
        var threshold = floor    // threshold set by the newest edge
        var lastPosition = 0     // the latest finalised edge, origin of the fade
        var fadeLength = 0       // 1/32 sample over which the threshold fades; 0 = no fade
        var finalised = 0
        for x in 1..<count {
            let s0 = ((32 &- smoothing) &* s1 &+ smoothing &* Int(profile[x])) >> 5
            let d0 = s0 &- s1
            let c1 = d0 &- d1               // curvature at x - 1 (c2 is at x - 2)
            // Slope at the inflection: the steeper of the two differences around it if they agree.
            let slope = (d1 ^ d2) >= 0 && abs(d2) > abs(d1) ? d2 : d1
            let magnitude = abs(slope)
            let crossing = c1 == 0 || (c1 > 0 ? c2 < 0 : c2 > 0)
            let curvature = c2
            s1 = s0
            d2 = d1
            d1 = d0
            c2 = c1
            guard magnitude >= floor && crossing else { continue }
            if threshold > floor && fadeLength > 0 {
                // Faded threshold = threshold * (1 - travelled / fadeLength), kept above the floor.
                let remaining = threshold &* (fadeLength &- ((x << 5) &- lastPosition))
                if remaining > floor &* fadeLength {
                    if magnitude &* fadeLength < remaining { continue }
                } else {
                    threshold = floor
                }
            }
            let reverses = tracked > 0 ? slope < 0 : slope > 0
            if tracked != 0 && reverses {
                edges.append(position: Int32(trackedPosition &- 64), strength: Int32(abs(tracked)))
                finalised &+= 1
                fadeLength = finalised >= 2 ? (trackedPosition &- lastPosition) &* fadeElements : 0
                lastPosition = trackedPosition
            }
            if tracked == 0 || reverses || magnitude > abs(tracked) {
                if tracked == 0 { edges.startsDark = slope > 0 }
                tracked = slope
                threshold = max(floor, (magnitude &* thresholdRatio &+ 16) >> 5)
                // Interpolate the curvature zero crossing between x - 2 and x - 1.
                let denominator = c1 &- curvature
                var fraction = 32
                if denominator == 0 {
                    fraction = 16
                } else if c1 != 0 {
                    fraction -= ((c1 << 5) &+ 1) / denominator
                }
                trackedPosition = (x << 5) &+ fraction
            }
        }
        if tracked != 0 {
            edges.append(position: Int32(trackedPosition &- 64), strength: Int32(abs(tracked)))
        }
    }
}
