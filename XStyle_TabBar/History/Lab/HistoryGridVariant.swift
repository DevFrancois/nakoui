import SwiftUI

/// 4 · Grid: square tinted thumbnails in two columns, like a photo library,
/// grouped by day.
struct HistoryGridVariant: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth = 150.0

    private var columns: [GridItem] {
        [GridItem(dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: minimumColumnWidth), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(HistoryDay.days(from: HistoryItem.samples)) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        day.title
                            .font(.title3.bold())

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(day.items) { item in
                                HistoryGridTile(item: item)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

}

private struct HistoryGridTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: HistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(item.kind.tint.gradient)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: item.kind.symbol)
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                }
                .clipShape(.rect(cornerRadius: 18))
                .accessibilityHidden(true)

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

            Text(item.source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .accessibilityElement(children: .combine)
    }
}
