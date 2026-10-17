import SwiftUI

/// A history entry in a list: its icon, title, and source with the time.
struct HistoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: HistoryItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HistoryKindIcon(kind: item.kind)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                Text("\(item.source) · \(Text(item.date, format: .dateTime.hour().minute()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
