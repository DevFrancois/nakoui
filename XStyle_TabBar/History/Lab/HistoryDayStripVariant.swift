import SwiftUI

/// 6 · Day strip: the last seven days across the top, like a calendar week,
/// showing one day's history at a time.
struct HistoryDayStripVariant: View {
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
            strip
        }
        .animation(.snappy, value: selectedDay)
    }

    private var strip: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isSelected = day == selectedDay
                let count = HistoryItem.samples.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.count

                Button {
                    selectedDay = day
                } label: {
                    VStack(spacing: 4) {
                        Text(day, format: .dateTime.weekday(.narrow))
                            .font(.caption2.bold())
                            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)

                        Text(day, format: .dateTime.day())
                            .font(.headline.monospacedDigit())

                        Circle()
                            .fill(count > 0 ? (isSelected ? Color.white : Color.accentColor) : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.quaternary), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month()))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
