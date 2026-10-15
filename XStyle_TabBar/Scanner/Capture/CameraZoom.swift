import Foundation

/// The camera's zoom: the range the user can pinch through, and the zoom
/// scanning starts at.
nonisolated struct CameraZoom: Equatable, Sendable {
    var range: ClosedRange<Double>
    /// Where scanning starts: sharp on small codes (see `BarcodeZoom`).
    var recommended: Double

    /// The zoom buttons: the widest zoom and the recommended one, or 2× on
    /// cameras that start unzoomed.
    var presets: [Double] {
        let second = recommended > range.lowerBound + 0.1 ? recommended : clamped(2)
        return second > range.lowerBound ? [range.lowerBound, second] : [range.lowerBound]
    }

    func clamped(_ factor: Double) -> Double {
        min(max(factor, range.lowerBound), range.upperBound)
    }

    /// The preset `factor` falls under: the highest at or below it, allowing
    /// for the tenth the buttons round to.
    func presetIndex(for factor: Double) -> Int {
        presets.lastIndex { $0 <= factor + 0.05 } ?? 0
    }
}
