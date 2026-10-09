import SwiftUI

/// Put four pets in order: lightest to heaviest, shortest-lived to
/// longest-lived, and so on. Tap pets from the pool into numbered glass
/// slots, with the glass flowing from chip to slot, and tap a slot to send
/// its pet back. Checking reveals each slot in turn, then scores a point
/// for every pet in its right place.
struct LineUpQuizView: View {
    let namespace: Namespace.ID

    @State private var session = QuizSession(kind: .lineUp)
    @State private var board = LineUpBoard(round: LineUpRounds.all[0])
    /// Set by Check until the next round, locking the slots.
    @State private var isChecking = false
    /// How many slots, from the top, show their verdict so far.
    @State private var revealedCount = 0
    @Namespace private var glassNamespace
    @AccessibilityFocusState private var focus: LineUpFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var round: LineUpRound {
        LineUpRounds.all[session.index]
    }

    var body: some View {
        QuizScreen(kind: .lineUp, session: session, namespace: namespace) {
            ScrollViewReader { proxy in
                VStack(spacing: QuizMetrics.sectionSpacing) {
                    LineUpPromptCard(round: round, tint: QuizKind.lineUp.tint)
                        .accessibilityFocused($focus, equals: .prompt)
                        .id(round.id)
                        .quizQuestionTransition()

                    GlassEffectContainer(spacing: LineUpMetrics.glassSpacing) {
                        VStack(spacing: QuizMetrics.sectionSpacing) {
                            LineUpSlotList(
                                round: round,
                                board: board,
                                revealedCount: revealedCount,
                                isLocked: isChecking,
                                tint: QuizKind.lineUp.tint,
                                glassNamespace: glassNamespace,
                                clear: clear(slot:)
                            )

                            if session.isAnswered {
                                LineUpVerdictCard(points: board.points, total: board.slots.count, fact: round.fact)
                                    .glassEffectID("verdict", in: glassNamespace)
                                    .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
                                    .accessibilityFocused($focus, equals: .verdict)

                                QuizNextButton(tint: QuizKind.lineUp.tint, isLast: session.isLastQuestion) {
                                    next(scrollingWith: proxy)
                                }
                                .id(LineUpScrollTarget.next)
                            } else if board.isFull {
                                // Stays while the verdicts are revealed, so its
                                // glass can morph into the verdict card.
                                Button(action: check) {
                                    Label("Check", systemImage: "checkmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glassProminent)
                                .tint(QuizKind.lineUp.tint)
                                .controlSize(.large)
                                .allowsHitTesting(!isChecking)
                                .glassEffectID("verdict", in: glassNamespace)
                                .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
                                .accessibilityFocused($focus, equals: .check)
                            } else {
                                LineUpPool(board: board, glassNamespace: glassNamespace, focus: $focus, place: place)
                            }
                        }
                    }
                }
                .id(LineUpScrollTarget.top)
                .animation(.smooth, value: session.outcome)
                .animation(.smooth, value: session.index)
                .sensoryFeedback(trigger: board.slots) { old, new in
                    moveFeedback(from: old, to: new)
                }
                .sensoryFeedback(trigger: revealedCount) { old, new in
                    revealFeedback(from: old, to: new)
                }
                .task(id: isChecking) {
                    await revealVerdicts(scrollingWith: proxy)
                }
            }
        }
        // Outside the content, which is away while the results show, so
        // they see Play again: it restarts the session but not this view's
        // state, and must deal a fresh first round before the content
        // comes back.
        .onChange(of: session.index) {
            startRound()
        }
        .onChange(of: session.isFinished) { _, isFinished in
            if !isFinished {
                startRound()
            }
        }
    }

    /// A springy hop between pool and slot, or a plain fade with Reduce
    /// Motion on.
    private var moveAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0.3)
    }

