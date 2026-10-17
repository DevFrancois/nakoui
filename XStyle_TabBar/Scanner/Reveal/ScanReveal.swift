import CoreGraphics
import Foundation

/// The found-code animation, from the first sighting until the result has
/// closed. Times are absolute, so the view can derive every frame from the
/// clock.
nonisolated struct ScanReveal: Sendable {
    let code: ScannedCode
    /// The code in the live source image, while the camera still runs.
    var geometry: ScanFrameGeometry
    let startDate: Date
    /// The frozen frame, once the camera has stopped.
    private(set) var frozen: FrozenScan?
    private(set) var bloom: BloomPlan?
    private(set) var freezeDate: Date?
    private(set) var closeDate: Date?

    init(code: ScannedCode, geometry: ScanFrameGeometry, startDate: Date = .now) {
        self.code = code
        self.geometry = geometry
        self.startDate = startDate
    }

    mutating func freeze(_ frozen: FrozenScan, at date: Date = .now) {
        self.frozen = frozen
        let card = RevealLayout(viewSize: frozen.geometry.imageSize, codeQuad: frozen.geometry.imageQuad).card
        bloom = BloomPlan(aspect: card.width / max(card.height, 1))
        freezeDate = date
    }

    mutating func close(at date: Date = .now) {
        closeDate = date
    }

    /// Seconds since detection when the frame froze.
    var freezeTime: Double? {
        freezeDate.map { $0.timeIntervalSince(startDate) }
    }

    func frame(at date: Date, reduceMotion: Bool) -> ScanRevealFrame {
        ScanRevealTimeline.frame(
            at: date.timeIntervalSince(startDate),
            freezeTime: freezeTime,
            closeTime: closeDate.map { date.timeIntervalSince($0) },
            reduceMotion: reduceMotion
        )
    }
}
