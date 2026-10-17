import SwiftUI

/// The Quizz tab's page: a short intro and a glass card per quiz.
struct QuizHub: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumCardWidth = 280.0

    var body: some View {
        VStack(alignment: .leading, spacing: QuizMetrics.sectionSpacing) {
            QuizHubIntroduction()

            // One container renders the cards' glass together.
            GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: QuizMetrics.sectionSpacing) {
                    ForEach(QuizKind.allCases) { kind in
                        NavigationLink(value: kind) {
                            QuizCard(kind: kind)
                        }
                        .buttonStyle(QuizCardButtonStyle())
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: QuizMetrics.hubMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var columns: [GridItem] {
        [GridItem(
            dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: minimumCardWidth),
            spacing: QuizMetrics.sectionSpacing,
            alignment: .top
        )]
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
