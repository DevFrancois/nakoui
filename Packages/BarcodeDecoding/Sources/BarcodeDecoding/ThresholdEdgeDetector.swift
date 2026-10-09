/// Edges where a sharpened profile crosses a per-line threshold, after zxing-cpp's
/// GlobalHistogramBinarizer (Apache-2.0): a 32-bucket histogram of the line gives a dark and a
/// light peak, the threshold sits in the valley between them (biased towards the light peak),
/// and each sample is sharpened as (4v - left - right) / 2 before the comparison. Crossings are
/// interpolated to 1/32 sample instead of being rounded to whole pixels.
enum ThresholdEdgeDetector {
    /// Lines whose two histogram peaks are this close (in buckets) have too little contrast.
    private static let minimumPeakDistance = 3

    /// Appends the edges of `profile[0..<count]` to `edges` (which it clears first). `scale`
    /// converts profile values to grey levels (profile = grey * scale).
    static func detect(_ profile: UnsafePointer<Int32>, count: Int, scale: Int, into edges: inout EdgeList) {
        edges.count = 0
        edges.startsDark = false
        guard count >= 3, let threshold = threshold(profile, count: count, scale: scale) else { return }
        // The end samples are compared unsharpened, as in zxing.
        var previous = Int(profile[0]) &- threshold
        var isDark = previous <= 0
        edges.startsDark = isDark
        var left = Int(profile[0]), centre = Int(profile[1])
        for i in 1..<count {
            var current: Int
            if i + 1 < count {
                let right = Int(profile[i + 1])
                current = ((4 &* centre &- left &- right) >> 1) &- threshold
                left = centre
                centre = right
            } else {
                current = centre &- threshold
            }
            if (current <= 0) != isDark {
                // Linear interpolation of the crossing between samples i - 1 and i.
                let fraction = (previous << 5) / (previous &- current)
                edges.append(position: Int32(truncatingIfNeeded: (i &- 1) << 5 &+ fraction),
                             strength: Int32(truncatingIfNeeded: abs(previous &- current)))
                isDark.toggle()
            }
            previous = current
        }
    }

    /// The line's black point in profile units, or nil for a low-contrast line.
    private static func threshold(_ profile: UnsafePointer<Int32>, count: Int, scale: Int) -> Int? {
        withUnsafeTemporaryAllocation(of: Int.self, capacity: 4 * 32) { raw -> Int? in
            let counts = raw.baseAddress!
            counts.initialize(repeating: 0, count: 4 * 32)
            // Four interleaved histograms (neighbouring samples usually share a bucket, and
            // consecutive increments of one counter would wait on each other), every other
            // sample, bucket = grey / 8 by multiply and shift.
            let reciprocal = (1 << 24) / (8 * scale)
            var i = 0
            while i + 6 < count {
                for lane in 0..<4 {
                    let bucket = min(31, (max(0, Int(profile[i + 2 * lane])) &* reciprocal) >> 24)
                    counts[lane * 32 + bucket] += 1
                }
                i += 8
            }
            while i < count {
                counts[min(31, (max(0, Int(profile[i])) &* reciprocal) >> 24)] += 1
                i += 2
            }
            for bucket in 0..<32 {
                counts[bucket] += counts[32 + bucket] + counts[64 + bucket] + counts[96 + bucket]
            }
            return blackPoint(UnsafeBufferPointer(start: counts, count: 32)).map { $0 * scale }
        }
    }

    /// zxing's peak-and-valley search over a 32-bucket histogram, in grey levels.
    private static func blackPoint(_ buckets: UnsafeBufferPointer<Int>) -> Int? {
        var first = 0, maximum = 0
        for x in 0..<32 where buckets[x] > maximum {
            maximum = buckets[x]
            first = x
        }
        var second = 0, best = 0
        for x in 0..<32 {
            let score = buckets[x] * (x - first) * (x - first)
            if score > best {
                best = score
                second = x
            }
        }
        let dark = min(first, second), light = max(first, second)
        guard light - dark >= minimumPeakDistance else { return nil }
        var valley = light - 1, valleyScore = -1
        for x in stride(from: light - 1, to: dark, by: -1) {
            let score = (x - dark) * (x - dark) * (light - x) * (maximum - buckets[x])
            if score > valleyScore {
                valleyScore = score
                valley = x
            }
        }
        return valley * 8 - 1
    }
}
