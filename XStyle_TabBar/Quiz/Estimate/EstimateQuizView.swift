import SwiftUI

/// Guess a number with a glass slider, lock it in, then see your guess
/// beside the real answer on a scale. Close enough counts.
struct EstimateQuizView: View {
    let namespace: Namespace.ID

    @State private var session = QuizSession(questionCount: QuizKind.estimate.questionCount)
    @State private var guess = 0.0
    @Namespace private var glassNamespace

    private var question: EstimateQuestion {
        QuizBank.estimateQuestions[session.index]
    }

    var body: some View {
        QuizScreen(kind: .estimate, session: session, namespace: namespace) {
            VStack(spacing: QuizMetrics.sectionSpacing) {
                QuizQuestionCard(prompt: question.prompt)
                    .id(question.id)
                    .quizQuestionTransition()

                GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
                    VStack(spacing: QuizMetrics.sectionSpacing) {
                        EstimateGuessPanel(
                            question: question,
                            guess: $guess,
                            isLocked: session.isAnswered,
                            tint: QuizKind.estimate.tint
                        )
                        .glassEffectID("guess", in: glassNamespace)

                        if let outcome = session.outcome {
                            EstimateScale(question: question, guess: guess, tint: QuizKind.estimate.tint)
                                .glassEffectID("scale", in: glassNamespace)

                            QuizFactCard(outcome: outcome, fact: question.fact)
                                .glassEffectID("fact", in: glassNamespace)

                            QuizNextButton(tint: QuizKind.estimate.tint, isLast: session.isLastQuestion, action: next)
                        } else {
                            Button(action: lockIn) {
                                Label("Lock in", systemImage: "lock.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(QuizKind.estimate.tint)
                            .controlSize(.large)
                        }
                    }
                }
            }
            .animation(.smooth, value: session.outcome)
            .animation(.smooth, value: session.index)
            .onChange(of: session.index, initial: true) {
                guess = question.startValue
            }
        }
    }

    private func lockIn() {
        session.submit(isCorrect: question.isClose(guess))
    }

    private func next() {
        session.advance()
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        EstimateQuizView(namespace: namespace)
    }
}
