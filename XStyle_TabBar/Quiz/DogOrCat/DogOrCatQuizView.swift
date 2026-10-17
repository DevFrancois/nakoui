import SwiftUI

/// Sort each fact to the right animal: fling the card left for dog or right
/// for cat, or tap the glass buttons, which also serve VoiceOver.
struct DogOrCatQuizView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var session = QuizSession(questionCount: QuizKind.dogOrCat.questionCount)
    @GestureState private var dragOffset: Double?
    @State private var choice: PetSpecies?

    private var statement: SpeciesStatement {
        QuizBank.speciesStatements[session.index]
    }

    var body: some View {
        QuizScreen(kind: .dogOrCat, session: session) {
            QuizRound {
                SpeciesCard(
                    statement: statement,
                    dragOffset: dragOffset ?? 0,
                    answer: session.isAnswered ? statement.species : nil
                )
                .animation(dragOffset == nil && !reduceMotion ? .bouncy : nil, value: dragOffset)
                .gesture(swipe, isEnabled: !session.isAnswered)
                .id(statement.id)
                .quizQuestionTransition()

            } answers: {
                SpeciesQuizAnswers(statement: statement, session: session, choice: choice, choose: choose, next: next)
            }
            .animation(reduceMotion ? nil : .smooth, value: session.outcome)
            .animation(reduceMotion ? nil : .smooth, value: session.index)
        }
    }

    /// Follows the finger, and counts a fling past the threshold as an answer.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragOffset) { value, offset, _ in
                offset = value.translation.width
            }
            .onEnded { value in
                let flung = value.predictedEndTranslation.width
                if abs(flung) > QuizMetrics.swipeThreshold {
                    choose(flung < 0 ? .dog : .cat)
                }
            }
    }

    private func choose(_ species: PetSpecies) {
        guard !session.isAnswered else { return }
        choice = species
        session.submit(isCorrect: species == statement.species)
    }

    private func next() {
        choice = nil
        session.advance()
    }
}

private struct SpeciesQuizAnswers: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let statement: SpeciesStatement
    let session: QuizSession
    let choice: PetSpecies?
    let choose: (PetSpecies) -> Void
    let next: () -> Void

    @Namespace private var glassNamespace

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
            VStack(spacing: QuizMetrics.sectionSpacing) {
                layout {
                    ForEach(PetSpecies.allCases, id: \.self) { species in
                        AnswerTile(title: species.title, systemImage: species.symbol, tint: species.tint, state: state(of: species)) {
                            choose(species)
                        }
                        .glassEffectID(species, in: glassNamespace)
                    }
                }

                if let outcome = session.outcome {
                    QuizFactCard(outcome: outcome, fact: statement.fact)
                        .glassEffectID("fact", in: glassNamespace)

                    QuizNextButton(tint: QuizKind.dogOrCat.tint, isLast: session.isLastQuestion, action: next)
                }
            }
        }
    }

    private func state(of species: PetSpecies) -> ChoiceState {
        guard session.isAnswered else { return .idle }
        if species == statement.species {
            return .correct
        }
        return species == choice ? .wrong : .dimmed
    }
}

#Preview {
    NavigationStack {
        QuizDestination(kind: .dogOrCat)
    }
}
