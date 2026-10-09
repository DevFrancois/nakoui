import Observation

/// One round of any quiz: which question is showing, the score, and how the
/// current question was settled. It holds no questions itself, so every
/// format shares it, and it has no UI, so it can be unit tested.
@Observable
final class QuizSession {
    let questionCount: Int
    /// The most points a game can earn; more than `questionCount` when a
    /// format awards extra points for speed or for using fewer hints.
    let maxScore: Int
    private(set) var index = 0
    private(set) var score = 0
    private(set) var streak = 0
    private(set) var bestStreak = 0
    /// Nil until the current question is settled.
    private(set) var outcome: QuizOutcome?
    private(set) var isFinished = false

    init(questionCount: Int, maxScore: Int? = nil) {
        self.questionCount = questionCount
        self.maxScore = maxScore ?? questionCount
    }

    convenience init(kind: QuizKind) {
        self.init(questionCount: kind.questionCount, maxScore: kind.maxScore)
    }

    var isAnswered: Bool {
        outcome != nil
    }

    var isLastQuestion: Bool {
        index >= questionCount - 1
    }

    /// Settled questions as a fraction of the round.
    var progress: Double {
        guard questionCount > 0 else { return 0 }
        return Double(index + (isAnswered ? 1 : 0)) / Double(questionCount)
    }

    /// Settles the current question. A right answer earns `points`, one by
    /// default; formats that reward speed or fewer hints pass more.
    func submit(isCorrect: Bool, points: Int = 1) {
        guard outcome == nil, !isFinished else { return }
        if isCorrect {
            score += max(points, 0)
            streak += 1
            bestStreak = max(bestStreak, streak)
            outcome = .correct
        } else {
            streak = 0
            outcome = .wrong
        }
    }

    func timeOut() {
        guard outcome == nil, !isFinished else { return }
        streak = 0
        outcome = .timedOut
    }

    /// Moves to the next question, or finishes after the last one.
    func advance() {
        guard outcome != nil, !isFinished else { return }
        if isLastQuestion {
            isFinished = true
        } else {
            index += 1
            outcome = nil
        }
    }

    func restart() {
        index = 0
        score = 0
        streak = 0
        bestStreak = 0
        outcome = nil
        isFinished = false
    }
}
