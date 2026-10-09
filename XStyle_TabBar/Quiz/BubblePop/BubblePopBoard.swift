import Foundation
import Observation

/// One round of Bubble Pop as it plays: the bubbles in their shuffled order,
/// what's been popped, the clock, and how the round ended. It holds no UI,
/// so the rules can be unit tested; the game's score lives in `QuizSession`.
@Observable
final class BubblePopBoard {
    let round: BubblePopRound
    let items: [BubblePopItem]
    /// How fast the bubbles rise, in points per second.
    let speed: Double
    private(set) var phase = BubblePopPhase.countingIn(BubblePopMetrics.countInStart)
    private(set) var startDate: Date?
    /// Whether the round runs against the clock. Settled once, when play
    /// starts, so turning VoiceOver on or off mid-round can't add a clock
    /// to an untimed round or take one away.
    private(set) var isTimed = true
    /// When play stopped, which freezes the bubbles and the clock.
    private(set) var stopDate: Date?
    private(set) var ending: BubblePopEnding?
    private(set) var popped: Set<UUID> = []
    /// Decoys popped by mistake, each counted once.
    private(set) var wrongPops: Set<UUID> = []
    /// Taps on each decoy, so it shakes every time.
    private(set) var decoyTaps: [UUID: Int] = [:]
    /// Taps on any decoy, for the error haptic.
    private(set) var decoyTapCount = 0

    /// - Parameter number: The round's place in the game, from 0. Later
    ///   rounds rise faster.
    init(round: BubblePopRound, number: Int) {
        self.round = round
        speed = BubblePopMetrics.baseSpeed + BubblePopMetrics.speedStep * Double(number)
        let tints = BubblePopMetrics.bubbleTints
        items = round.words.shuffled().enumerated().map { index, word in
            BubblePopItem(
                word: word,
                drift: .random(),
                scale: .random(in: BubblePopMetrics.bubbleScales),
                tint: tints[index % tints.count],
                entranceDelay: Double(index) * BubblePopMetrics.entranceStagger
            )
        }
    }

    var matchCount: Int {
        round.matchCount
    }

    var foundCount: Int {
        popped.count
    }

    var livesLeft: Int {
        max(BubblePopMetrics.lives - wrongPops.count, 0)
    }

    var hasStarted: Bool {
        startDate != nil
    }

    var isPlaying: Bool {
        phase == .playing
    }

    var isOver: Bool {
        phase == .over
    }

    /// The matches left unpopped, in board order.
    var missedWords: [LocalizedStringResource] {
        items.filter { $0.word.isMatch && !popped.contains($0.id) }.map(\.word.text)
    }

    /// The decoys popped by mistake, in board order.
    var wrongWords: [LocalizedStringResource] {
        items.filter { wrongPops.contains($0.id) }.map(\.word.text)
    }

    /// Seconds of play at `date`, held once play stops.
    func elapsed(at date: Date) -> TimeInterval {
        guard let startDate else { return 0 }
        return max((stopDate ?? date).timeIntervalSince(startDate), 0)
    }

    func countIn(to value: Int) {
        guard case .countingIn = phase else { return }
        phase = .countingIn(value)
    }

    func start(at date: Date, isTimed: Bool) {
        guard case .countingIn = phase else { return }
        startDate = date
        self.isTimed = isTimed
        phase = .playing
    }

    /// Pops a match, or counts a decoy as a wrong pop the first time it's
    /// tapped. Stops play once every match is popped or the lives run out.
    func tap(_ item: BubblePopItem, at date: Date) {
        guard phase == .playing else { return }
        if item.word.isMatch {
            popped.insert(item.id)
        } else {
            decoyTaps[item.id, default: 0] += 1
            decoyTapCount += 1
            wrongPops.insert(item.id)
        }

        if foundCount == matchCount {
            stop(wrongPops.isEmpty ? .perfect : .cleared, at: date)
        } else if livesLeft == 0 {
            stop(.outOfPaws, at: date)
        }
    }

    /// Ends play, decided, out of time or with Done. Only the first call counts.
    func stop(_ ending: BubblePopEnding, at date: Date) {
        guard phase == .playing else { return }
        self.ending = ending
        stopDate = date
        phase = .frozen
    }

    /// Settles the frozen board into the verdict.
    func reveal() {
        guard phase == .frozen else { return }
        phase = .over
    }

    func status(of item: BubblePopItem) -> BubblePopBubbleStatus {
        let isPopped = popped.contains(item.id)
        let isWrong = wrongPops.contains(item.id)
        switch phase {
        case .countingIn:
            return .waiting
        case .playing, .frozen:
            if isPopped {
                return .popped
            }
            return isWrong ? .wrong : .floating
        case .over:
            if item.word.isMatch {
                return isPopped ? .found : .missed
            }
            return isWrong ? .wrong : .avoided
        }
    }

    func taps(on item: BubblePopItem) -> Int {
        decoyTaps[item.id] ?? 0
    }
}
