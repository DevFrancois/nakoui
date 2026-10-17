import SwiftUI

/// The Quizz tab's page: a short intro and a glass card per quiz.
struct QuizHub: View {
    var body: some View {
        VStack(alignment: .leading, spacing: QuizMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pet Quizz")
                    .font(.largeTitle)
                    .bold()
                    .accessibilityAddTraits(.isHeader)

                Text("How well do you know dogs and cats? Pick a game.")
                    .foregroundStyle(.secondary)
            }

            // One container renders the cards' glass together.
            GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
                VStack(spacing: QuizMetrics.sectionSpacing) {
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
        .frame(maxWidth: QuizMetrics.contentMaxWidth)
        .frame(maxWidth: .infinity)
    }
}
