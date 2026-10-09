import CoreImage
import CoreVideo

/// Turns a portrait image of the screen into the frame the back camera would
/// deliver: a 1920x1080 landscape full-range 4:2:0 buffer which, turned
/// clockwise and aspect-filled, gives the image back.
nonisolated enum SimulatedCameraFrame {
    static let size = CGSize(width: 1920, height: 1080)
    private static let context = CIContext(options: [.cacheIntermediates: false, .name: "scanner.simulated-camera"])

    static func make(from portrait: CGImage) -> CVPixelBuffer? {
        var frame: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()] as CFDictionary
        guard CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                  attributes, &frame) == kCVReturnSuccess, let frame else { return nil }
        // The camera's frame turned clockwise is the screen, so the screen
        // turned counterclockwise is the frame.
        let landscape = CIImage(cgImage: portrait).oriented(.left)
        let extent = landscape.extent
        let fitted = landscape.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: size.width / extent.width, y: size.height / extent.height)))
        context.render(fitted, to: frame)
        return frame
    }
}
