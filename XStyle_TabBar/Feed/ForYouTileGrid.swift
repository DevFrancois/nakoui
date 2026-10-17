import SwiftUI

/// A single set of cards reflows as their readable minimum width changes.
struct ForYouTileGrid: View {
    @ScaledMetric(relativeTo: .body) private var minimumTileWidth = 160.0
    let onSelect: (ForYouDestination) -> Void

    private static let destinations: [ForYouDestination] = [.first, .second, .third, .fourth]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumTileWidth), spacing: 12, alignment: .top)], spacing: 12) {
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

#Preview("Large text") {
    ScrollView {
        ForYouTileGrid { _ in }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
