import SwiftUI

/// Multiple choice: a question card, four glass answers that settle green or
/// red, then a fun fact that morphs in from the answers.
struct ClassicQuizView: View {
    let namespace: Namespace.ID

    @State private var session = QuizSession(questionCount: QuizKind.classic.questionCount)
    @State private var selection: Int?
    @Namespace private var glassNamespace

    private var question: ChoiceQuestion {
        QuizBank.choiceQuestions[session.index]
    }

    var body: some View {
        QuizScreen(kind: .classic, session: session, namespace: namespace) {
            VStack(spacing: QuizMetrics.sectionSpacing) {
                QuizQuestionCard(prompt: question.prompt)
                    .id(question.id)
                    .quizQuestionTransition()

                GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
                    VStack(spacing: 12) {
                        ForEach(question.choices.indices, id: \.self) { index in
                            ChoiceButton(title: question.choices[index], state: state(of: index)) {
                                choose(index)
                            }
                            .glassEffectID(index, in: glassNamespace)
                        }

                        if let outcome = session.outcome {
                            QuizFactCard(outcome: outcome, fact: question.fact)
                                .glassEffectID("fact", in: glassNamespace)

                            QuizNextButton(tint: QuizKind.classic.tint, isLast: session.isLastQuestion, action: next)
                        }
                    }
                }
            }
            .animation(.smooth, value: session.outcome)
            .animation(.smooth, value: session.index)
        }
    }

    private func state(of index: Int) -> ChoiceState {
        guard session.isAnswered else { return .idle }
        if index == question.answerIndex {
            return .correct
        }
        return index == selection ? .wrong : .dimmed
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

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        ClassicQuizView(namespace: namespace)
    }
}
