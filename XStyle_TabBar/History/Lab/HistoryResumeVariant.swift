import SwiftUI

/// 8 · Resume: the latest unfinished entry as a big "pick up where you left
/// off" card, then everything else with progress bars.
struct HistoryResumeVariant: View {
    private var current: HistoryItem? {
        HistoryItem.samples.first { ($0.progress ?? 1) < 1 }
    }

    var body: some View {
        List {
            if let current {
                Section {
                    hero(current)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Recently Viewed") {
                ForEach(HistoryItem.samples.filter { $0.id != current?.id }) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HistoryRow(item: item)

                        if let progress = item.progress {
                            ProgressView(value: progress)
                                .tint(item.kind.tint)
                                .padding(.leading, 48)
                                .accessibilityLabel(progress == 1 ? "Finished" : "Progress")
                        }
                    }
                }
            }
        }
    }

    private func hero(_ item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Continue", systemImage: "play.fill")
                .font(.caption.bold())
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.85))

            Text(item.title)
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(item.source)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))

            ProgressView(value: item.progress ?? 0)
                .tint(.white)

            Text("\(Int((item.progress ?? 0) * 100))% done")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [item.kind.tint, item.kind.tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .accessibilityElement(children: .combine)
    }
}
