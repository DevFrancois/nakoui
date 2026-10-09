import SwiftUI

/// The four breeds to pick from, as glass answers that settle green or red.
/// Once one is picked, the mystery pet steps out: its reveal, a fun fact and
/// the way on morph in below the answers.
struct MysteryPetAnswerPanel: View {
    let breed: MysteryPetBreed
    let session: QuizSession
    let selection: Int?
    let cluesUsed: Int
    let tint: Color
    let choose: (Int) -> Void
    let next: () -> Void

    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: MysteryPetMetrics.glassSpacing) {
            VStack(spacing: MysteryPetMetrics.clueSpacing) {
                ForEach(breed.choices.indices, id: \.self) { index in
                    ChoiceButton(title: breed.choices[index], state: state(of: index)) {
                        choose(index)
                    }
                    .glassEffectID(MysteryPetGlassID.choice(index), in: glassNamespace)
                }

                if let outcome = session.outcome {
                    MysteryPetRevealCard(breed: breed, outcome: outcome, cluesUsed: cluesUsed, tint: tint)
                        .glassEffectID(MysteryPetGlassID.reveal, in: glassNamespace)
                        .id(MysteryPetScrollTarget.reveal)

                    QuizFactCard(outcome: outcome, fact: breed.fact)
                        .glassEffectID(MysteryPetGlassID.fact, in: glassNamespace)

                    QuizNextButton(tint: tint, isLast: session.isLastQuestion, action: next)
                }
            }
            // With Reduce Motion on, the reveal and fact fade in where they
            // stand instead of travelling out of the answers.
            .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
        }
    }

    private func state(of index: Int) -> ChoiceState {
        guard session.isAnswered else { return .idle }
        if index == breed.answerIndex {
            return .correct
        }
        return index == selection ? .wrong : .dimmed
    }
}
