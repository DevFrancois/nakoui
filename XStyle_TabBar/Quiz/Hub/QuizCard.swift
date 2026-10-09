import SwiftUI

/// A quiz on the hub: its symbol, name, pitch, length and best score, on
/// glass. Not interactive glass: the hub sits in the Home pager, so most
/// touches on a card are swipes, and interactive glass would run its touch
/// effect through every swipe and every bounce past the last page.
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
                    Text("^[\(kind.questionCount) question](inflect: true)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    QuizBestScoreBadge(kind: kind)
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
        .glassEffect(.regular, in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
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
