import SwiftUI

/// True or false against the clock: each claim has a few seconds, a streak
/// builds with every right answer, and the round moves on by itself. With
/// VoiceOver on, there's no clock and a Next button instead.
struct LightningQuizView: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var session = QuizSession(questionCount: QuizKind.lightning.questionCount)
    @State private var choice: Bool?
    @State private var questionStart = Date.now
    /// When the clock stopped, on an answer or a timeout.
    @State private var stoppedAt: Date?

    private var statement: TrueFalseStatement {
        QuizBank.trueFalseStatements[session.index]
    }

    var body: some View {
        QuizScreen(kind: .lightning, session: session) {
            QuizRound {
                LightningQuizPrompt(statement: statement, start: questionStart, stoppedAt: voiceOverEnabled ? questionStart : stoppedAt, streak: session.streak)
            } answers: {
                LightningQuizAnswers(statement: statement, session: session, choice: choice, choose: choose, next: next)
            }
            .animation(reduceMotion ? nil : .smooth, value: session.outcome)
            .animation(reduceMotion ? nil : .smooth, value: session.index)
            .task(id: session.index) {
                await runClock()
            }
            .task(id: session.outcome) {
                await moveOnAfterVerdict()
            }
        }
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

private struct LightningQuizPrompt: View {
    let statement: TrueFalseStatement
    let start: Date
    let stoppedAt: Date?
    let streak: Int

    var body: some View {
        VStack(spacing: QuizMetrics.sectionSpacing) {
            HStack {
                CountdownRing(start: start, duration: QuizMetrics.lightningDuration, stoppedAt: stoppedAt, tint: QuizKind.lightning.tint)
                Spacer()
                StreakBadge(streak: streak)
            }

            QuizQuestionCard(prompt: statement.text)
                .id(statement.id)
                .quizQuestionTransition()
        }
    }
}

private struct LightningQuizAnswers: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let statement: TrueFalseStatement
    let session: QuizSession
    let choice: Bool?
    let choose: (Bool) -> Void
    let next: () -> Void

    @Namespace private var glassNamespace

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
            VStack(spacing: QuizMetrics.sectionSpacing) {
                layout {
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

    private func state(of answer: Bool) -> ChoiceState {
        guard session.isAnswered else { return .idle }
        if answer == statement.isTrue {
            return .correct
        }
        return answer == choice ? .wrong : .dimmed
    }
}

#Preview {
    NavigationStack {
        QuizDestination(kind: .lightning)
    }
}
