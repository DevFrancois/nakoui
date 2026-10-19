import CoreGraphics
import CoreImage
import Testing
@testable import XStyle_TabBar

struct ScannerGeometryTests {
    @Test("The same frozen image stays aligned through both aspect-fill crop directions")
    func projectsSourcePixelsAfterRepeatedFolds() {
        let geometry = ScanFrameGeometry(
            imageQuad: Quad(CGRect(x: 300, y: 800, width: 400, height: 200)),
            imageSize: CGSize(width: 1_000, height: 2_000)
        )
        let open = CGSize(width: 800, height: 600)
        let closed = CGSize(width: 400, height: 700)
        let narrow = CGSize(width: 240, height: 700)

        // Open and closed crop vertically; narrow crops horizontally.
        expect(geometry.quad(in: open), equals: Quad(CGRect(x: 240, y: 140, width: 320, height: 160)))
        expect(geometry.quad(in: closed), equals: Quad(CGRect(x: 120, y: 270, width: 160, height: 80)))
        expect(geometry.quad(in: narrow), equals: Quad(CGRect(x: 50, y: 280, width: 140, height: 70)))
        expect(geometry.quad(in: open), equals: Quad(CGRect(x: 240, y: 140, width: 320, height: 160)))
    }

    @Test("Live and frozen camera quads keep the same reading order after a fold")
    func frozenAndLiveGeometryAgree() {
        let bufferQuad = Quad(
            topLeft: CGPoint(x: 700, y: 800), topRight: CGPoint(x: 700, y: 300),
            bottomRight: CGPoint(x: 900, y: 300), bottomLeft: CGPoint(x: 900, y: 800)
        )
        let mapper = AspectFillMapper(
            bufferSize: CGSize(width: 1_920, height: 1_080),
            viewSize: CGSize(width: 736, height: 678), rotation: .simulated
        )
        let live = ScanFrameGeometry(bufferQuad: bufferQuad, mapper: mapper)
        let frozen = ScanFrameGeometry(
            viewQuad: bufferQuad.map(mapper.viewPoint), viewSize: mapper.viewSize,
            imageSize: CGSize(width: 1_080, height: 1_920)
        )

        expect(live.imageQuad, equals: Quad(CGRect(x: 280, y: 700, width: 500, height: 200)))
        expect(frozen.imageQuad, equals: live.imageQuad)
        for width: CGFloat in [736, 466, 393, 736, 466] {
            let viewport = CGSize(width: width, height: 678)
            expect(frozen.quad(in: viewport), equals: live.quad(in: viewport))
            #expect(frozen.quad(in: viewport).isConvexAndUpright)
        }
    }

    @Test("The reveal card recenters and remains inside every resized viewport")
    func revealLayoutUsesCurrentViewport() {
        let geometry = ScanFrameGeometry(
            imageQuad: Quad(CGRect(x: 300, y: 800, width: 400, height: 200)),
            imageSize: CGSize(width: 1_000, height: 2_000)
        )
        for size in [
            CGSize(width: 736, height: 678), CGSize(width: 466, height: 678),
            CGSize(width: 393, height: 852), CGSize(width: 320, height: 480),
            CGSize(width: 600, height: 200), CGSize(width: 1_024, height: 320),
            CGSize(width: 736, height: 678), CGSize(width: 466, height: 678),
        ] {
            let layout = RevealLayout(viewSize: size, codeQuad: geometry.quad(in: size))
            #expect(abs(layout.card.midX - size.width / 2) < 0.000_001)
            #expect(layout.card.minX >= -0.000_001 && layout.card.maxX <= size.width + 0.000_001)
            #expect(layout.card.minY >= -0.000_001 && layout.card.maxY <= size.height + 0.000_001)
            #expect(abs(layout.liftTarget.width / layout.liftTarget.height - 2) < 0.000_001)
        }
    }

    @Test("Tracking never interpolates between different image coordinate spaces")
    func sourceImageChangeResetsSmoothing() {
        let previous = ScanFrameGeometry(
            imageQuad: Quad(CGRect(x: 10, y: 20, width: 100, height: 50)),
            imageSize: CGSize(width: 1_000, height: 2_000)
        )
        let next = ScanFrameGeometry(
            imageQuad: Quad(CGRect(x: 200, y: 400, width: 200, height: 100)),
            imageSize: CGSize(width: 2_000, height: 4_000)
        )
        #expect(previous.interpolated(to: next, fraction: 0.6) == next)
        #expect(previous.interpolated(to: previous, fraction: 0.6) == previous)
    }

