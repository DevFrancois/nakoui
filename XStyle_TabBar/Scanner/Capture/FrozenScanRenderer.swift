import CoreImage
import CoreImage.CIFilterBuiltins

/// Prepares a frame for the reveal with Core Image: the upright still, a
/// blurred and frosted copy, and the code cut out and flattened. Renders are
/// immediate, so the images own their pixels and a capture buffer can be
/// released straight away.
nonisolated enum FrozenScanRenderer {
    /// One context for the app's lifetime: making one is expensive.
    private static let context = CIContext(options: [.cacheIntermediates: false, .name: "scanner.freeze"])
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    /// Transparent border around the patch, in pixels.
    private static let paddingPixels: CGFloat = 2

    /// - Parameters:
    ///   - image: The frame, in buffer orientation.
    ///   - rotation: The same coordinator angle used by the preview connection.
    ///   - codeQuad: The code in the image, in pixels with y down, in reading
    ///     orientation.
    ///   - viewQuad: The same quad in full-screen view points.
    static func render(_ image: CIImage, rotation: CameraImageRotation, codeQuad: Quad,
                       viewQuad: Quad, viewSize: CGSize, displayScale: CGFloat) -> FrozenScan? {
        let layout = RevealLayout(viewSize: viewSize, codeQuad: viewQuad)

        let rotated = image.transformed(by: rotation.coreImageTransform(for: image.extent.size))
        // CGImage has integral pixel dimensions. Keep the image and its
        // canonical code coordinates in that exact canvas after any rotation.
        let upright = rotated.cropped(to: rotated.extent.integral)
        guard let sharp = makeImage(upright, from: upright.extent) else { return nil }

        // A big blur hides the downscale, which makes it about 16x cheaper.
        // Clamping keeps the edges from fading to transparent.
        let small = upright.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        let frosted = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 14)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.9, kCIInputBrightnessKey: 0.08, kCIInputContrastKey: 0.85,
            ])
            .cropped(to: small.extent)
        guard let blurred = makeImage(frosted, from: small.extent) else { return nil }

        guard let patch = flatten(image, codeQuad: codeQuad, size: layout.liftTarget.size, displayScale: displayScale) else { return nil }
        return FrozenScan(
            sharp: sharp, blurred: blurred, patch: patch, patchPadding: paddingPixels / displayScale,
            geometry: ScanFrameGeometry(
                bufferQuad: codeQuad,
                mapper: AspectFillMapper(bufferSize: image.extent.size, viewSize: viewSize, rotation: rotation),
                renderedImageBounds: CGRect(origin: upright.extent.origin, size: CGSize(width: sharp.width, height: sharp.height))
            )
        )
    }

    /// The same, off the caller's actor: for callers on the main actor.
    @concurrent
    static func render(_ image: CGImage, codeQuad: Quad, viewQuad: Quad, viewSize: CGSize, displayScale: CGFloat) async -> FrozenScan? {
        render(CIImage(cgImage: image), rotation: .unrotated, codeQuad: codeQuad, viewQuad: viewQuad,
               viewSize: viewSize, displayScale: displayScale)
    }

    /// Compiles Core Image's kernels on a real frame, so the first freeze is quick.
    static func warmUp(with image: CIImage) {
        let tiny = image.cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        _ = makeImage(tiny.applyingGaussianBlur(sigma: 2), from: tiny.extent)
    }

    private static func flatten(_ image: CIImage, codeQuad q: Quad, size: CGSize, displayScale: CGFloat) -> CGImage? {
        // Core Image's origin is at the bottom left, so y flips.
        let height = image.extent.height
        func flipped(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: height - p.y) }
        let correction = CIFilter.perspectiveCorrection()
        correction.inputImage = image
        correction.topLeft = flipped(q.topLeft)
        correction.topRight = flipped(q.topRight)
        correction.bottomRight = flipped(q.bottomRight)
        correction.bottomLeft = flipped(q.bottomLeft)
        guard let rectified = correction.outputImage, !rectified.extent.isEmpty else { return nil }

        let r = rectified.extent
        let content = CGRect(x: paddingPixels, y: paddingPixels, width: size.width * displayScale, height: size.height * displayScale)
        let canvas = content.insetBy(dx: -paddingPixels, dy: -paddingPixels)
        let placed = rectified
            .transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY)
                .concatenating(CGAffineTransform(scaleX: content.width / r.width, y: content.height / r.height))
                .concatenating(CGAffineTransform(translationX: content.minX, y: content.minY)))
            .cropped(to: content)
            .composited(over: CIImage(color: .clear).cropped(to: canvas))
        return makeImage(placed, from: canvas)
    }

    private static func makeImage(_ image: CIImage, from rect: CGRect) -> CGImage? {
        context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: colorSpace, deferred: false)
    }
}
