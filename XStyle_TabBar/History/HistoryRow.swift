import SwiftUI

/// A history entry in a list: its icon, title, and source with the time.
struct HistoryRow: View {
    let item: HistoryItem

    var body: some View {
        HStack(spacing: 12) {
            HistoryKindIcon(kind: item.kind)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(item.source)
                    Text("·")
                    Text(item.date, format: .dateTime.hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
