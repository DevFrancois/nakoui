import SwiftUI

/// A quiz on the hub: its symbol, name, pitch, length and best score, on
/// glass. Not interactive glass: the hub sits in the Home pager, so most
/// touches on a card are swipes, and interactive glass would run its touch
/// effect through every swipe and every bounce past the last page.
struct QuizCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let kind: QuizKind
    var settledWidth: CGFloat? = nil

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: QuizMetrics.sectionSpacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: QuizMetrics.sectionSpacing))

        SettledWidthLayout(width: settledWidth.map { max(0, $0 - 2 * FeedLayoutMetrics.horizontalPadding) }) {
            layout {
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

                    VStack(alignment: .leading, spacing: 4) {
                        Text("^[\(kind.questionCount) question](inflect: true)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        QuizBestScoreBadge(kind: kind)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FeedLayoutMetrics.horizontalPadding)
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
