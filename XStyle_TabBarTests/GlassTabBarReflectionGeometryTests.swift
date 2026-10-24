import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
struct GlassTabBarReflectionGeometryTests {
    @Test("Vertical reflections keep page colors at their screen height as the viewport resizes")
    func verticalReflectionKeepsPageHeight() throws {
        let viewport = CGRect(x: 0, y: 0, width: 60, height: 244)
        let layouts: [(size: CGSize, origin: CGPoint)] = [
            (CGSize(width: 951, height: 669), CGPoint(x: 873, y: 401)),
            (CGSize(width: 466, height: 678), CGPoint(x: 388, y: 410))
        ]
        for layout in layouts {
            let source = CGRect(origin: .zero, size: layout.size)
            let geometry = try makeGeometry(source: source, viewport: viewport, axis: .vertical) {
                CGPoint(x: $0.x - layout.origin.x, y: $0.y - layout.origin.y)
            }
            for stripeY: CGFloat in [445, 500, 526] {
                let point = project(CGPoint(x: source.midX, y: stripeY), with: geometry)
                #expect(abs(point.y + layout.origin.y - stripeY) < 0.0001,
                        "Centering the whole page on the rail would displace these colors downwards")
                #expect(abs(point.x - viewport.midX) < 0.0001,
                        "Keep the existing centered strip across the rail's width")
            }
            #expect(geometry.portalBounds.height == source.height)
            expectShortAxisCoverage(geometry, viewport: viewport, axis: .vertical)
        }
    }

    @Test("Nonzero source bounds and shared comparison scaling preserve registration")
    func sourceOriginsAndSharedScaling() throws {
        let source = CGRect(x: 100, y: 200, width: 950, height: 670)
        let viewport = CGRect(x: 7, y: 9, width: 60, height: 244)
        let viewportOriginInSource = CGPoint(x: 973, y: 601)
        for scale: CGFloat in [1, 1.5, 2] {
            let geometry = try makeGeometry(source: source, viewport: viewport, axis: .vertical) { point in
                // Both siblings share the comparison canvas's scaleEffect.
                let windowPoint = CGPoint(x: point.x * scale + 80, y: point.y * scale + 120)
                let windowOrigin = CGPoint(x: viewportOriginInSource.x * scale + 80,
                                           y: viewportOriginInSource.y * scale + 120)
                return CGPoint(x: (windowPoint.x - windowOrigin.x) / scale + viewport.minX,
                               y: (windowPoint.y - windowOrigin.y) / scale + viewport.minY)
            }
            let point = project(CGPoint(x: source.midX, y: 645), with: geometry)
            #expect(abs(point.x - 37) < 0.0001)
            #expect(abs(point.y - 53) < 0.0001)
            #expect(geometry.sourceBounds == source)
            #expect(geometry.portalBounds.height == source.height)
            expectShortAxisCoverage(geometry, viewport: viewport, axis: .vertical)
        }
    }

    @Test("Native press scaling keeps color heights fixed and expands the captured strip")
    func inversePressScalingPreservesAlignment() throws {
        let source = CGRect(x: 0, y: 0, width: 950, height: 670)
        let viewport = CGRect(x: 0, y: 0, width: 60, height: 244)
        let origin = CGPoint(x: 873, y: 401)
        let press = CGSize(width: 1.1, height: 1.05)
        let geometry = try makeGeometry(source: source, viewport: viewport, axis: .vertical) { point in
            CGPoint(x: (point.x - origin.x - viewport.midX) / press.width + viewport.midX,
                    y: (point.y - origin.y - viewport.midY) / press.height + viewport.midY)
        }
        let reflected = project(CGPoint(x: source.midX, y: 500), with: geometry)
        let displayedY = origin.y + viewport.midY + (reflected.y - viewport.midY) * press.height
        #expect(abs(displayedY - 500) < 0.0001)
        #expect(abs(geometry.portalBounds.width - 66) < 0.0001)
        expectShortAxisCoverage(geometry, viewport: viewport, axis: .vertical)
    }

    @Test("The bottom bar registers the page horizontally while keeping its centered vertical strip")
    func horizontalReflectionKeepsPagePosition() throws {
        let source = CGRect(x: 0, y: 0, width: 950, height: 670)
        let viewport = CGRect(x: 0, y: 0, width: 360, height: 64)
        let geometry = try makeGeometry(source: source, viewport: viewport, axis: .horizontal) {
            CGPoint(x: $0.x - 300, y: $0.y - 600)
        }
        for stripeX: CGFloat in [320, 445, 600] {
            let point = project(CGPoint(x: stripeX, y: source.midY), with: geometry)
            #expect(abs(point.x + 300 - stripeX) < 0.0001)
            #expect(abs(point.y - 32) < 0.0001)
        }
        #expect(geometry.portalBounds.width == source.width)
        expectShortAxisCoverage(geometry, viewport: viewport, axis: .horizontal)
    }

    @Test("Empty, nonfinite and singular mappings cannot reach the reflection renderer")
    func invalidGeometryIsRejected() {
        let source = CGRect(x: 0, y: 0, width: 950, height: 670)
        let viewport = CGRect(x: 0, y: 0, width: 60, height: 244)
        for invalidSource in [CGRect.zero, CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 670)] {
            #expect(GlassTabBarReflectionGeometry(sourceBounds: invalidSource, viewportBounds: viewport,
                                                 sourceOrigin: .zero, sourceXAxis: CGPoint(x: 1, y: 0),
                                                 sourceYAxis: CGPoint(x: 0, y: 1), axis: .vertical) == nil)
        }
        for invalidViewport in [CGRect.zero, CGRect(x: 0, y: CGFloat.nan, width: 60, height: 244)] {
            #expect(GlassTabBarReflectionGeometry(sourceBounds: source, viewportBounds: invalidViewport,
                                                 sourceOrigin: .zero, sourceXAxis: CGPoint(x: 1, y: 0),
                                                 sourceYAxis: CGPoint(x: 0, y: 1), axis: .vertical) == nil)
        }
        for invalidAxis in [CGPoint.zero, CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: CGFloat.infinity, y: 0)] {
            #expect(GlassTabBarReflectionGeometry(sourceBounds: source, viewportBounds: viewport,
                                                 sourceOrigin: .zero, sourceXAxis: invalidAxis,
                                                 sourceYAxis: CGPoint(x: 0, y: 1), axis: .vertical) == nil)
        }
    }

    private func makeGeometry(source: CGRect, viewport: CGRect, axis: NSLayoutConstraint.Axis,
                              convert: (CGPoint) -> CGPoint) throws -> GlassTabBarReflectionGeometry {
        try #require(GlassTabBarReflectionGeometry(
            sourceBounds: source, viewportBounds: viewport,
            sourceOrigin: convert(source.origin),
            sourceXAxis: convert(CGPoint(x: source.minX + 1, y: source.minY)),
            sourceYAxis: convert(CGPoint(x: source.minX, y: source.minY + 1)), axis: axis
        ))
    }

    private func project(_ point: CGPoint, with geometry: GlassTabBarReflectionGeometry) -> CGPoint {
        let relative = CGPoint(x: point.x - geometry.sourceBounds.midX,
                               y: point.y - geometry.sourceBounds.midY).applying(geometry.portalTransform)
        return CGPoint(x: geometry.portalPosition.x + relative.x, y: geometry.portalPosition.y + relative.y)
    }

    private func expectShortAxisCoverage(_ geometry: GlassTabBarReflectionGeometry,
                                         viewport: CGRect, axis: NSLayoutConstraint.Axis) {
        let source = geometry.sourceBounds
        if axis == .vertical {
            let left = project(CGPoint(x: source.midX - geometry.portalBounds.width / 2, y: source.midY), with: geometry)
            let right = project(CGPoint(x: source.midX + geometry.portalBounds.width / 2, y: source.midY), with: geometry)
            #expect(abs(left.x - viewport.minX) < 0.0001)
            #expect(abs(right.x - viewport.maxX) < 0.0001)
        } else {
            let top = project(CGPoint(x: source.midX, y: source.midY - geometry.portalBounds.height / 2), with: geometry)
            let bottom = project(CGPoint(x: source.midX, y: source.midY + geometry.portalBounds.height / 2), with: geometry)
            #expect(abs(top.y - viewport.minY) < 0.0001)
            #expect(abs(bottom.y - viewport.maxY) < 0.0001)
        }
    }
}