    @Test("Camera projection and inverse agree for every orientation and non-quarter-turn angles")
    func cameraRotationRoundTrips() {
        let bufferSize = CGSize(width: 1_920, height: 1_080)
        for angle: CGFloat in [0, 90, 180, 270, 13.7, 359.5] {
            for viewSize in [CGSize(width: 393, height: 852), CGSize(width: 1_024, height: 768)] {
                let mapper = AspectFillMapper(bufferSize: bufferSize, viewSize: viewSize, rotation: CameraImageRotation(degrees: angle))
                for point in Quad(CGRect(origin: .zero, size: bufferSize)).corners + [CGPoint(x: 321, y: 654)] {
                    let restored = mapper.bufferPoint(fromView: mapper.viewPoint(fromBuffer: point))
                    #expect(abs(restored.x - point.x) < 0.000_001)
                    #expect(abs(restored.y - point.y) < 0.000_001)
                }
            }
        }
    }

    @Test("Metering includes all four corners when the preview is rotated")
    func rotatedViewfinderBounds() {
        let mapper = AspectFillMapper(bufferSize: CGSize(width: 1_920, height: 1_080),
                                      viewSize: CGSize(width: 800, height: 600), rotation: CameraImageRotation(degrees: 45))
        let viewfinder = CGRect(x: 300, y: 200, width: 200, height: 200)
        let bounds = mapper.bufferRect(fromView: viewfinder)
        #expect(bounds.width > 0)
        #expect(bounds.height > 0)
        for corner in Quad(viewfinder).corners.map(mapper.bufferPoint) {
            #expect(corner.x >= bounds.minX - 0.000_001 && corner.x <= bounds.maxX + 0.000_001)
            #expect(corner.y >= bounds.minY - 0.000_001 && corner.y <= bounds.maxY + 0.000_001)
        }
    }

    @Test("A half turn reprojects retained tracking pixels without smoothing across coordinate spaces")
    func trackingRotationPreservesRawPixels() {
        let mapper = AspectFillMapper(bufferSize: CGSize(width: 1_920, height: 1_080),
                                      viewSize: CGSize(width: 800, height: 600), rotation: .unrotated)
        let original = ScanFrameGeometry(bufferQuad: Quad(CGRect(x: 300, y: 200, width: 500, height: 100)), mapper: mapper)
        let turned = original.reoriented(to: CameraImageRotation(degrees: 180))
        #expect(turned.imageSize == original.imageSize)
        #expect(original.interpolated(to: turned, fraction: 0.6) == turned)
        expect(turned.reoriented(to: .unrotated).imageQuad, equals: original.imageQuad)
    }

    @Test("Core Image and top-leading pixel coordinates apply the same preview rotation")
    func rendererAndPreviewTransformsAgree() {
        let size = CGSize(width: 1_920, height: 1_080)
        for angle: CGFloat in [0, 90, 180, 270, 32] {
            let rotation = CameraImageRotation(degrees: angle)
            for point in Quad(CGRect(origin: .zero, size: size)).corners + [CGPoint(x: 456, y: 789)] {
                let imagePoint = point.applying(rotation.imageTransform(for: size))
                let ciPoint = CGPoint(x: point.x, y: size.height - point.y)
                    .applying(rotation.coreImageTransform(for: size))
                #expect(abs(imagePoint.x - ciPoint.x) < 0.000_001)
                #expect(abs(imagePoint.y - (rotation.imageSize(for: size).height - ciPoint.y)) < 0.000_001)
            }
        }
    }

