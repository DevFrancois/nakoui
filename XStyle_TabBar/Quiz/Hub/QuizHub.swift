import SwiftUI

/// The Quizz tab's page: a short intro and a glass card per quiz, each
/// zooming open into its quiz.
struct QuizHub: View {
    let namespace: Namespace.ID

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

            ForEach(QuizKind.allCases) { kind in
                NavigationLink(value: kind) {
                    QuizCard(kind: kind)
                        .matchedTransitionSource(id: kind, in: namespace) { source in
                            source.clipShape(.rect(cornerRadius: QuizMetrics.cardCornerRadius))
                        }
                }
                .buttonStyle(PassthroughButtonStyle())
            }
        }
        .padding()
        .frame(maxWidth: QuizMetrics.contentMaxWidth)
        .frame(maxWidth: .infinity)
    }
}
