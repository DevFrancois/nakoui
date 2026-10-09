import SwiftUI

/// A personality quiz with no wrong answers: seven playful questions, each
/// with four glass mood tiles. Every pick nudges one or two breeds ahead,
/// glows for a beat, then the next question slides in; a change of mind
/// during the beat just restarts it. The round ends by sniffing out your
/// breed. With VoiceOver on, a Next button replaces the automatic move on.
struct PetMatchQuizView: View {
    let namespace: Namespace.ID

    @State private var session = QuizSession(kind: .petMatch)
    @State private var tally = PetMatchTally()
    @Namespace private var glassNamespace
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var question: PetMatchQuestion {
        PetMatchRounds.all[session.index]
    }

    /// The answer picked for the current question, if any.
    private var pick: PetMatchAnswer? {
        tally.answer(forQuestion: session.index)
    }

    /// The pick the automatic move on waits after, or nil while there's
    /// nothing to wait for. VoiceOver moves on with the Next button instead,
    /// so turning it on mid-beat cancels the beat, and a change of mind
    /// restarts it.
    private var autoAdvancePick: PetMatchAnswer.ID? {
        voiceOverEnabled ? nil : pick?.id
    }

    var body: some View {
        QuizScreen(kind: .petMatch, session: session, namespace: namespace, showsScore: false) {
            VStack(spacing: QuizMetrics.sectionSpacing) {
                PetMatchPromptCard(question: question)
                    .id(question.id)
                    .quizQuestionTransition()

                GlassEffectContainer(spacing: PetMatchMetrics.tileSpacing) {
                    VStack(spacing: QuizMetrics.sectionSpacing) {
                        PetMatchMoodGrid(question: question, pick: pick, namespace: glassNamespace, choose: choose)

                        if voiceOverEnabled, session.isAnswered {
                            QuizNextButton(tint: QuizKind.petMatch.tint, isLast: session.isLastQuestion, action: next)
                        }
                    }
                }

                Label("No wrong answers. Go with your gut!", systemImage: "heart.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .animation(.smooth, value: session.index)
            .animation(.snappy, value: pick?.id)
            // The first pick on a question already gets the session's
            // success tap; this marks a change of mind.
            .sensoryFeedback(.selection, trigger: pick?.id) { oldPick, newPick in
                oldPick != nil && newPick != nil
            }
            .task(id: autoAdvancePick) {
                await moveOnAfterBeat()
            }
        } results: {
            PetMatchResultsView(result: tally.result, takeAgain: takeAgain)
        }
    }

    private func choose(_ answer: PetMatchAnswer) {
        tally.pick(answer, forQuestion: session.index)
        // Every answer is right here; the session only needs to know the
        // question is settled. Later picks just change the tally.
        session.submit(isCorrect: true, points: 0)
    }

    private func next() {
        session.advance()
    }

    /// Clears this round's picks along with the session, so the first
    /// question starts fresh.
    private func takeAgain() {
        tally.reset()
        session.restart()
    }

    /// Leaves the pick glowing for a beat, then moves on. The task is keyed
    /// to `autoAdvancePick`, so a new pick, VoiceOver or leaving the quiz
    /// cancels the wait.
    private func moveOnAfterBeat() async {
        guard autoAdvancePick != nil else { return }
        do {
            try await Task.sleep(for: PetMatchMetrics.pickBeat)
        } catch {
            return
        }
        session.advance()
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        PetMatchQuizView(namespace: namespace)
    }
}
