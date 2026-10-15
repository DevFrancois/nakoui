import Foundation

/// The camera's zoom: the range the user can pinch through, and the zoom
/// scanning starts at.
nonisolated struct CameraZoom: Equatable, Sendable {
    let range: ClosedRange<Double>
    /// Where scanning starts: sharp on small codes (see `BarcodeZoom`).
    let recommended: Double
    /// The zoom buttons: the widest zoom and the recommended one, or 2× on
    /// cameras that start unzoomed.
    let presets: [Double]

    /// - Parameter recommended: Kept within `range`.
    init(range: ClosedRange<Double>, recommended: Double) {
        self.range = range
        self.recommended = range.clamp(recommended)
        let second = self.recommended > range.lowerBound + 0.1 ? self.recommended : range.clamp(2)
        presets = second > range.lowerBound ? [range.lowerBound, second] : [range.lowerBound]
    }

    /// The preset `factor` falls under: the highest at or below it, allowing
    /// for the tenth the buttons round to.
    func presetIndex(for factor: Double) -> Int {
        presets.lastIndex { $0 <= factor + 0.05 } ?? 0
    }
}
