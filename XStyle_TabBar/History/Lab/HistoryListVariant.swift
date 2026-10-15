import SwiftUI

/// 1 · List: a grouped list by day, like Settings, with swipe to delete.
struct HistoryListVariant: View {
    @State private var items = HistoryItem.samples

    var body: some View {
        List {
            ForEach(HistoryDay.days(from: items)) { day in
                Section {
                    ForEach(day.items) { item in
                        HistoryRow(item: item)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    withAnimation {
                                        items.removeAll { $0.id == item.id }
                                    }
                                }
                            }
                    }
                } header: {
                    day.title
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
