import SwiftUI

/// 2 · Timeline: times down the left, a line joining colored dots, and the
/// entries beside them, with each day's heading pinned while it scrolls.
struct HistoryTimelineVariant: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(HistoryDay.days(from: HistoryItem.samples)) { day in
                    Section {
                        ForEach(day.items) { item in
                            row(item, isLast: item.id == day.items.last?.id)
                        }
                    } header: {
                        day.title
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(.bar)
                    }
                }
            }
        }
    }

    private func row(_ item: HistoryItem, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.date, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
                .padding(.top, 2)

            VStack(spacing: 0) {
                Circle()
                    .fill(item.kind.tint)
                    .frame(width: 12, height: 12)
                    .padding(.top, 3)

                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .opacity(isLast ? 0 : 1)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.semibold))

                Label {
                    Text(item.source)
                } icon: {
                    Image(systemName: item.kind.symbol)
                        .foregroundStyle(item.kind.tint)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 20)
        }
        // Natural height, so the line fills the row exactly.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}
