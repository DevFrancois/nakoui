import SwiftUI

/// 5 · Log: one dense line per entry, a monospaced time column and a small
/// colored symbol, for scanning a lot at once.
struct HistoryLogVariant: View {
    var body: some View {
        List {
            ForEach(HistoryDay.days(from: HistoryItem.samples)) { day in
                Section {
                    ForEach(day.items) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(item.date, format: .dateTime.hour().minute())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .leading)

                            Image(systemName: item.kind.symbol)
                                .font(.caption)
                                .foregroundStyle(item.kind.tint)
                                .accessibilityHidden(true)

                            Text(item.title)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
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
