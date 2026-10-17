import SwiftUI

/// A single set of cards reflows as their readable minimum width changes.
/// Columns follow the grid's width at rest, keeping their count and height
/// while the page narrows beside the rail.
struct ForYouTileGrid: View {
    @ScaledMetric(relativeTo: .body) private var minimumTileWidth = 160.0
    @Environment(\.holdsSettledWidth) private var holdsWidth
    let onSelect: (ForYouDestination) -> Void

    private static let destinations: [ForYouDestination] = [.first, .second, .third, .fourth]

    var body: some View {
        SettledColumnsLayout(minimumColumnWidth: minimumTileWidth, spacing: 12, holdsWidth: holdsWidth) {
            ForEach(Self.destinations) { destination in
                FeedTile(
                    caption: "Placeholder caption",
                    title: destination.title,
                    tint: destination.tint,
                    size: destination == .first || destination == .second ? .regular : .compact
                ) {
                    onSelect(destination)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// As many equal columns as fit the minimum width, counted at the width the
/// grid last had at rest. Items stretch with the current width.
private struct SettledColumnsLayout: Layout {
    let minimumColumnWidth: CGFloat
    let spacing: CGFloat
    let holdsWidth: Bool

    struct Cache {
        var restingWidth: CGFloat?
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    /// The resting width outlives the update that starts holding it.
    func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? cache.restingWidth ?? minimumColumnWidth
        let rows = rows(width: width, subviews: subviews, cache: cache)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        if !holdsWidth {
            cache.restingWidth = bounds.width
        }
        let columnWidth = columnWidth(width: bounds.width, cache: cache)
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews, cache: cache) {
            for (column, index) in row.indices.enumerated() {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (columnWidth + spacing), y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: columnWidth, height: nil)
                )
            }
            y += row.height + spacing
        }
    }

    private func columnCount(width: CGFloat, cache: Cache) -> Int {
        let countedWidth = holdsWidth ? cache.restingWidth ?? width : width
        return max(1, Int((countedWidth + spacing) / (minimumColumnWidth + spacing)))
    }

    private func columnWidth(width: CGFloat, cache: Cache) -> CGFloat {
        let count = CGFloat(columnCount(width: width, cache: cache))
        return max(0, (width - spacing * (count - 1)) / count)
    }

    private func rows(width: CGFloat, subviews: Subviews, cache: Cache) -> [(indices: Range<Int>, height: CGFloat)] {
        let count = columnCount(width: width, cache: cache)
        let proposal = ProposedViewSize(width: columnWidth(width: width, cache: cache), height: nil)
        return stride(from: 0, to: subviews.count, by: count).map { start in
            let indices = start..<min(start + count, subviews.count)
            let height = indices.map { subviews[$0].sizeThatFits(proposal).height }.max() ?? 0
            return (indices, height)
        }
    }
}

#Preview("Large text") {
    ScrollView {
        ForYouTileGrid { _ in }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
