import Foundation

/// A matchup on one stat: the known pet's value is on show, and the player
/// calls whether the challenger's is higher or lower.
struct HigherLowerRound: Identifiable {
    let id = UUID()
    let stat: HigherLowerStat
    let known: HigherLowerContender
    let challenger: HigherLowerContender
    let fact: LocalizedStringResource

    var answer: HigherLowerGuess {
        challenger.value > known.value ? .higher : .lower
    }

    /// How many times the larger value is the smaller one.
    var ratio: Double {
        let smaller = min(known.value, challenger.value)
        guard smaller > 0 else { return 0 }
        return max(known.value, challenger.value) / smaller
    }

    /// Where a value sits on the meter, from 0 to 1. The known value always
    /// lands at the midpoint, so the meter gives nothing away before the call.
    func meterFraction(of value: Double) -> Double {
        guard known.value > 0 else { return 0 }
        return min(max(value / (known.value * 2), 0), 1)
    }
}
