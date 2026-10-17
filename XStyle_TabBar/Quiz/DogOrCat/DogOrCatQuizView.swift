import SwiftUI

/// Sort each fact to the right animal: fling the card left for dog or right
/// for cat, or tap the glass buttons, which also serve VoiceOver.
struct DogOrCatQuizView: View {
    @State private var session = QuizSession(questionCount: QuizKind.dogOrCat.questionCount)
    @GestureState private var dragOffset: Double?
    @State private var choice: PetSpecies?
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var statement: SpeciesStatement {
        QuizBank.speciesStatements[session.index]
    }

    var body: some View {
        QuizScreen(kind: .dogOrCat, session: session) {
            VStack(spacing: QuizMetrics.sectionSpacing) {
                SpeciesCard(
                    statement: statement,
                    dragOffset: dragOffset ?? 0,
                    answer: session.isAnswered ? statement.species : nil
                )
                .animation(dragOffset == nil && !reduceMotion ? .bouncy : nil, value: dragOffset)
                .gesture(swipe, isEnabled: !session.isAnswered)
                .id(statement.id)
                .quizQuestionTransition()

                GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
                    VStack(spacing: QuizMetrics.sectionSpacing) {
                        HStack(spacing: 12) {
                            ForEach(PetSpecies.allCases, id: \.self) { species in
                                AnswerTile(
                                    title: species.title,
                                    systemImage: species.symbol,
                                    tint: species.tint,
                                    state: state(of: species)
                                ) {
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
            .animation(.smooth, value: session.outcome)
            .animation(.smooth, value: session.index)
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

    private func state(of species: PetSpecies) -> ChoiceState {
        guard session.isAnswered else { return .idle }
        if species == statement.species {
            return .correct
        }
        return species == choice ? .wrong : .dimmed
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

#Preview {
    NavigationStack {
        QuizDestination(kind: .dogOrCat)
    }
}
