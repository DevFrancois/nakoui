import SwiftUI

/// The question or claim being asked, large on a glass card.
struct QuizQuestionCard: View {
    let prompt: LocalizedStringResource

    var body: some View {
        Text(prompt)
            .font(.title2)
            .bold()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding()
            .glassEffect(in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    QuizQuestionCard(prompt: "How many teeth does an adult dog have?")
        .padding()
        .background(.teal.gradient)
}
