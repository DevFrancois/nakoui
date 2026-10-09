/// Lays out the scanlines of one family across a region, in order of their offset.
///
/// Lines run a little past the region so quiet zones next to it can be seen; where a line
/// reaches the image border, its end counts as an unbounded quiet zone.
enum ScanPlanner {
    /// Pixels scanlines extend beyond the region.
    static let margin = 64
    /// Shortest line worth scanning, in pixels.
    static let minimumLength = 24

    static func appendLines(_ family: ScanFamily, image: LumaImage, region: ScanRegion, spacing: Int,
                            averaging k: Int, into lines: inout [ScanLine]) {
        let w = image.width, h = image.height, bpr = image.bytesPerRow
        let bx0 = max(0, region.minX - margin), bx1 = min(w, region.maxX + margin)
        let by0 = max(0, region.minY - margin), by1 = min(h, region.maxY + margin)
        let half = Double(k) / 2
        switch family {
        case .columns:
            guard by1 - by0 >= minimumLength else { return }
            for x in offsets(from: region.minX, to: region.maxX - k, spacing: spacing) {
                lines.append(ScanLine(family: .columns, offset: Double(x) + half, firstPixel: by0 * bpr + x, step: bpr,
                                      across: 1, sampleCount: by1 - by0, originX: Double(x) + half,
                                      originY: Double(by0) + 0.5, stepX: 0, stepY: 1,
                                      startsAtBorder: by0 == 0, endsAtBorder: by1 == h))
            }
        case .rows:
            guard bx1 - bx0 >= minimumLength else { return }
            for y in offsets(from: region.minY, to: region.maxY - k, spacing: spacing) {
                lines.append(ScanLine(family: .rows, offset: Double(y) + half, firstPixel: y * bpr + bx0, step: 1,
                                      across: bpr, sampleCount: bx1 - bx0, originX: Double(bx0) + 0.5,
                                      originY: Double(y) + half, stepX: 1, stepY: 0,
                                      startsAtBorder: bx0 == 0, endsAtBorder: bx1 == w))
            }
        case .diagonal, .antiDiagonal:
            // A full sample at u sums pixels (u + j, y(u) -/+ j), j < k; the half sample after it
            // is the same footprint one pixel to the right. `c` identifies the line: x - y of the
            // first footprint pixel for diagonals, x + y for anti-diagonals.
            let isDiagonal = family == .diagonal
            let diagonalSpacing = max(1, Int((Double(spacing) * 2.0.squareRoot()).rounded()))
            let spread = k - 1
            let low = isDiagonal ? region.minX - (region.maxY - 1) - spread : region.minX + region.minY - spread
            let high = isDiagonal ? region.maxX - 1 - region.minY - spread : region.maxX + region.maxY - 2 - spread
            for c in offsets(from: low, to: high, spacing: diagonalSpacing) {
                let uStart, uEnd: Int
                let startsAtBorder, endsAtBorder: Bool
                if isDiagonal {
                    uStart = max(bx0, by0 + spread + c)
                    uEnd = min(bx1 - k, by1 - 1 + c)
                    startsAtBorder = (uStart == bx0 && bx0 == 0) || (uStart == by0 + spread + c && by0 == 0)
                    endsAtBorder = (uEnd == bx1 - k && bx1 == w) || (uEnd == by1 - 1 + c && by1 == h)
                } else {
                    uStart = max(bx0, c - by1 + k)
                    uEnd = min(bx1 - k, c - by0)
                    startsAtBorder = (uStart == bx0 && bx0 == 0) || (uStart == c - by1 + k && by1 == h)
                    endsAtBorder = (uEnd == bx1 - k && bx1 == w) || (uEnd == c - by0 && by0 == 0)
                }
                guard Double(uEnd - uStart) * 2.0.squareRoot() >= Double(minimumLength) else { continue }
                let y = isDiagonal ? uStart - c : c - uStart
                let centreY = isDiagonal ? Double(y) - Double(spread) / 2 : Double(y) + Double(spread) / 2
                lines.append(ScanLine(family: family, offset: Double(c + spread) / 2.0.squareRoot(),
                                      firstPixel: y * bpr + uStart, step: isDiagonal ? bpr + 1 : 1 - bpr,
                                      across: isDiagonal ? 1 - bpr : 1 + bpr, sampleCount: 2 * (uEnd - uStart) + 1,
                                      originX: Double(uStart) + Double(spread) / 2 + 0.5, originY: centreY + 0.5,
                                      stepX: 0.5, stepY: isDiagonal ? 0.5 : -0.5,
                                      startsAtBorder: startsAtBorder, endsAtBorder: endsAtBorder))
            }
        }
    }

    /// Evenly spaced positions in `from...to`, centred in the range.
    private static func offsets(from low: Int, to high: Int, spacing: Int) -> StrideThrough<Int> {
        guard high >= low else { return stride(from: 0, through: -1, by: 1) }
        let count = (high - low) / spacing + 1
        let first = low + ((high - low) - (count - 1) * spacing) / 2
        return stride(from: first, through: first + (count - 1) * spacing, by: spacing)
    }
}
