import SwiftUI

/// 3 · Cards: big cards with a tinted artwork band, title, source and how
/// long ago it was opened.
struct HistoryCardsVariant: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(HistoryItem.samples) { item in
                    card(item)
                }
            }
            .padding()
        }
    }

    private func card(_ item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [item.kind.tint, item.kind.tint.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: item.kind.symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding()
                    .accessibilityHidden(true)
            }
            .frame(height: 120)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)

                HStack {
                    Text(item.source)
                    Spacer()
                    Text(item.date, format: .relative(presentation: .named))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(.fill.quaternary)
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}