    private var revealAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .bouncy
    }

    private func place(_ pet: LineUpPet) {
        guard !isChecking, !session.isAnswered else { return }
        withAnimation(moveAnimation) {
            board.place(pet)
        }
        // The chip just placed is gone, so VoiceOver moves on to the next
        // pet still in the pool, or to Check.
        guard voiceOverEnabled else { return }
        if board.isFull {
            focus = .check
        } else if let pet = board.pool.first(where: { !board.isPlaced($0) }) {
            focus = .pet(pet.id)
        }
    }

    private func clear(slot: Int) {
        guard !isChecking, !session.isAnswered, let pet = board.pet(inSlot: slot) else { return }
        withAnimation(moveAnimation) {
            board.clear(slot: slot)
        }
        if voiceOverEnabled {
            focus = .pet(pet.id)
        }
    }

    private func check() {
        guard board.isFull, !isChecking, !session.isAnswered else { return }
        isChecking = true
    }

    private func next(scrollingWith proxy: ScrollViewProxy) {
        // A second tap on the outgoing button must not run this again.
        guard session.isAnswered else { return }
        session.advance()
        // After the last round the results take over, and this content
        // leaves as it is; Play again deals afresh.
        guard !session.isFinished else { return }

        startRound()
        withAnimation(reduceMotion ? nil : .smooth) {
            proxy.scrollTo(LineUpScrollTarget.top, anchor: .top)
        }
        if voiceOverEnabled {
            focus = .prompt
        }
    }

    /// Clears the reveal and deals the current round, unless a fresh board
    /// for it is already out.
    private func startRound() {
        isChecking = false
        revealedCount = 0
        guard board.roundID != round.id || !board.isEmpty else { return }
        board = LineUpBoard(round: round)
    }

    /// Reveals each slot's verdict from the top, a beat apart, then scores
    /// the line-up and brings the verdict and Next into view. If the view
    /// goes away mid-reveal, it picks up where it stopped. With VoiceOver,
    /// everything is revealed at once and focus moves to the verdict.
    private func revealVerdicts(scrollingWith proxy: ScrollViewProxy) async {
        guard isChecking, board.isFull, board.roundID == round.id, !session.isAnswered else { return }

        do {
            if voiceOverEnabled {
                revealedCount = board.slots.count
            } else {
                for slot in revealedCount..<board.slots.count {
                    try await Task.sleep(for: LineUpMetrics.revealInterval)
                    withAnimation(revealAnimation) {
                        revealedCount = slot + 1
                    }
                }
                try await Task.sleep(for: LineUpMetrics.verdictDelay)
            }

            let points = board.points
            session.submit(isCorrect: points > 0, points: points)
            try await Task.sleep(for: LineUpMetrics.settlePause)
        } catch {
            return
        }

        if voiceOverEnabled {
            focus = .verdict
        } else {
            // On shorter phones and at large text sizes, Next can land
            // below the fold.
            withAnimation(reduceMotion ? nil : .smooth) {
                proxy.scrollTo(LineUpScrollTarget.next, anchor: .bottom)
            }
        }
    }

    /// A tap as a pet lands in a slot, a lighter tick as it goes back. A new
    /// round clears every slot at once, which stays silent.
    private func moveFeedback(from old: [LineUpPet.ID?], to new: [LineUpPet.ID?]) -> SensoryFeedback? {
        let change = new.count(where: { $0 != nil }) - old.count(where: { $0 != nil })
        return switch change {
        case 1: .impact(weight: .light)
        case -1: .selection
        default: nil
        }
    }

    /// A firm tap for each pet revealed in its right place, a soft one for
    /// each that isn't.
    private func revealFeedback(from old: Int, to new: Int) -> SensoryFeedback? {
        guard new > old, let mark = board.mark(forSlot: new - 1) else { return nil }
        return mark == .correct ? .impact(weight: .medium) : .impact(flexibility: .soft, intensity: 0.6)
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        LineUpQuizView(namespace: namespace)
    }
}
