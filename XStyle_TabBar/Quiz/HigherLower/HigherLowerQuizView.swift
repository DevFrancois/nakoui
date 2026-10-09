import SwiftUI

/// Higher or lower, card style: a known pet's value is on show, and the
/// player calls whether the challenger's is higher or lower. The hidden value
/// then counts up from zero along a meter, with a bump the moment it passes
/// the known one, before the verdict lands. With Reduce Motion the value
/// fades in instead, and with VoiceOver it's revealed and announced at once.
struct HigherLowerQuizView: View {
    let namespace: Namespace.ID

    @State private var session = QuizSession(kind: .higherLower)
    /// The player's call on the current round; nil until it's made.
    @State private var guess: HigherLowerGuess?
    /// The challenger's value as it counts up; nil while it's still hidden.
    @State private var shownValue: Double?
    /// Brings VoiceOver to the new round's stat after Next, whose button is gone.
    @AccessibilityFocusState private var isStatFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var round: HigherLowerRound {
        HigherLowerRounds.all[session.index]
    }

    /// Whether the counting value has passed the known pet's.
    private var hasOvertaken: Bool {
        (shownValue ?? 0) > round.known.value
    }

    /// The stat and streak sit side by side, and stack at accessibility sizes.
    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading))
            : AnyLayout(HStackLayout())
    }

    var body: some View {
        QuizScreen(kind: .higherLower, session: session, namespace: namespace) {
            ScrollViewReader { proxy in
                VStack(spacing: QuizMetrics.sectionSpacing) {
                    GlassEffectContainer {
                        headerLayout {
                            HigherLowerStatChip(stat: round.stat)
                                .accessibilityFocused($isStatFocused)

                            Spacer(minLength: 0)

                            StreakBadge(streak: session.streak)
                        }
                    }
                    .id(HigherLowerScrollTarget.top)

                    HigherLowerMatchup(round: round, shownValue: shownValue, outcome: session.outcome)
                        .id(round.id)
                        .quizQuestionTransition()

                    HigherLowerAnswerPanel(
                        round: round,
                        guess: guess,
                        outcome: session.outcome,
                        isLast: session.isLastQuestion,
                        call: call,
                        next: { next(scrollingWith: proxy) }
                    )
                }
                .animation(.smooth, value: session.outcome)
                .animation(.smooth, value: session.index)
                .animation(.smooth, value: guess)
                .symbolEffectsRemoved(reduceMotion)
                .sensoryFeedback(.selection, trigger: guess) { _, newGuess in
                    newGuess != nil
                }
                // A bump as the count passes the known value, before the verdict.
                // Reduce Motion skips the count, so there's no moment to mark.
                .sensoryFeedback(.impact(weight: .medium), trigger: hasOvertaken) { wasAhead, isAhead in
                    isAhead && !wasAhead && !session.isAnswered && !reduceMotion
                }
                .task(id: guess) {
                    await reveal()
                }
                .task(id: session.isAnswered) {
                    await bringVerdictIntoView(with: proxy)
                }
            }
        }
        // Play again restarts the session but not this view's state.
        .onChange(of: session.isFinished) { _, isFinished in
            if !isFinished {
                resetRound()
            }
        }
    }

    private func call(_ option: HigherLowerGuess) {
        guard guess == nil, !session.isAnswered, !session.isFinished else { return }
        guess = option
    }

    private func next(scrollingWith proxy: ScrollViewProxy) {
        // A second tap on the outgoing button must not clear the next round's call.
        guard session.isAnswered else { return }
        withAnimation(reduceMotion ? nil : .smooth) {
            proxy.scrollTo(HigherLowerScrollTarget.top, anchor: .top)
        }
        resetRound()
        session.advance()

        if voiceOverEnabled, !session.isFinished {
            isStatFocused = true
        }
    }

    /// Clears the call and hides the value, in the same update that changes
    /// the round, so the new pair never shows the last one's number.
    private func resetRound() {
        guess = nil
        shownValue = nil
    }

    /// Reveals the challenger's value for the call just made, then settles
    /// the round, so the verdict and its haptic land with the final number.
    /// If the view goes away mid-count, the next appearance counts again.
    private func reveal() async {
        guard let guess, !session.isAnswered else { return }
        let round = round
        let isCorrect = guess == round.answer

        if voiceOverEnabled {
            shownValue = round.challenger.value
            session.submit(isCorrect: isCorrect)
            announceVerdict(for: round)
            return
        }

        await countUp(to: round.challenger.value)
        try? await Task.sleep(for: HigherLowerMetrics.verdictPause)
        guard !Task.isCancelled else { return }
        session.submit(isCorrect: isCorrect)
    }

    /// Rolls the value up from zero, easing in and out so it lingers both
    /// around the known value and on the way into the answer. With Reduce
    /// Motion, it simply fades in.
    private func countUp(to target: Double) async {
        if reduceMotion {
            withAnimation(.easeInOut) {
                shownValue = target
            }
            return
        }

        let steps = HigherLowerMetrics.countSteps
        for step in 1...steps {
            guard !Task.isCancelled else { return }
            let progress = Double(step) / Double(steps)
            let eased = progress * progress * (3 - 2 * progress)
            withAnimation(.snappy(duration: 0.2)) {
                shownValue = step == steps ? target : (target * eased).rounded()
            }
            try? await Task.sleep(for: HigherLowerMetrics.countStepDuration)
        }
    }

    /// Once the fact has morphed in, scrolls down so it and Next are on
    /// screen on shorter phones and at large text sizes. VoiceOver users move
    /// through the page themselves, so it stays put for them.
    private func bringVerdictIntoView(with proxy: ScrollViewProxy) async {
        guard session.isAnswered, !voiceOverEnabled else { return }
        try? await Task.sleep(for: HigherLowerMetrics.revealScrollDelay)
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .smooth) {
            proxy.scrollTo(HigherLowerScrollTarget.next, anchor: .bottom)
        }
    }

    /// Speaks the revealed value and the verdict, since VoiceOver stays on
    /// the tile that was activated rather than reading the card that changed.
    private func announceVerdict(for round: HigherLowerRound) {
        guard let outcome = session.outcome else { return }
        let name = String(localized: round.challenger.name)
        let value = round.stat.spokenValue(round.challenger.value)
        let verdict = String(localized: outcome.title)
        let announcement = String(
            localized: "\(name): \(value). \(verdict)",
            comment: "VoiceOver announcement after a Higher or Lower call: the challenger's name, its revealed value with its unit, then the verdict, such as Correct!"
        )
        AccessibilityNotification.Announcement(announcement).post()
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        HigherLowerQuizView(namespace: namespace)
    }
}
