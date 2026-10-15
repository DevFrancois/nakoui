import SwiftUI

/// One day's history entries, for sectioned lists.
struct HistoryDay: Identifiable {
    let day: Date
    let items: [HistoryItem]

    var id: Date { day }

    /// "Today", "Yesterday", or the weekday and date.
    var title: Text {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            return Text("Today")
        } else if calendar.isDateInYesterday(day) {
            return Text("Yesterday")
        } else {
            return Text(day, format: .dateTime.weekday(.wide).day().month())
        }
    }

    /// Groups entries by day, newest day first, keeping each day's order.
    static func days(from items: [HistoryItem]) -> [HistoryDay] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { HistoryDay(day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }
}
