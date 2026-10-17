import SwiftUI

/// Multiple choice: a question card, four glass answers that settle green or
/// red, then a fun fact that morphs in from the answers.
struct ClassicQuizView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var session = QuizSession(questionCount: QuizKind.classic.questionCount)
    @State private var selection: Int?

    private var question: ChoiceQuestion {
        QuizBank.choiceQuestions[session.index]
    }

    var body: some View {
        QuizScreen(kind: .classic, session: session) {
            QuizRound {
                QuizQuestionCard(prompt: question.prompt)
                    .id(question.id)
                    .quizQuestionTransition()
            } answers: {
                ClassicQuizAnswers(question: question, session: session, selection: selection, choose: choose, next: next)
            }
            .animation(reduceMotion ? nil : .smooth, value: session.outcome)
            .animation(reduceMotion ? nil : .smooth, value: session.index)
        }
    }

    private func choose(_ index: Int) {
        guard !session.isAnswered else { return }
        selection = index
        session.submit(isCorrect: index == question.answerIndex)
    }

    private func next() {
        selection = nil
        session.advance()
    }
}

private struct ClassicQuizAnswers: View {
    let question: ChoiceQuestion
    let session: QuizSession
    let selection: Int?
    let choose: (Int) -> Void
    let next: () -> Void

    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
            VStack(spacing: 12) {
                ForEach(question.choices.enumerated(), id: \.element.id) { index, choice in
                    ChoiceButton(title: choice.title, state: state(of: index)) {
                        choose(index)
                    }
                    .glassEffectID(choice.id, in: glassNamespace)
                }

                if let outcome = session.outcome {
                    QuizFactCard(outcome: outcome, fact: question.fact)
                        .glassEffectID("fact", in: glassNamespace)

                    QuizNextButton(tint: QuizKind.classic.tint, isLast: session.isLastQuestion, action: next)
                }
            }
        }
    }

    private func state(of index: Int) -> ChoiceState {
        guard session.isAnswered else { return .idle }
        if index == question.answerIndex {
            return .correct
        }
        return index == selection ? .wrong : .dimmed
    }
}

#Preview {
    NavigationStack {
        QuizDestination(kind: .classic)
    }
}
