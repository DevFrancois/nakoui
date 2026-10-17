import CoreGraphics
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
            viewSize: CGSize(width: 736, height: 678), rotatesClockwise: true
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
            CGSize(width: 736, height: 678), CGSize(width: 466, height: 678),
        ] {
            let layout = RevealLayout(viewSize: size, codeQuad: geometry.quad(in: size))
            #expect(abs(layout.card.midX - size.width / 2) < 0.000_001)
            #expect(layout.card.minX >= 0 && layout.card.maxX <= size.width)
            #expect(layout.card.minY >= 0 && layout.card.maxY <= size.height)
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

    private func expect(_ actual: Quad, equals expected: Quad) {
        for (actualPoint, expectedPoint) in zip(actual.corners, expected.corners) {
            #expect(abs(actualPoint.x - expectedPoint.x) < 0.000_001)
            #expect(abs(actualPoint.y - expectedPoint.y) < 0.000_001)
        }
    }
}
