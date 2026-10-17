import SwiftUI

/// 6 · Day strip: the last seven days across the top, like a calendar week,
/// showing one day's history at a time.
struct HistoryDayStripVariant: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Fixed when the screen opens, so the strip doesn't shift under the
    /// selection at midnight.
    @State private var today = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    private var days: [Date] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private var items: [HistoryItem] {
        HistoryItem.samples.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView("Nothing This Day", systemImage: "clock", description: Text("Pick another day above."))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(items) { item in
                    HistoryRow(item: item)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HistoryDayStrip(days: days, selectedDay: $selectedDay)
        }
        .animation(reduceMotion ? nil : .snappy, value: selectedDay)
    }
}

private struct HistoryDayStrip: View {
    let days: [Date]
    @Binding var selectedDay: Date
    @ScaledMetric(relativeTo: .headline) private var dayWidth = 44.0

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    HistoryDayButton(
                        day: day,
                        isSelected: day == selectedDay,
                        hasItems: HistoryItem.samples.contains { Calendar.current.isDate($0.date, inSameDayAs: day) },
                        minimumWidth: dayWidth
                    ) {
                        selectedDay = day
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.trailing, for: .initialOffset)
        .background(.bar)
    }
}

private struct HistoryDayButton: View {
    let day: Date
    let isSelected: Bool
    let hasItems: Bool
    let minimumWidth: CGFloat
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                Text(day, format: .dateTime.weekday(.narrow))
                    .font(.caption2.bold())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)

                Text(day, format: .dateTime.day())
                    .font(.headline.monospacedDigit())

                Circle()
                    .fill(hasItems ? (isSelected ? Color.white : Color.accentColor) : .clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.vertical, 8)
            .frame(minWidth: minimumWidth, minHeight: 64)
            .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.quaternary), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month()))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
