import Foundation

/// A number to guess with a slider, counted right within a tolerance.
struct EstimateQuestion: Identifiable {
    let id = UUID()
    let prompt: LocalizedStringResource
    let range: ClosedRange<Double>
    let step: Double
    let answer: Double
    /// How far off a guess may be and still count.
    let tolerance: Double
    let unit: LocalizedStringResource
    let fact: LocalizedStringResource

    /// Where the slider starts: the middle of the range, on a step.
    var startValue: Double {
        let middle = (range.lowerBound + range.upperBound) / 2
        return (middle / step).rounded() * step
    }

    func isClose(_ guess: Double) -> Bool {
        abs(guess - answer) <= tolerance
    }

    /// The position of a value along the range, from 0 to 1.
    func fraction(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }
}
