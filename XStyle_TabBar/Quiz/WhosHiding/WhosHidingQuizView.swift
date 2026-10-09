import SwiftUI

/// A reveal game: an animal hides behind frosted glass that clears a stage
/// at a time, thawing one more clue at each. Naming it early earns more
/// paws, so it's a race between nerve and certainty. With VoiceOver on,
/// there's no clock; a button reveals each clue instead.
struct WhosHidingQuizView: View {
    let namespace: Namespace.ID

    @State private var session = QuizSession(kind: .whosHiding)
    @State private var stage = WhosHidingStage.frosted
    @State private var choice: Int?
    @Namespace private var glassNamespace
    @AccessibilityFocusState private var focusedClue: Int?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var round: WhosHidingRound {
        WhosHidingRounds.all[session.index]
    }

    /// The round whose clock runs, or nil when none should: once the round
    /// is answered, which cancels it, and while VoiceOver is on, when the
    /// Reveal clue button clears the glass instead. Turning VoiceOver off
    /// mid-round restarts the clock from the current stage.
    private var clockID: Int? {
        session.isAnswered || voiceOverEnabled ? nil : session.index
    }

    /// What an answer is worth right now, or what the answer earned.
    private var points: Int {
        session.outcome == .wrong ? 0 : stage.points
    }

    /// The worth meter beside the streak, or above it at accessibility text
    /// sizes, where side by side would squeeze the meter's words.
    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    /// Two columns of answers, or one at accessibility text sizes.
    private var choiceColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        QuizScreen(kind: .whosHiding, session: session, namespace: namespace) {
            VStack(spacing: QuizMetrics.sectionSpacing) {
                headerLayout {
                    WhosHidingWorthMeter(
                        points: points,
                        outcome: session.outcome,
                        isPointAtStake: clockID != nil && stage.isPointAtStake,
                        bounceTrigger: session.score
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    StreakBadge(streak: session.streak)
                }

                // The ZStack lets the outgoing and incoming panes overlap as
                // they push past each other, rather than stacking and shoving
                // everything below down by a pane's height mid-transition.
                ZStack {
                    WhosHidingPane(round: round, stage: stage, outcome: session.outcome)
                        .id(round.id)
                        .quizQuestionTransition()
                }

                GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
                    VStack(spacing: 12) {
                        if let outcome = session.outcome {
                            // Takes the first clue's glass, so the clues melt into the fact.
                            QuizFactCard(outcome: outcome, fact: round.fact)
                                .glassEffectID("clue0", in: glassNamespace)
                        } else {
                            ForEach(round.clues.indices, id: \.self) { index in
                                WhosHidingClueRow(
                                    number: index + 1,
                                    clue: round.clues[index],
                                    isRevealed: index < stage.clueCount
                                )
                                .glassEffectID("clue\(index)", in: glassNamespace)
                                .accessibilityFocused($focusedClue, equals: index)
                            }

                            if voiceOverEnabled, stage.clueCount < round.clues.count {
                                Button(action: revealNextClue) {
                                    Label("Reveal clue \(stage.clueCount + 1)", systemImage: "lightbulb.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glass)
                                .controlSize(.large)
                                .glassEffectID("hint", in: glassNamespace)
                                .accessibilityHint(Text("Your answer will be worth one point less."))
                            }
                        }

                        LazyVGrid(columns: choiceColumns, spacing: 12) {
                            ForEach(round.choices.indices, id: \.self) { index in
                                ChoiceButton(title: round.choices[index], state: state(of: index)) {
                                    choose(index)
                                }
                                .glassEffectID(index, in: glassNamespace)
                            }
                        }

                        if session.isAnswered {
                            QuizNextButton(tint: QuizKind.whosHiding.tint, isLast: session.isLastQuestion, action: next)
                        }
                    }
                }
            }
            .animation(.smooth, value: session.outcome)
            .animation(.smooth, value: session.index)
            .animation(.smooth, value: stage)
            // A soft tap each time the glass clears, on top of the answer
            // haptics QuizScreen already plays.
            .sensoryFeedback(trigger: stage) { oldStage, newStage in
                newStage > oldStage ? .impact(weight: .light) : nil
            }
            .task(id: clockID) {
                await runClock()
            }
        }
    }

    private func state(of index: Int) -> ChoiceState {
        guard session.isAnswered else { return .idle }
        if index == round.answerIndex {
            return .correct
        }
        return index == choice ? .wrong : .dimmed
    }

    private func choose(_ index: Int) {
        guard !session.isAnswered else { return }
        choice = index
        session.submit(isCorrect: index == round.answerIndex, points: stage.points)
        announceResult()
    }

    /// Tells VoiceOver how the answer went and who was hiding, since focus
    /// stays on the chosen answer while the fact card replaces the clues.
    private func announceResult() {
        guard voiceOverEnabled, let outcome = session.outcome else { return }
        let verdict = String(localized: outcome.title)
        let reveal = String(localized: round.reveal)
        let message = if outcome == .correct {
            AttributedString(
                localized: "\(verdict) \(reveal) ^[\(points) point](inflect: true) earned.",
                comment: "VoiceOver, after a right answer: the verdict (\"Correct!\"), who was hiding (\"It's a cat!\"), then the points earned."
            )
        } else {
            AttributedString(
                localized: "\(verdict). \(reveal)",
                comment: "VoiceOver, after a wrong answer: the verdict (\"Not quite\"), then who was hiding (\"It's a cat!\")."
            )
        }
        AccessibilityNotification.Announcement(message).post()
    }

    /// VoiceOver's stand-in for the clock: clears the glass one stage and
    /// moves focus to the clue that thaws.
    private func revealNextClue() {
        guard !session.isAnswered, let upcoming = stage.next else { return }
        stage = upcoming
        focusedClue = upcoming.clueCount - 1
    }

    /// Resets the round before moving on, so the next animal (or the first,
    /// after Play again) never shows unfrosted, even for a frame. With
    /// VoiceOver on, focus then lands on the next animal's first clue.
    private func next() {
        guard session.isAnswered else { return }
        choice = nil
        stage = .frosted
        focusedClue = session.isLastQuestion ? nil : 0
        session.advance()
    }

    /// Clears the glass a stage at a time until the animal is in plain view.
    /// Answering, or turning VoiceOver on, changes `clockID`, which cancels this.
    private func runClock() async {
        guard clockID != nil else { return }
        while let upcoming = stage.next {
            try? await Task.sleep(for: stage.duration)
            guard !Task.isCancelled, !session.isAnswered else { return }
            stage = upcoming
        }
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        WhosHidingQuizView(namespace: namespace)
    }
}
