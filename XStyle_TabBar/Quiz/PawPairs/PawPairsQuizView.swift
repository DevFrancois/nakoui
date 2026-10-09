import SwiftUI

/// Memory with a twist: each board hides six pairs that belong together,
/// such as a breed and its homeland. Turn two glass cards a move: a pair
/// locks in green, a miss shakes and turns back. Clear a board within par for
/// a point, then watch the cards line up beside their matches.
struct PawPairsQuizView: View {
    let namespace: Namespace.ID

    @State private var session = QuizSession(kind: .pawPairs)
    @State private var game = PawPairsGame(board: PawPairsRounds.all[0])
    /// How many of the board's cards are on the table while it's dealt.
    @State private var dealtCount = 0
    @AccessibilityFocusState private var isHeaderFocused: Bool
    @AccessibilityFocusState private var isVerdictFocused: Bool
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var board: PawPairsBoard {
        PawPairsRounds.all[session.index]
    }

    /// The board being played, or nil while the results are showing. It
    /// changes for Next and for "Play again", which resets the session but
    /// not this view's own state.
    private var boardInPlay: Int? {
        session.isFinished ? nil : session.index
    }

    private var verdict: PawPairsVerdict {
        PawPairsVerdict(moves: game.moves, par: board.par, pairCount: game.pairCount)
    }

    var body: some View {
        QuizScreen(kind: .pawPairs, session: session, namespace: namespace) {
            ScrollViewReader { proxy in
                VStack(spacing: QuizMetrics.sectionSpacing) {
                    PawPairsBoardHeader(board: board)
                        .accessibilityFocused($isHeaderFocused)
                        .id(session.index)
                        .quizQuestionTransition()
                        // A steady target around the header, whose own ID
                        // changes per board to slide the next one in.
                        .id(PawPairsScrollTarget.top)

                    PawPairsScoreboard(
                        moves: game.moves,
                        par: board.par,
                        found: game.matchedPairs.count,
                        total: game.pairCount
                    )

                    PawPairsTable(
                        game: game,
                        dealtCount: dealtCount,
                        isReviewing: session.isAnswered,
                        flip: flip
                    )

                    if session.isAnswered {
                        GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
                            VStack(spacing: QuizMetrics.sectionSpacing) {
                                PawPairsVerdictCard(verdict: verdict, fact: board.fact)
                                    .glassEffectID("verdict", in: glassNamespace)
                                    .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
                                    .accessibilityFocused($isVerdictFocused)
                                    .id(PawPairsScrollTarget.verdict)

                                QuizNextButton(tint: QuizKind.pawPairs.tint, isLast: session.isLastQuestion) {
                                    next(scrollingWith: proxy)
                                }
                                .id(PawPairsScrollTarget.next)
                            }
                        }
                    }
                }
                .animation(reduceMotion ? .easeInOut : PawPairsMetrics.reviewAnimation, value: session.outcome)
                .animation(.smooth, value: session.index)
                .sensoryFeedback(trigger: game.flipCount) { _, _ in
                    game.lastFlip?.feedback
                }
                .task(id: game.dealCount) {
                    await dealCards()
                }
                .task(id: game.isShowingMiss) {
                    await turnBackMiss()
                }
                .task(id: game.isCleared) {
                    await finishBoard(scrollingWith: proxy)
                }
            }
        }
        // Outside the content, which the results replace, so "Play again"
        // deals a fresh board before the content comes back.
        .onChange(of: boardInPlay) { _, boardIndex in
            if boardIndex != nil {
                startBoard()
            }
        }
    }

    private func flip(_ card: PawPairsCard) {
        guard let result = game.flip(card), voiceOverEnabled else { return }
        announce(result, for: card)
    }

    private func next(scrollingWith proxy: ScrollViewProxy) {
        // Back up to the header, so the next board's theme is the first
        // thing seen, even on a small phone that scrolled down to Next.
        withAnimation(reduceMotion ? nil : .smooth) {
            proxy.scrollTo(PawPairsScrollTarget.top, anchor: .top)
        }
        session.advance()
    }

    /// Clears the table and shuffles the current board, ready to deal.
    private func startBoard() {
        // Cleared so setting them again after the deal is a real change.
        isHeaderFocused = false
        isVerdictFocused = false
        withAnimation(.smooth) {
            dealtCount = 0
            game.deal(board)
        }
    }

    /// Deals the cards one by one, or all at once with Reduce Motion or
    /// VoiceOver. VoiceOver then starts each later board on its header, as
    /// the Next or Play again button that had focus is gone.
    private func dealCards() async {
        let total = game.cards.count
        guard dealtCount < total else { return }

        if reduceMotion || voiceOverEnabled {
            withAnimation(.easeIn) {
                dealtCount = total
            }
            if voiceOverEnabled, game.dealCount > 1 {
                isHeaderFocused = true
            }
            return
        }

        for count in (dealtCount + 1)...total {
            do {
                try await Task.sleep(for: count == 1 ? PawPairsMetrics.dealDelay : PawPairsMetrics.dealInterval)
            } catch {
                return
            }
            withAnimation(PawPairsMetrics.dealAnimation) {
                dealtCount = count
            }
        }
    }

    /// Leaves a mismatched pair up for a moment, then turns it back.
    private func turnBackMiss() async {
        guard game.isShowingMiss else { return }
        do {
            try await Task.sleep(for: PawPairsMetrics.missDelay)
        } catch {
            return
        }
        game.turnBack()
    }

    /// Once the last pair has landed, settles the board, which lines the
    /// cards up in pairs and brings in the verdict, then shows it: VoiceOver
    /// moves to the verdict, and everyone else scrolls to it.
    private func finishBoard(scrollingWith proxy: ScrollViewProxy) async {
        guard game.isCleared, !session.isAnswered else { return }
        do {
            try await Task.sleep(for: PawPairsMetrics.clearPause)
        } catch {
            return
        }
        // Still the same board, cleared and unscored, after the pause.
        guard game.isCleared, !session.isAnswered else { return }
        session.submit(isCorrect: verdict.isWithinPar)

        // Gives the verdict a moment to be laid out before going to it.
        do {
            try await Task.sleep(for: PawPairsMetrics.scrollPause)
        } catch {
            return
        }

        if voiceOverEnabled {
            isVerdictFocused = true
            return
        }

        withAnimation(reduceMotion ? nil : .smooth) {
            // Next at the bottom keeps as much of the lined-up board in view
            // as fits. At accessibility sizes the verdict alone can outgrow
            // the screen, so its top comes first instead.
            if dynamicTypeSize.isAccessibilitySize {
                proxy.scrollTo(PawPairsScrollTarget.verdict, anchor: .top)
            } else {
                proxy.scrollTo(PawPairsScrollTarget.next, anchor: .bottom)
            }
        }
    }

    /// Tells VoiceOver what a flip revealed and whether it made a pair.
    private func announce(_ result: PawPairsFlip, for card: PawPairsCard) {
        let text = String(localized: card.face.text)
        let message = switch result {
        case .turned:
            text
        case .matched:
            String(localized: "Match! \(partnerText(of: card)) and \(text). \(game.matchedPairs.count) of \(game.pairCount) pairs found.")
        case .missed:
            String(localized: "\(text). Not a match.")
        }

        // High priority, so VoiceOver reading the card's new label, or moving
        // to the verdict after the last pair, doesn't cut the result off.
        var announcement = AttributedString(message)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func partnerText(of card: PawPairsCard) -> String {
        guard let partner = game.partner(of: card) else { return "" }
        return String(localized: partner.face.text)
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        PawPairsQuizView(namespace: namespace)
    }
}
