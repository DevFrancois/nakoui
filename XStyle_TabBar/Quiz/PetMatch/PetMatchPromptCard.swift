import SwiftUI

/// The question, large on pink-tinted glass under a gently breathing symbol.
struct PetMatchPromptCard: View {
    let question: PetMatchQuestion

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: question.symbol)
                .font(.largeTitle)
                .foregroundStyle(QuizKind.petMatch.tint)
                .symbolEffect(.breathe, isActive: !reduceMotion)
                .accessibilityHidden(true)

            Text(question.prompt)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding()
        .glassEffect(
            .regular.tint(QuizKind.petMatch.tint.opacity(0.12)),
            in: .rect(cornerRadius: QuizMetrics.cardCornerRadius)
        )
    }
}

#Preview {
    PetMatchPromptCard(question: PetMatchRounds.all[0])
        .padding()
        .background(.pink.gradient)
}
