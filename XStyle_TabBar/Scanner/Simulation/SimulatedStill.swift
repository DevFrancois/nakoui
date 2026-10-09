import SwiftUI

/// What the simulated camera "sees": the scanner's backdrop, upright, at the
/// camera's upright resolution and cropped onto the screen the same way a
/// camera frame is. The image is immutable, so it can cross actors.
nonisolated struct SimulatedStill: @unchecked Sendable {
    let image: CGImage

    @MainActor
    static func render(screenSize: CGSize) -> SimulatedStill? {
        let upright = CGSize(width: SimulatedCameraFrame.size.height, height: SimulatedCameraFrame.size.width)
        guard screenSize.width > 0, screenSize.height > 0 else { return nil }
        // Points per frame pixel when the frame covers the screen.
        let scale = max(screenSize.width / upright.width, screenSize.height / upright.height)
        let renderer = ImageRenderer(content: ScannerBackdropPlaceholder()
            .frame(width: screenSize.width, height: screenSize.height)
            .frame(width: upright.width * scale, height: upright.height * scale)
            .background(Color(white: 0.1))
            .environment(\.colorScheme, .dark))
        renderer.scale = 1 / scale
        return renderer.cgImage.map(SimulatedStill.init)
    }
}
