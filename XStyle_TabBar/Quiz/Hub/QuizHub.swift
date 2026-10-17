import SwiftUI

/// The Quizz tab's page: a short intro and a glass card per quiz.
struct QuizHub: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumCardWidth = 280.0
    var settledWidth: CGFloat? = nil

    var body: some View {
        let spacing = CGFloat(QuizMetrics.sectionSpacing)
        let gridWidth = settledWidth.map {
            max(0, min($0, CGFloat(QuizMetrics.hubMaxWidth)) - 2 * FeedLayoutMetrics.horizontalPadding)
        }
        let columnCount = gridWidth.map {
            dynamicTypeSize.isAccessibilitySize
                ? 1
                : max(1, Int(($0 + spacing) / (CGFloat(minimumCardWidth) + spacing)))
        }
        let columns = columnCount.map {
            Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing, alignment: .top), count: $0)
        } ?? [GridItem(
            dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: minimumCardWidth),
            spacing: spacing,
            alignment: .top
        )]
        let cardWidth = gridWidth.map {
            let count = CGFloat(columnCount ?? 1)
            return max(0, ($0 - spacing * (count - 1)) / count)
        }

        VStack(alignment: .leading, spacing: QuizMetrics.sectionSpacing) {
            SettledWidthLayout(width: gridWidth) {
                QuizHubIntroduction()
            }

            // One container renders the cards' glass together.
            GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: QuizMetrics.sectionSpacing) {
                    ForEach(QuizKind.allCases) { kind in
                        NavigationLink(value: kind) {
                            QuizCard(kind: kind, settledWidth: cardWidth)
                        }
                        .buttonStyle(QuizCardButtonStyle())
                    }
                }
            }
        }
        .padding(FeedLayoutMetrics.horizontalPadding)
        .frame(maxWidth: QuizMetrics.hubMaxWidth)
        .frame(maxWidth: .infinity)
    }
}

private struct QuizHubIntroduction: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pet Quizz")
                .font(.largeTitle)
                .bold()
                .accessibilityAddTraits(.isHeader)

            Text("How well do you know dogs and cats? Pick a game.")
                .foregroundStyle(.secondary)
        }
    }
}
