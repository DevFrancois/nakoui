/// Estimates the sensor noise of a frame, so the edge detector's slope floor can rise above it.
///
/// The region is cut into a grid of small patches; each patch's mean absolute second difference
/// along x measures its texture plus noise. Flat patches (quiet zones, paper, background) are
/// common, so a low quantile of the patch values tracks the noise alone. For Gaussian noise of
/// standard deviation sigma the mean absolute second difference is about 1.95 sigma.
enum NoiseEstimator {
    private static let grid = 8
    private static let patchWidth = 24
    private static let patchRows = 3

    /// Noise standard deviation in grey levels.
    static func sigma(of image: LumaImage, region: ScanRegion) -> Double {
        guard region.width >= patchWidth + 2, region.height >= patchRows else { return 0 }
        return withUnsafeTemporaryAllocation(of: Int.self, capacity: grid * grid) { activities in
            for gy in 0..<grid {
                let y = region.minY + (region.height - patchRows) * gy / (grid - 1)
                for gx in 0..<grid {
                    let x = region.minX + 1 + (region.width - patchWidth - 2) * gx / (grid - 1)
                    var total = 0
                    for r in 0..<patchRows {
                        let p = image.pixels + (y + r) * image.bytesPerRow + x
                        for i in 0..<patchWidth {
                            total += abs(Int(p[i - 1]) - 2 * Int(p[i]) + Int(p[i + 1]))
                        }
                    }
                    activities[gy * grid + gx] = total
                }
            }
            var sorted = activities  // the same storage
            sorted.sort()
            return Double(sorted[sorted.count / 5]) / Double(patchWidth * patchRows) / 1.95
        }
    }
}
