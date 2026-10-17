import SwiftUI

/// 5 · Log: one dense line per entry, a monospaced time column and a small
/// colored symbol, for scanning a lot at once.
struct HistoryLogVariant: View {
    var body: some View {
        List {
            ForEach(HistoryDay.days(from: HistoryItem.samples)) { day in
                Section {
                    ForEach(day.items) { item in
                        HistoryLogRow(item: item)
                    }
                } header: {
                    day.title
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 36)
    }
}

private struct HistoryLogRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: HistoryItem

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))

        layout {
            Label {
                Text(item.date, format: .dateTime.hour().minute())
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: item.kind.symbol)
                    .foregroundStyle(item.kind.tint)
                    .accessibilityHidden(true)
            }
            .font(.caption.monospacedDigit())
            .fixedSize()

            Text(item.title)
                .font(.subheadline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .accessibilityElement(children: .combine)
    }
}
