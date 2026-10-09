import SwiftUI

/// Unscramble a breed: tap glass letters from the tray into the answer
/// slots, and tap a placed letter to send it back. A right word fuses into
/// one piece of green glass and waves; a wrong one shakes and stays to be
/// fixed. A solve earns two points, one after the hint, none on giving up.
struct WordWagQuizView: View {
    let namespace: Namespace.ID

    @State private var session = QuizSession(kind: .wordWag)
    /// Replaced by a fresh board for each word, so the word sliding out
    /// keeps its own letters, and its tiles can't move the next word's.
    @State private var board = WordWagBoard(puzzle: WordWagRounds.all[0])
    @AccessibilityFocusState private var isPromptFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var puzzle: WordWagPuzzle {
        WordWagRounds.all[session.index]
    }

    var body: some View {
        QuizScreen(kind: .wordWag, session: session, namespace: namespace) {
            ScrollViewReader { proxy in
                VStack(spacing: QuizMetrics.sectionSpacing) {
                    WordWagPromptCard(puzzle: board.puzzle, points: board.points, solves: board.solves)
                        .accessibilityFocused($isPromptFocused)
                        .id(board.puzzle.id)
                        .quizQuestionTransition()

                    WordWagBoardView(board: board)
                        .id(board.puzzle.id)
                        .quizQuestionTransition()

                    WordWagPanel(board: board, session: session) {
                        next(scrollingWith: proxy)
                    }
                }
                .id(WordWagScrollTarget.top)
                .animation(.smooth, value: session.outcome)
                .animation(.smooth, value: session.index)
                .animation(.smooth, value: board.status)
                .animation(.bouncy, value: board.usedHint)
                .onChange(of: board.status, boardStatusChanged)
                .sensoryFeedback(.selection, trigger: board.moves, condition: isRise)
                .sensoryFeedback(.impact(weight: .light), trigger: board.shuffles, condition: isRise)
                .sensoryFeedback(trigger: board.status, guessFeedback)
                .task(id: session.isAnswered) {
                    await bringNextIntoView(with: proxy)
                }
            }
        }
        // On the screen rather than its content, which is swapped for the
        // results and back, so Play again always deals a fresh first word.
        .onChange(of: session.index, initial: true, loadPuzzle)
        .onChange(of: session.isFinished, loadPuzzle)
    }

    /// Deals the current question's word on a fresh board, unless it's
    /// already on the board in step with the session.
    private func loadPuzzle() {
        guard board.puzzle.id != puzzle.id || board.isSettled != session.isAnswered else { return }
        board = WordWagBoard(puzzle: puzzle)
    }

    /// Scores a settled word, whose outcome then plays its haptic and
    /// brings in the fact, and tells VoiceOver how a full guess went.
    private func boardStatusChanged() {
        switch board.status {
        case .solved:
            session.submit(isCorrect: true, points: board.points)
            announce(String(localized: "Correct! It's \(board.puzzle.spokenName)."))
        case .revealed:
            session.submit(isCorrect: false)
            announce(String(localized: "The breed was \(board.puzzle.spokenName)."))
        case .wrong:
            announce(String(localized: "Not quite! Tap a letter in your guess to send it back."))
        case .playing:
            break
        }
    }

    /// Whether a board counter went up. The counters start again on each
    /// word's board, so only a rise is a move or a shuffle.
    private func isRise(from old: Int, to new: Int) -> Bool {
        new > old
    }

    /// An error buzz for a wrong full guess. A settled word's haptic comes
    /// from the session's outcome instead.
    private func guessFeedback(from old: WordWagStatus, to new: WordWagStatus) -> SensoryFeedback? {
        new == .wrong ? .error : nil
    }

    /// Tells VoiceOver what changed, since focus stays on the tapped tile.
    /// High priority, so focus leaving a control that just vanished, such
    /// as Give up, can't cut it off.
    private func announce(_ message: String) {
        var announcement = AttributedString(message)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func next(scrollingWith proxy: ScrollViewProxy) {
        // Back up to the prompt, where the next word starts.
        withAnimation(reduceMotion ? nil : .smooth) {
            proxy.scrollTo(WordWagScrollTarget.top, anchor: .top)
        }
        session.advance()
        loadPuzzle()
        // Next has gone, so VoiceOver starts the new word at its prompt.
        if voiceOverEnabled, !session.isFinished {
            isPromptFocused = true
        }
    }

    /// Once the fact has morphed in, scrolls down so it and Next are on
    /// screen, which short phones and large text need. VoiceOver users
    /// move through the page themselves, so it stays put for them.
    private func bringNextIntoView(with proxy: ScrollViewProxy) async {
        guard session.isAnswered, !voiceOverEnabled else { return }
        try? await Task.sleep(for: .seconds(WordWagMetrics.nextScrollDelay))
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .smooth) {
            proxy.scrollTo(WordWagScrollTarget.next, anchor: .bottom)
        }
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        WordWagQuizView(namespace: namespace)
    }
}
