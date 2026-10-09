import SwiftUI

/// How the board went against par, then a fun fact, on glass tinted by the
/// verdict. The verdict carries a symbol and words, not just a color.
struct PawPairsVerdictCard: View {
    let verdict: PawPairsVerdict
    let fact: LocalizedStringResource

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(verdict.title, systemImage: verdict.symbol)
                .font(.headline)
                .foregroundStyle(verdict.tint)
                .symbolEffect(.bounce, value: hasAppeared)
                .symbolEffectsRemoved(reduceMotion)

            Text(verdict.detail)
                .font(.subheadline)

            Label {
                Text(fact)
            } icon: {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(QuizKind.pawPairs.tint)
            }
            .font(.callout)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(
            .regular.tint(verdict.tint.opacity(0.15)),
            in: .rect(cornerRadius: QuizMetrics.cardCornerRadius)
        )
        .accessibilityElement(children: .combine)
        .onAppear(perform: celebrate)
    }

    private func celebrate() {
        hasAppeared = true
    }
}

#Preview {
    PawPairsVerdictCard(
        verdict: PawPairsVerdict(moves: 11, par: 14, pairCount: 6),
        fact: PawPairsRounds.all[0].fact
    )
    .padding()
    .background(.indigo.gradient)
}
