import SwiftUI

/// The verdict and a fun fact, on glass tinted by the outcome. The verdict
/// carries a symbol and words, not just a color.
struct QuizFactCard: View {
    let outcome: QuizOutcome
    let fact: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(outcome.title, systemImage: outcome.symbol)
                .font(.headline)
                .foregroundStyle(outcome.tint)

            Text(fact)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(
            .regular.tint(outcome.tint.opacity(0.15)),
            in: .rect(cornerRadius: QuizMetrics.cardCornerRadius)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    QuizFactCard(outcome: .correct, fact: "A group of kittens has its own name too: a kindle.")
        .padding()
        .background(.teal.gradient)
}
