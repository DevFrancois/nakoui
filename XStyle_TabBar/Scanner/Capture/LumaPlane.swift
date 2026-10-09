import BarcodeDecoding
import CoreVideo

/// Zero-copy access to a camera frame's luma (Y) plane.
nonisolated enum LumaPlane {
    /// Locks the buffer read-only and hands its luma plane to `body`. Nil for
    /// anything but 4:2:0 bi-planar frames, such as the compressed formats the
    /// CPU must never read.
    static func read<Result>(_ pixelBuffer: CVPixelBuffer, _ body: (LumaImage) -> Result) -> Result? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { return nil }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        return body(LumaImage(
            pixels: base.assumingMemoryBound(to: UInt8.self),
            width: CVPixelBufferGetWidthOfPlane(pixelBuffer, 0),
            height: CVPixelBufferGetHeightOfPlane(pixelBuffer, 0),
            bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        ))
    }
}
