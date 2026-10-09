import SwiftUI

/// Who Am I?: a mystery pet describes itself in glass speech bubbles, from its
/// hardest clue to its easiest. Each extra clue empties a paw on the points
/// meter, so naming the breed early earns the most. Once answered, the rest
/// of the clues fill in and the pet steps out with a fun fact.
struct MysteryPetQuizView: View {
    let namespace: Namespace.ID

    @State private var session = QuizSession(kind: .mysteryPet)
    /// Clues showing for the current breed, counting the first.
    @State private var cluesUsed = 1
    /// The clue the pet is still "typing", shown as a typing bubble.
    @State private var typingClue: Int?
    @State private var selection: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var breed: MysteryPetBreed {
        MysteryPetRounds.all[session.index]
    }

    private var tint: Color {
        QuizKind.mysteryPet.tint
    }

    /// The breed in play, or nil while the results are showing.
    private var round: Int? {
        session.isFinished ? nil : session.index
    }

    var body: some View {
        QuizScreen(kind: .mysteryPet, session: session, namespace: namespace) {
            ScrollViewReader { proxy in
                VStack(spacing: QuizMetrics.sectionSpacing) {
                    MysteryPetPortrait(
                        species: session.isAnswered ? breed.species : nil,
                        clueCount: cluesUsed,
                        tint: tint
                    )
                    .id(MysteryPetScrollTarget.top)

                    MysteryPetClueBoard(
                        breed: breed,
                        cluesUsed: cluesUsed,
                        typingClue: typingClue,
                        isAnswered: session.isAnswered,
                        tint: tint,
                        askForClue: askForClue
                    )
                    .id(breed.id)
                    .quizQuestionTransition()

                    MysteryPetAnswerPanel(
                        breed: breed,
                        session: session,
                        selection: selection,
                        cluesUsed: cluesUsed,
                        tint: tint,
                        choose: choose,
                        next: { next(scrollingWith: proxy) }
                    )
                }
                .animation(.smooth, value: cluesUsed)
                .animation(.smooth, value: typingClue)
                .animation(.smooth, value: session.outcome)
                .animation(.smooth, value: session.index)
                // A soft tap for every paw spent on a clue.
                .sensoryFeedback(trigger: cluesUsed) { old, new in
                    new > old ? .impact(flexibility: .soft) : nil
                }
                .task(id: typingClue) {
                    await finishTyping()
                }
                .task(id: session.isAnswered) {
                    await bringRevealIntoView(with: proxy)
                }
            }
        }
        // Outside the content, which the results replace, so "Play again"
        // starts the first breed with one clue and nothing picked.
        .onChange(of: round) { _, round in
            roundChanged(to: round)
        }
    }

    /// Brings in the next clue, which costs a paw until the meter is down to one.
    private func askForClue() {
        // Ignores taps while the pet is still typing, so a double tap can't
        // spend two paws at once.
        guard !session.isAnswered, typingClue == nil, cluesUsed < breed.clues.count else { return }
        cluesUsed += 1
        if voiceOverEnabled {
            announce(String(localized: breed.clues[cluesUsed - 1]))
        } else {
            // The pet "types" for a moment, so the clue lands like a message.
            typingClue = cluesUsed - 1
        }
    }

    private func choose(_ index: Int) {
        guard !session.isAnswered else { return }
        selection = index
        typingClue = nil
        session.submit(
            isCorrect: index == breed.answerIndex,
            points: MysteryPetRounds.points(afterClues: cluesUsed)
        )

        if voiceOverEnabled, let outcome = session.outcome {
            let verdict = String(localized: outcome.title)
            let name = String(localized: breed.name)
            announce(String(localized: "\(verdict) It's the \(name)."))
        }
    }

    private func next(scrollingWith proxy: ScrollViewProxy) {
        // Back up to the portrait, where the next mystery pet starts talking.
        withAnimation(reduceMotion ? nil : .smooth) {
            proxy.scrollTo(MysteryPetScrollTarget.top, anchor: .top)
        }
        // Cleared in the same update that brings the next breed, so it
        // arrives with one clue showing. The last breed keeps its clues and
        // pick, so its reveal stays true as it fades into the results; a
        // restart clears them instead.
        if !session.isLastQuestion {
            startRound()
        }
        session.advance()
    }

    /// Catches a new game from "Play again", which restarts the session
    /// without coming through `next`.
    private func roundChanged(to round: Int?) {
        guard round != nil else { return }
        // Already fresh when `next` got here first. Otherwise the content is
        // only just coming back, so the clean slate needs no animation.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, startRound)
    }

    /// One clue showing, nothing typing and nothing picked.
    private func startRound() {
        cluesUsed = 1
        typingClue = nil
        selection = nil
    }

    /// Swaps the typing bubble for the clue after a short pause.
    private func finishTyping() async {
        guard typingClue != nil else { return }
        try? await Task.sleep(for: MysteryPetMetrics.typingDuration)
        guard !Task.isCancelled else { return }
        typingClue = nil
    }

    /// Once the extra clues and the reveal have morphed in, scrolls the
    /// reveal up to the top of the screen, which brings the fact and Next
    /// into view below it when they fit. Anchoring the reveal rather than
    /// Next keeps it on screen at large text sizes. VoiceOver users move
    /// through the page themselves, so it stays put for them.
    private func bringRevealIntoView(with proxy: ScrollViewProxy) async {
        guard session.isAnswered, !voiceOverEnabled else { return }
        try? await Task.sleep(for: MysteryPetMetrics.revealScrollDelay)
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .smooth) {
            proxy.scrollTo(MysteryPetScrollTarget.reveal, anchor: .top)
        }
    }

    /// Speaks a clue or verdict at high priority, so VoiceOver reading the
    /// button it's on, or finding a new element when the clue button goes
    /// after the last clue, doesn't cut it off.
    private func announce(_ text: String) {
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        MysteryPetQuizView(namespace: namespace)
    }
}
