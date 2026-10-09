import Observation

/// The answers picked in one round of Which Dog Are You?, and the breeds
/// they add up to. Like `QuizSession`, it has no UI, so it can be unit tested.
@Observable
final class PetMatchTally {
    /// The answer picked for each question, keyed by the question's position.
    private(set) var picks: [Int: PetMatchAnswer] = [:]

    func answer(forQuestion index: Int) -> PetMatchAnswer? {
        picks[index]
    }

    /// Records a pick, replacing any earlier one for the same question.
    func pick(_ answer: PetMatchAnswer, forQuestion index: Int) {
        picks[index] = answer
    }

    func reset() {
        picks.removeAll()
    }

    func points(for breed: PetMatchBreed) -> Int {
        picks.values.reduce(0) { total, answer in
            total + answer.points(for: breed)
        }
    }

    /// Every breed, best match first. Ties go to the breed more picks suited
    /// best, then to the one picked first-choice most recently, then to the
    /// order the breeds are listed in, so the same answers always give the
    /// same match.
    var ranking: [PetMatchBreed] {
        PetMatchBreed.allCases.sorted { lhs, rhs in
            let lhsKey = rankKey(for: lhs)
            let rhsKey = rankKey(for: rhs)
            return lhsKey == rhsKey ? lhs < rhs : lhsKey > rhsKey
        }
    }

    /// The match, runner-up and breed mix for the picks so far, ranked once.
    var result: PetMatchResult {
        let ranking = ranking
        return PetMatchResult(match: ranking[0], runnerUp: ranking[1], mix: mix(of: ranking))
    }

    /// Each ranked breed with any points, as whole percents of all the points
    /// given. Rounded by largest remainder so they add up to exactly 100.
    private func mix(of ranking: [PetMatchBreed]) -> [PetMatchMixShare] {
        let scored = ranking.map { (breed: $0, points: points(for: $0)) }.filter { $0.points > 0 }
        let total = scored.reduce(0) { $0 + $1.points }
        guard total > 0 else { return [] }

        let exact = scored.map { Double($0.points) * 100 / Double(total) }
        var percents = exact.map { Int($0.rounded(.down)) }
        let remainders = exact.indices.map { exact[$0] - Double(percents[$0]) }
        let leftover = 100 - percents.reduce(0, +)
        let byRemainder = exact.indices.sorted { lhs, rhs in
            remainders[lhs] == remainders[rhs] ? lhs < rhs : remainders[lhs] > remainders[rhs]
        }
        for index in byRemainder.prefix(leftover) {
            percents[index] += 1
        }

        return scored.indices.map { PetMatchMixShare(breed: scored[$0].breed, percent: percents[$0]) }
    }

    /// What a breed is ranked by, most important first: its points, how many
    /// picks suited it best, and the latest question where one did.
    private func rankKey(for breed: PetMatchBreed) -> (Int, Int, Int) {
        let firstChoices = picks.filter { $0.value.primary == breed }
        return (points(for: breed), firstChoices.count, firstChoices.keys.max() ?? -1)
    }
}
