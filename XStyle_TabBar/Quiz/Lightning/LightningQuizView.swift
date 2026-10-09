import SwiftUI

/// True or false against the clock: each claim has a few seconds, a streak
/// builds with every right answer, and the round moves on by itself. With
/// VoiceOver on, there's no clock and a Next button instead.
struct LightningQuizView: View {
    let namespace: Namespace.ID

    @State private var session = QuizSession(questionCount: QuizKind.lightning.questionCount)
    @State private var choice: Bool?
    @State private var questionStart = Date.now
    /// When the clock stopped, on an answer or a timeout.
    @State private var stoppedAt: Date?
    @Namespace private var glassNamespace
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var statement: TrueFalseStatement {
        QuizBank.trueFalseStatements[session.index]
    }

    var body: some View {
        QuizScreen(kind: .lightning, session: session, namespace: namespace) {
            VStack(spacing: QuizMetrics.sectionSpacing) {
                HStack {
                    CountdownRing(
                        start: questionStart,
                        duration: QuizMetrics.lightningDuration,
                        stoppedAt: voiceOverEnabled ? questionStart : stoppedAt,
                        tint: QuizKind.lightning.tint
                    )

                    Spacer()

                    StreakBadge(streak: session.streak)
                }

                QuizQuestionCard(prompt: statement.text)
                    .id(statement.id)
                    .quizQuestionTransition()

                GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
                    VStack(spacing: QuizMetrics.sectionSpacing) {
                        HStack(spacing: 12) {
                            AnswerTile(title: "True", systemImage: "checkmark", tint: .green, state: state(of: true)) {
                                choose(true)
                            }
                            .glassEffectID("true", in: glassNamespace)

                            AnswerTile(title: "False", systemImage: "xmark", tint: .red, state: state(of: false)) {
                                choose(false)
                            }
                            .glassEffectID("false", in: glassNamespace)
                        }

                        if let outcome = session.outcome {
                            QuizFactCard(outcome: outcome, fact: statement.fact)
                                .glassEffectID("fact", in: glassNamespace)

                            if voiceOverEnabled {
                                QuizNextButton(tint: QuizKind.lightning.tint, isLast: session.isLastQuestion, action: next)
                            }
                        }
                    }
                }
            }
            .animation(.smooth, value: session.outcome)
            .animation(.smooth, value: session.index)
            .task(id: session.index) {
                await runClock()
            }
            .task(id: session.outcome) {
                await moveOnAfterVerdict()
            }
        }
    }

    private func state(of answer: Bool) -> ChoiceState {
        guard session.isAnswered else { return .idle }
        if answer == statement.isTrue {
            return .correct
        }
        return answer == choice ? .wrong : .dimmed
    }

    private func choose(_ answer: Bool) {
        guard !session.isAnswered else { return }
        stoppedAt = .now
        choice = answer
        session.submit(isCorrect: answer == statement.isTrue)
    }

    private func next() {
        session.advance()
    }

    /// Starts the clock for the current question and times it out if it runs down.
    private func runClock() async {
        choice = nil
        stoppedAt = nil
        questionStart = .now
        guard !voiceOverEnabled else { return }

        try? await Task.sleep(for: .seconds(QuizMetrics.lightningDuration))
        guard !Task.isCancelled, !session.isAnswered else { return }
        stoppedAt = .now
        session.timeOut()
    }

    /// Leaves the verdict up briefly, then moves on.
    private func moveOnAfterVerdict() async {
        guard session.isAnswered, !voiceOverEnabled else { return }
        try? await Task.sleep(for: .seconds(QuizMetrics.verdictDuration))
        guard !Task.isCancelled else { return }
        session.advance()
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        LightningQuizView(namespace: namespace)
    }
}
