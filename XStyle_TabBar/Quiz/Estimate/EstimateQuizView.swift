import SwiftUI

/// Guess a number with a glass slider, lock it in, then see your guess
/// beside the real answer on a scale. Close enough counts.
struct EstimateQuizView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var session = QuizSession(questionCount: QuizKind.estimate.questionCount)
    @State private var guess = 0.0

    private var question: EstimateQuestion {
        QuizBank.estimateQuestions[session.index]
    }

    var body: some View {
        QuizScreen(kind: .estimate, session: session) {
            QuizRound {
                QuizQuestionCard(prompt: question.prompt)
                    .id(question.id)
                    .quizQuestionTransition()
            } answers: {
                EstimateQuizControls(question: question, session: session, guess: $guess, lockIn: lockIn, next: next)
            }
            .animation(reduceMotion ? nil : .smooth, value: session.outcome)
            .animation(reduceMotion ? nil : .smooth, value: session.index)
            .onChange(of: session.index, initial: true) {
                prepareGuess()
            }
        }
    }

    private func lockIn() {
        session.submit(isCorrect: question.isClose(guess))
    }

    private func next() {
        session.advance()
    }

    private func prepareGuess() {
        guess = question.startValue
    }
}

private struct EstimateQuizControls: View {
    let question: EstimateQuestion
    let session: QuizSession
    @Binding var guess: Double
    let lockIn: () -> Void
    let next: () -> Void

    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
            VStack(spacing: QuizMetrics.sectionSpacing) {
                EstimateGuessPanel(question: question, guess: $guess, isLocked: session.isAnswered, tint: QuizKind.estimate.tint)
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
}

#Preview {
    NavigationStack {
        QuizDestination(kind: .estimate)
    }
}
