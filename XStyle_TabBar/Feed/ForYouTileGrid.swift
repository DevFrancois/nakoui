import SwiftUI

/// Columns follow the settled page width, keeping their count and height
/// stable while the page narrows beside the rail.
struct ForYouTileGrid: View {
    @ScaledMetric(relativeTo: .body) private var minimumTileWidth = 160.0
    var settledWidth: CGFloat? = nil
    let onSelect: (ForYouDestination) -> Void

    private static let destinations: [ForYouDestination] = [.first, .second, .third, .fourth]
    private static let spacing: CGFloat = 12

    var body: some View {
        let gridWidth = settledWidth.map { max(0, $0 - 2 * FeedLayoutMetrics.horizontalPadding) }
        let columnCount = gridWidth.map {
            max(1, Int(($0 + Self.spacing) / (CGFloat(minimumTileWidth) + Self.spacing)))
        }
        let columns = columnCount.map {
            Array(repeating: GridItem(.flexible(minimum: 0), spacing: Self.spacing, alignment: .top), count: $0)
        } ?? [GridItem(.adaptive(minimum: minimumTileWidth), spacing: Self.spacing, alignment: .top)]
        let tileWidth = gridWidth.map {
            let count = CGFloat(columnCount ?? 1)
            return max(0, ($0 - Self.spacing * (count - 1)) / count)
        }

        LazyVGrid(columns: columns, spacing: Self.spacing) {
            ForEach(Self.destinations) { destination in
                FeedTile(
                    caption: "Placeholder caption",
                    title: destination.title,
                    tint: destination.tint,
                    size: destination == .first || destination == .second ? .regular : .compact,
                    settledWidth: tileWidth
                ) {
                    onSelect(destination)
                }
            }
        }
        .padding(.horizontal, FeedLayoutMetrics.horizontalPadding)
        .padding(.vertical, 8)
    }
}

#Preview("Large text") {
    ScrollView {
        ForYouTileGrid { _ in }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
