import SwiftUI

/// One round of Bubble Pop: the rule, then a count-in, then glass bubbles
/// rising against the clock. Popping every match clears the round; a second
/// wrong pop or the clock ends it. The board holds still for a beat, then
/// settles into a grid showing every word's fate, with the verdict below.
/// With Reduce Motion, VoiceOver or accessibility text sizes, the bubbles
/// hold still in a grid and Done ends the round; VoiceOver also plays
/// without a clock or count-in.
struct BubblePopRoundView: View {
    let round: BubblePopRound
    /// The round's place in the game, from 0.
    let number: Int
    let session: QuizSession

    @State private var board: BubblePopBoard
    @AccessibilityFocusState private var focusedAnchor: BubblePopAnchor?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(round: BubblePopRound, number: Int, session: QuizSession) {
        self.round = round
        self.number = number
        self.session = session
        _board = State(initialValue: BubblePopBoard(round: round, number: number))
    }

    private var tint: Color {
        QuizKind.bubblePop.tint
    }

    /// Whether the bubbles hold still in a grid rather than float.
    private var isStatic: Bool {
        reduceMotion || voiceOverEnabled || dynamicTypeSize.isAccessibilitySize
    }

    /// Whether the clock shows: once play starts, whether the round is
    /// timed; before that, whether it will be.
    private var showsClock: Bool {
        board.hasStarted ? board.isTimed : !voiceOverEnabled
    }

    /// Whether Done is offered while the round plays: whenever the bubbles
    /// hold still, and in an untimed round, which no clock will end.
    private var offersDone: Bool {
        board.isPlaying && (isStatic || !board.isTimed)
    }

    /// Whether this is still the round in play, rather than one sliding out
    /// after Next.
    private var isCurrent: Bool {
        session.index == number && !session.isFinished
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: QuizMetrics.sectionSpacing) {
                BubblePopRuleBanner(round: round, tint: tint)
                    .id(BubblePopAnchor.rule)
                    .accessibilityFocused($focusedAnchor, equals: .rule)

                if !board.isOver {
                    BubblePopHUD(board: board, showsClock: showsClock, tint: tint)
                        .transition(.opacity)
                }

                BubblePopPlayArea(board: board, isStatic: isStatic, tint: tint, pop: pop)

                if offersDone {
                    Button(action: finishEarly) {
                        Label("Done", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }

                if let ending = board.ending, board.isOver {
                    BubblePopVerdictCard(
                        ending: ending,
                        missed: board.missedWords,
                        wrong: board.wrongWords,
                        fact: round.fact
                    )
                    .id(BubblePopAnchor.verdict)
                    .accessibilityFocused($focusedAnchor, equals: .verdict)

                    QuizNextButton(tint: tint, isLast: session.isLastQuestion) {
                        next(scrollingWith: proxy)
                    }
                    .id(BubblePopAnchor.next)
                }
            }
            .task {
                await play()
            }
            .task(id: board.phase) {
                await phaseChanged(scrollingWith: proxy)
            }
        }
        .sensoryFeedback(.success, trigger: board.foundCount)
        .sensoryFeedback(.error, trigger: board.decoyTapCount)
        .sensoryFeedback(trigger: board.phase, countInBeat)
    }

    /// Counts in, starts play, and calls time unless the round ends sooner.
    /// VoiceOver starts at once, on the rule, and plays without a clock.
    private func play() async {
        if !board.hasStarted {
            if voiceOverEnabled {
                focusedAnchor = .rule
            } else {
                await countIn()
                guard !Task.isCancelled else { return }
            }

            withAnimation(.smooth) {
                board.start(at: .now, isTimed: !voiceOverEnabled)
            }
        }

        guard board.isTimed else { return }
        let remaining = BubblePopMetrics.roundDuration - board.elapsed(at: .now)
        try? await Task.sleep(for: .seconds(max(remaining, 0)))
        guard !Task.isCancelled else { return }
        withAnimation(.smooth) {
            board.stop(.timeUp, at: .now)
        }
    }

