import Foundation

/// The camera's zoom range, starting zoom, and button presets.
nonisolated struct CameraZoom: Equatable, Sendable {
    let range: ClosedRange<Double>
    /// A close-up preset that keeps small codes sharp (see `BarcodeZoom`).
    let recommended: Double
    /// The zoom buttons: the widest zoom and the recommended one, or 2× on
    /// cameras whose recommended zoom is the widest.
    let presets: [Double]

    /// Scanning starts at 1×, within the camera's supported range.
    var initial: Double { range.clamp(1) }

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
