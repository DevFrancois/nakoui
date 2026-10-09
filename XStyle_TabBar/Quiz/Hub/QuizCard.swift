import SwiftUI

/// A quiz on the hub: its symbol, name, pitch, length and best score, on
/// interactive glass that answers the touch.
struct QuizCard: View {
    let kind: QuizKind

    var body: some View {
        HStack(spacing: QuizMetrics.sectionSpacing) {
            Image(systemName: kind.symbol)
                .font(.title2)
                .foregroundStyle(kind.tint)
                .frame(width: QuizMetrics.iconSize, height: QuizMetrics.iconSize)
                .background(kind.tint.quaternary, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title)
                    .font(.headline)

                Text(kind.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(kind.lengthLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if kind.isScored {
                        QuizBestScoreBadge(kind: kind)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.forward")
                .font(.footnote)
                .bold()
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding()
        .contentShape(.rect(cornerRadius: QuizMetrics.cardCornerRadius))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack {
        ForEach(QuizKind.allCases) { kind in
            QuizCard(kind: kind)
        }
    }
    .padding()
    .background(.teal.gradient)
}
