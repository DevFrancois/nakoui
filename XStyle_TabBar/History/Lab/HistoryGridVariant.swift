import SwiftUI

/// 4 · Grid: square tinted thumbnails in two columns, like a photo library,
/// grouped by day.
struct HistoryGridVariant: View {
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(HistoryDay.days(from: HistoryItem.samples)) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        day.title
                            .font(.title3.bold())

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(day.items) { item in
                                tile(item)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func tile(_ item: HistoryItem) -> some View {
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
                .lineLimit(2, reservesSpace: true)

            Text(item.source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