    /// 3, 2, 1, Pop!
    private func countIn() async {
        for value in stride(from: BubblePopMetrics.countInStart - 1, through: 0, by: -1) {
            try? await Task.sleep(for: BubblePopMetrics.countInStep)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                board.countIn(to: value)
            }
        }
        try? await Task.sleep(for: BubblePopMetrics.popCueDuration)
    }

    private func pop(_ item: BubblePopItem) {
        guard board.isPlaying else { return }
        withAnimation(isStatic ? .smooth(duration: 0.25) : .snappy(duration: 0.3)) {
            board.tap(item, at: .now)
        }

        if voiceOverEnabled {
            announceTap(on: item)
        }
    }

    /// Tells VoiceOver how a pop went, since the bubble stays where it is
    /// and the count and lives are elsewhere on the screen.
    private func announceTap(on item: BubblePopItem) {
        let message = if item.word.isMatch {
            AttributedString(localized: "Popped! \(board.foundCount) of \(board.matchCount).")
        } else {
            AttributedString(localized: "Not a match. ^[\(board.livesLeft) paw](inflect: true) left.")
        }
        AccessibilityNotification.Announcement(message).post()
    }

    private func finishEarly() {
        withAnimation(.smooth) {
            board.stop(.incomplete, at: .now)
        }
    }

    /// Settles a decided round after a beat, then brings its verdict to the
    /// player.
    private func phaseChanged(scrollingWith proxy: ScrollViewProxy) async {
        switch board.phase {
        case .frozen:
            await revealAfterFreeze()
        case .over:
            await presentVerdict(scrollingWith: proxy)
        case .countingIn, .playing:
            break
        }
    }

    /// Holds the board still for a beat once the round is decided, then
    /// settles it into the verdict and scores it.
    private func revealAfterFreeze() async {
        guard let ending = board.ending else { return }
        try? await Task.sleep(for: BubblePopMetrics.freezeDuration)
        guard !Task.isCancelled else { return }

        withAnimation(isStatic ? .smooth : .bouncy(duration: 0.6)) {
            board.reveal()
        }
        score(ending)
    }

    /// Once the verdict has landed, takes VoiceOver to it, since Done or the
    /// bubble that ended the round leads nowhere now. Otherwise scrolls Next
    /// into view, which can sit below the fold on smaller phones; at
    /// accessibility text sizes it keeps the verdict's start in view instead.
    private func presentVerdict(scrollingWith proxy: ScrollViewProxy) async {
        try? await Task.sleep(for: BubblePopMetrics.verdictSettleDelay)
        guard !Task.isCancelled, isCurrent else { return }

        if voiceOverEnabled {
            focusedAnchor = .verdict
        } else {
            withAnimation(reduceMotion ? nil : .smooth) {
                if dynamicTypeSize.isAccessibilitySize {
                    proxy.scrollTo(BubblePopAnchor.verdict, anchor: .top)
                } else {
                    proxy.scrollTo(BubblePopAnchor.next, anchor: .bottom)
                }
            }
        }
    }

    private func score(_ ending: BubblePopEnding) {
        if ending == .timeUp {
            session.timeOut()
        } else {
            session.submit(isCorrect: ending.isCleared)
        }
    }

    /// Moves on, back up at the top, where the next round's rule appears.
    private func next(scrollingWith proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .smooth) {
            proxy.scrollTo(BubblePopAnchor.rule, anchor: .top)
        }
        session.advance()
    }

    /// A light tap on each beat of the count-in, and a firmer one on "Pop!".
    private func countInBeat(from oldPhase: BubblePopPhase, to newPhase: BubblePopPhase) -> SensoryFeedback? {
        switch newPhase {
        case .countingIn(0): .impact(weight: .medium)
        case .countingIn: .impact(weight: .light)
        default: nil
        }
    }
}
