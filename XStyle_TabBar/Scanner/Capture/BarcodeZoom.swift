import Foundation

/// The zoom that keeps small barcodes sharp. Cameras with a long minimum focus
/// distance, about 20 cm on recent Pro iPhones, blur a code held close enough
/// to look big; zooming in lets it be held farther away, in focus. After
/// Apple's AVCamBarcode sample (WWDC21, "What's new in camera capture").
nonisolated enum BarcodeZoom {
    /// - Parameters:
    ///   - minimumFocusDistance: The camera's closest focus, in millimeters.
    ///     Zero or less when unknown.
    ///   - fieldOfView: The active format's field of view along the sensor's
    ///     long side, in degrees.
    ///   - formatAspect: The format's short side over its long side. In
    ///     portrait the screen's width spans the short side.
    ///   - codeWidth: The narrowest code to keep sharp, in millimeters.
    ///   - fill: Share of the screen width that code should span.
    ///   - maximum: The highest factor to return.
    /// - Returns: A zoom factor of at least 1.
    static func recommendedFactor(
        minimumFocusDistance: Double,
        fieldOfView: Double,
        formatAspect: Double,
        codeWidth: Double,
        fill: Double,
        maximum: Double
    ) -> Double {
        guard minimumFocusDistance > 0, fieldOfView > 0, formatAspect > 0, fill > 0 else { return 1 }

        // The width the screen shows per millimeter of distance, in portrait.
        let widthPerDistance = 2 * tan(fieldOfView / 2 * .pi / 180) * formatAspect
        // How close the code must be to span `fill` of the screen unzoomed.
        let subjectDistance = codeWidth / (fill * widthPerDistance)
        guard subjectDistance < minimumFocusDistance else { return 1 }

        return max(1, min(minimumFocusDistance / subjectDistance, maximum))
    }
}
