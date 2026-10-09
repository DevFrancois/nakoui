import SwiftUI

/// The white bloom: square tiles pop up at seed points and grow until their
/// union fills the card. Seeds sweep from top to bottom with a fixed jitter,
/// after a few anchors near the guards go first, like the finder patterns in
/// the reference. A pure function of time, so a timeline drives it.
nonisolated struct BloomPlan: Equatable, Sendable {
    struct Seed: Equatable, Sendable {
        /// Unit coordinates inside the card.
        var center: CGPoint
        /// Seconds after the bloom begins.
        var start: Double
    }

    private(set) var seeds: [Seed] = []
    /// A tile's full size, relative to the larger cell side.
    private let growth = 2.4
    private let growDuration = 0.12
    private let cellWidth: CGFloat
    private let cellHeight: CGFloat
    /// After this the card is solid, so no pinholes remain.
    static let duration = 0.3

    /// - Parameter aspect: The card's width over its height.
    init(aspect: CGFloat) {
        let rows = 5
        let columns = max(rows, Int((CGFloat(rows) * aspect).rounded()))
        cellWidth = 1 / CGFloat(columns)
        cellHeight = 1 / CGFloat(rows)

        let anchors = [CGPoint(x: 0.08, y: 0.3), CGPoint(x: 0.5, y: 0.3), CGPoint(x: 0.92, y: 0.3)]
        seeds = anchors.enumerated().map { Seed(center: $0.element, start: 0.025 * Double($0.offset)) }

        // splitmix64, so the layout is the same every time.
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func random() -> CGFloat {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return CGFloat(z ^ (z >> 31)) / CGFloat(UInt64.max)
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let center = CGPoint(
                    x: (CGFloat(column) + 0.5 + (random() - 0.5) * 0.6) * cellWidth,
                    y: (CGFloat(row) + 0.5 + (random() - 0.5) * 0.6) * cellHeight
                )
                let start = 0.05 + 0.13 * Double(row) / Double(rows - 1) + Double(random() - 0.5) * 0.05
                seeds.append(Seed(center: center, start: max(0, start)))
            }
        }
    }

    /// The tiles at `time`, in the coordinates of `card`.
    func tiles(in card: CGRect, at time: Double) -> [CGRect] {
        let size = max(card.width * cellWidth, card.height * cellHeight) * growth
        return seeds.compactMap { seed in
            guard time > seed.start else { return nil }
            let side = size * UnitCurve.easeOut.value(at: min((time - seed.start) / growDuration, 1))
            let center = CGPoint(x: card.minX + seed.center.x * card.width, y: card.minY + seed.center.y * card.height)
            return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        }
    }
}
