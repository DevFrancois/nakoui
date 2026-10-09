/// Reads scanline profiles out of the luma plane.
enum ProfileSampler {
    /// Profile values are pixel sums scaled by this factor, which keeps sub-grey-level precision
    /// through the edge detector's integer smoothing.
    static let scaleShift: Int32 = 3

    /// Fills `profile[0..<line.sampleCount]` with the summed pixels of each sample, scaled.
    static func sample(_ line: ScanLine, from image: LumaImage, averaging: Int,
                       into profile: UnsafeMutablePointer<Int32>) {
        if line.family == .rows {
            sampleRow(line, image, averaging, profile)
            return
        }
        if line.family == .columns && averaging == 4 {
            sampleColumnWords(line, image, profile)
            return
        }
        // Footprints of 1 to 4 pixels get loops unrolled for their width.
        switch averaging {
        case 1: sampleStrided(line, image, profile, footprint: 1)
        case 2: sampleStrided(line, image, profile, footprint: 2)
        case 3: sampleStrided(line, image, profile, footprint: 3)
        case 4: sampleStrided(line, image, profile, footprint: 4)
        default: sampleStrided(line, image, profile, footprint: averaging)
        }
    }

    /// Rows are contiguous along the line: one pass per summed row, which vectorises.
    private static func sampleRow(_ line: ScanLine, _ image: LumaImage, _ footprint: Int,
                                  _ profile: UnsafeMutablePointer<Int32>) {
        let p = image.pixels + line.firstPixel
        for s in 0..<line.sampleCount { profile[s] = Int32(p[s]) }
        for j in 1..<footprint {
            let row = p + j * line.across
            for s in 0..<line.sampleCount { profile[s] &+= Int32(row[s]) }
        }
        for s in 0..<line.sampleCount { profile[s] <<= scaleShift }
    }

    /// A column's four pixels are adjacent bytes: add them pairwise inside one 32-bit word.
    private static func sampleColumnWords(_ line: ScanLine, _ image: LumaImage, _ profile: UnsafeMutablePointer<Int32>) {
        var p = image.pixels + line.firstPixel
        for s in 0..<line.sampleCount {
            let word = UnsafeRawPointer(p).loadUnaligned(as: UInt32.self)
            let pairs = (word & 0x00FF_00FF) &+ ((word >> 8) & 0x00FF_00FF)
            profile[s] = Int32((pairs & 0xFFFF) &+ (pairs >> 16)) << scaleShift
            p += line.step
        }
    }

    /// Columns and diagonals, one footprint per sample.
    @inline(__always)
    private static func sampleStrided(_ line: ScanLine, _ image: LumaImage, _ profile: UnsafeMutablePointer<Int32>,
                                      footprint: Int) {
        let across = line.across
        let step = line.step
        var p = image.pixels + line.firstPixel
        guard line.isDiagonal else {
            for s in 0..<line.sampleCount {
                profile[s] = sum(p, across, footprint) << scaleShift
                p += step
            }
            return
        }
        // Full samples at even indices. A half step averages the footprint moved one pixel
        // along x and the one moved one pixel along y, which centres it on the line.
        let down = step - 1
        let fullCount = (line.sampleCount + 1) / 2
        for t in 0..<(fullCount - 1) {
            profile[2 * t] = sum(p, across, footprint) << scaleShift
            profile[2 * t + 1] = (sum(p + 1, across, footprint) &+ sum(p + down, across, footprint)) << (scaleShift - 1)
            p += step
        }
        profile[2 * (fullCount - 1)] = sum(p, across, footprint) << scaleShift
    }

    @inline(__always)
    private static func sum(_ p: UnsafePointer<UInt8>, _ across: Int, _ count: Int) -> Int32 {
        var total: Int32 = 0
        for j in 0..<count { total &+= Int32(p[j &* across]) }
        return total
    }
}
