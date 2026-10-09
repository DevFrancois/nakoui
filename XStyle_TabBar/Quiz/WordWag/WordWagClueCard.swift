import SwiftUI

/// The hint, on warm glass that morphs out of the Hint button.
struct WordWagClueCard: View {
    let clue: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Hint", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(clue)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(
            .regular.tint(.yellow.opacity(0.18)),
            in: .rect(cornerRadius: QuizMetrics.answerCornerRadius)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WordWagClueCard(clue: "A merry scent hound, just like Snoopy.")
        .padding()
        .background(.mint.gradient)
}
