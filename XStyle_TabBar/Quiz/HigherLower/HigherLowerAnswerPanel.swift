import SwiftUI

/// The two calls, worded from the round's stat, with the fact and Next
/// morphing out of them once the verdict lands. The tiles stack at
/// accessibility text sizes, so their words never break mid-word.
struct HigherLowerAnswerPanel: View {
    let round: HigherLowerRound
    /// The player's call; nil until it's made.
    let guess: HigherLowerGuess?
    /// Nil until the round is settled, which happens once the count-up ends.
    let outcome: QuizOutcome?
    let isLast: Bool
    let call: (HigherLowerGuess) -> Void
    let next: () -> Void

    @Namespace private var glassNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let tileLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: HigherLowerMetrics.tileSpacing))
            : AnyLayout(HStackLayout(spacing: HigherLowerMetrics.tileSpacing))

        GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
            VStack(spacing: QuizMetrics.sectionSpacing) {
                tileLayout {
                    ForEach(HigherLowerGuess.allCases, id: \.self) { option in
                        AnswerTile(
                            title: round.stat.title(for: option),
                            systemImage: option.symbol,
                            tint: option.tint,
                            state: state(of: option)
                        ) {
                            call(option)
                        }
                        .glassEffectID(option, in: glassNamespace)
                    }
                }

                if let outcome {
                    QuizFactCard(outcome: outcome, fact: round.fact)
                        .glassEffectID("fact", in: glassNamespace)

                    QuizNextButton(tint: QuizKind.higherLower.tint, isLast: isLast, action: next)
                        .id(HigherLowerScrollTarget.next)
                }
            }
        }
    }

    private func state(of option: HigherLowerGuess) -> ChoiceState {
        guard let guess else { return .idle }
        // While the value counts up, the call stays lit and the other steps back.
        guard outcome != nil else { return option == guess ? .idle : .dimmed }
        if option == round.answer {
            return .correct
        }
        return option == guess ? .wrong : .dimmed
    }
}

#Preview {
    HigherLowerAnswerPanel(
        round: HigherLowerRounds.all[0],
        guess: .lower,
        outcome: .wrong,
        isLast: false,
        call: { _ in },
        next: {}
    )
    .padding()
    .background(.red.gradient)
}