    @Test("Frozen camera pixels and live code outlines agree after every quarter turn")
    func frozenRotationMatchesPreview() throws {
        let size = CGSize(width: 80, height: 40)
        let image = CIImage(color: CIColor(red: 0.8, green: 0.6, blue: 0.4)).cropped(to: CGRect(origin: .zero, size: size))
        let code = Quad(CGRect(x: 20, y: 10, width: 30, height: 10))
        for angle: CGFloat in [0, 90, 180, 270] {
            let rotation = CameraImageRotation(degrees: angle)
            let mapper = AspectFillMapper(bufferSize: size, viewSize: CGSize(width: 600, height: 400), rotation: rotation)
            let frozen = try #require(FrozenScanRenderer.render(
                image, rotation: rotation, codeQuad: code, viewQuad: code.map(mapper.viewPoint),
                viewSize: mapper.viewSize, displayScale: 1
            ))
            #expect(CGSize(width: frozen.sharp.width, height: frozen.sharp.height) == mapper.uprightSize)
            expect(frozen.geometry.quad(in: mapper.viewSize), equals: code.map(mapper.viewPoint))
            expect(frozen.geometry.imageQuad, equals: ScanFrameGeometry(bufferQuad: code, mapper: mapper).imageQuad)
        }
    }

    @Test("Fractional freeze coordinates land on the rendered marker inside the actual pixel canvas")
    func fractionalFreezeUsesRenderedPixelCanvas() throws {
        let size = CGSize(width: 180, height: 100)
        let marker = CGRect(x: 30, y: 20, width: 50, height: 25)
        let background = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: size))
        let whiteMarker = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
            .cropped(to: CGRect(x: marker.minX, y: size.height - marker.maxY, width: marker.width, height: marker.height))
        let image = whiteMarker.composited(over: background)
        let mapper = AspectFillMapper(bufferSize: size, viewSize: CGSize(width: 600, height: 400),
                                      rotation: CameraImageRotation(degrees: 32))
        let code = Quad(marker)
        let frozen = try #require(FrozenScanRenderer.render(
            image, rotation: mapper.rotation, codeQuad: code, viewQuad: code.map(mapper.viewPoint),
            viewSize: mapper.viewSize, displayScale: 1
        ))
        #expect(frozen.geometry.imageSize == CGSize(width: frozen.sharp.width, height: frozen.sharp.height))
        let center = frozen.geometry.imageQuad.center
        let rawCenter = CGPoint(x: marker.midX, y: size.height - marker.midY)
            .applying(mapper.rotation.coreImageTransform(for: size))
        #expect(abs(center.x - rawCenter.x) < 0.000_001)
        #expect(abs(center.y - (CGFloat(frozen.sharp.height) - rawCenter.y)) < 0.000_001)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext()
        context.render(CIImage(cgImage: frozen.sharp), toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: center.x.rounded(.down), y: (CGFloat(frozen.sharp.height) - center.y).rounded(.down), width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        #expect(pixel[0] > 240 && pixel[1] > 240 && pixel[2] > 240)
    }

    @Test("The viewfinder shrinks as the camera pane gets shorter, and is width-bound when tall")
    func viewfinderFollowsPaneHeight() {
        let width: CGFloat = 400
        let rects = [1_000, 500, 300].map { height in
            ScannerMetrics.viewfinderRect(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        // Tall: the width limits it, well inside its share of the height.
        #expect(rects[0].height < 1_000 * ScannerMetrics.viewfinderMaxHeightFraction)
        // Shorter panes: smaller each time, never taller than their share.
        #expect(rects[1].width < rects[0].width)
        #expect(rects[2].width < rects[1].width)
        #expect(rects[1].height <= 500 * ScannerMetrics.viewfinderMaxHeightFraction)
        #expect(rects[2].height <= 300 * ScannerMetrics.viewfinderMaxHeightFraction)
        // Still centred on the pane's optical center.
        #expect(rects[2].midX == width / 2)
    }

    @Test("Camera artwork fits short windows without changing its intended proportions")
    func shortWindowArtworkFits() {
        for size in [CGSize(width: 600, height: 200), CGSize(width: 1_024, height: 320), CGSize(width: 320, height: 200)] {
            let viewport = CGRect(origin: .zero, size: size)
            let viewfinder = ScannerMetrics.viewfinderRect(in: viewport)
            #expect(viewfinder.minX >= 0 && viewfinder.maxX <= size.width)
            #expect(viewfinder.minY >= 0 && viewfinder.maxY <= size.height)
            #expect(abs(viewfinder.width / viewfinder.height - ScannerMetrics.viewfinderAspectRatio) < 0.000_001)
            for aspect: CGFloat in [1.1, 1.6, 2.4] {
                let layout = RevealLayout(viewSize: size, codeQuad: Quad(CGRect(x: 0, y: 0, width: 200 * aspect, height: 200)))
                #expect(layout.card.minX >= -0.000_001 && layout.card.maxX <= size.width + 0.000_001)
                #expect(layout.card.minY >= -0.000_001 && layout.card.maxY <= size.height + 0.000_001)
                #expect(abs(layout.liftTarget.width / layout.liftTarget.height - aspect) < 0.000_001)
            }
        }
    }

    private func expect(_ actual: Quad, equals expected: Quad) {
        for (actualPoint, expectedPoint) in zip(actual.corners, expected.corners) {
            #expect(abs(actualPoint.x - expectedPoint.x) < 0.000_001)
            #expect(abs(actualPoint.y - expectedPoint.y) < 0.000_001)
        }
    }
}
