import Charts
import SwiftUI

/// 10 · Stats: a week at a glance, a stacked bar per day by kind and a
/// count per kind, above the full list.
struct HistoryStatsVariant: View {
    @ScaledMetric(relativeTo: .caption2) private var minimumSummaryWidth = 72.0
    @ScaledMetric(relativeTo: .caption) private var chartHeight = 140.0
    private let items = HistoryItem.samples

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(items.count) things this week")
                        .font(.title2.bold())

                    Chart(items) { item in
                        BarMark(
                            x: .value("Day", item.date, unit: .day),
                            y: .value("Opened", 1)
                        )
                        .foregroundStyle(item.kind.tint)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
                    }
                    .frame(height: chartHeight)
                    .accessibilityLabel("Items opened per day this week")

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumSummaryWidth), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(HistoryKind.allCases) { kind in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(items.filter { $0.kind == kind }.count, format: .number)
                                    .font(.headline.monospacedDigit())

                                Text(kind.title)
                                    .font(.caption2)
                                    .foregroundStyle(kind.tint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            ForEach(HistoryDay.days(from: items)) { day in
                Section {
                    ForEach(day.items) { item in
                        HistoryRow(item: item)
                    }
                } header: {
                    day.title
                }
            }
        }
    }
}
