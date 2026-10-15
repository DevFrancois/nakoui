import SwiftUI

/// 9 · Glass: each entry on a Liquid Glass capsule, floating over a soft
/// colored backdrop.
struct HistoryGlassVariant: View {
    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 10) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(HistoryDay.days(from: HistoryItem.samples)) { day in
                        day.title
                            .font(.headline)
                            .padding(.top, 12)
                            .padding(.leading, 8)

                        ForEach(day.items) { item in
                            HStack(spacing: 12) {
                                HistoryKindIcon(kind: item.kind, size: 34)
                                    .clipShape(.circle)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)

                                    Text(item.source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)

                                Text(item.date, format: .dateTime.hour().minute())
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .padding(.trailing, 8)
                            .glassEffect(.regular, in: .capsule)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding()
            }
        }
        .background {
            LinearGradient(
                colors: [.purple.opacity(0.35), .blue.opacity(0.25), .teal.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}
