import SwiftUI

/// 7 · Filters: glass chips across the top narrow the list to one kind.
struct HistoryFiltersVariant: View {
    @State private var filter: HistoryKind?

    private var items: [HistoryItem] {
        guard let filter else { return HistoryItem.samples }
        return HistoryItem.samples.filter { $0.kind == filter }
    }

    var body: some View {
        List {
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
        .safeAreaInset(edge: .top, spacing: 0) {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        chip(nil)

                        ForEach(HistoryKind.allCases) { kind in
                            chip(kind)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .animation(.snappy, value: filter)
    }

    private func chip(_ kind: HistoryKind?) -> some View {
        let isSelected = filter == kind

        return Button {
            filter = kind
        } label: {
            Label {
                if let kind {
                    Text(kind.title)
                } else {
                    Text("All")
                }
            } icon: {
                Image(systemName: kind?.symbol ?? "square.grid.2x2.fill")
                    .foregroundStyle(kind?.tint ?? .primary)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint((kind?.tint ?? .accentColor).opacity(0.35)) : .regular, in: .capsule)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
