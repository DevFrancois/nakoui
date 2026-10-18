import CoreGraphics
import Testing
@testable import XStyle_TabBar

struct TabBarReflectionGeometryTests {
    @Test("Reflection coordinates preserve the full scene while clipping its visible region")
    func clippedSceneKeepsItsTextureCoordinates() throws {
        let source = CGRect(x: 100, y: 80, width: 400, height: 600)
        let capsule = CGRect(x: 380, y: 650, width: 44, height: 180)
        let result = try #require(TabBarReflectionGeometry(
            capsuleInWindow: capsule,
            sourceInWindow: source,
            visibleSourceInWindow: CGRect(x: 150, y: 120, width: 250, height: 500)
        ))

        #expect(result.sourceSize == source.size)
        #expect(result.capsuleRect == CGRect(x: 280, y: 570, width: 44, height: 180))
        #expect(result.visibleRect == CGRect(x: 50, y: 40, width: 250, height: 500))

        let pointInCapsule = CGPoint(x: 22, y: 90)
        let sourcePoint = CGPoint(x: result.capsuleRect.minX + pointInCapsule.x,
                                  y: result.capsuleRect.minY + pointInCapsule.y)
        #expect(sourcePoint.x + source.minX == capsule.minX + pointInCapsule.x)
        #expect(sourcePoint.y + source.minY == capsule.minY + pointInCapsule.y)
    }

    @Test("An oversized scene keeps its full extent when the window clips it")
    func oversizedSceneIsNotRescaledToItsVisiblePortion() throws {
        let result = try #require(TabBarReflectionGeometry(
            capsuleInWindow: CGRect(x: 316, y: 300, width: 44, height: 206),
            sourceInWindow: CGRect(x: -120, y: -80, width: 900, height: 1000),
            visibleSourceInWindow: CGRect(x: 0, y: 0, width: 390, height: 844)
        ))

        #expect(result.sourceSize == CGSize(width: 900, height: 1000))
        #expect(result.capsuleRect == CGRect(x: 436, y: 380, width: 44, height: 206))
        #expect(result.visibleRect == CGRect(x: 120, y: 80, width: 390, height: 844))
    }

    @Test("Vertical menus may lie outside either side of the scene", arguments: [CGFloat(28), 520])
    func verticalSidebarOriginsAreNotClamped(_ capsuleX: CGFloat) throws {
        let source = CGRect(x: 100, y: 50, width: 400, height: 700)
        let result = try #require(TabBarReflectionGeometry(
            capsuleInWindow: CGRect(x: capsuleX, y: 300, width: 44, height: 206),
            sourceInWindow: source,
            visibleSourceInWindow: source
        ))

        #expect(result.capsuleRect.origin == CGPoint(x: capsuleX - 100, y: 250))
        #expect(result.visibleRect == CGRect(origin: .zero, size: source.size))
        #expect(result.sourceSize == source.size)
    }

    @Test("A horizontal menu below the scene can reflect its lower edge")
    func horizontalMenuRetainsItsPositionBelowTheScene() throws {
        let source = CGRect(x: 0, y: 100, width: 400, height: 640)
        let result = try #require(TabBarReflectionGeometry(
            capsuleInWindow: CGRect(x: 25, y: 760, width: 350, height: 60),
            sourceInWindow: source,
            visibleSourceInWindow: source
        ))

        #expect(result.capsuleRect == CGRect(x: 25, y: 660, width: 350, height: 60))
        #expect(result.capsuleRect.minY > result.sourceSize.height)
    }

    @Test("Sampling ignores distant and clipped-away scene content")
    func onlyVisibleContentWithinReachIsEligible() {
        let source = CGRect(x: 0, y: 0, width: 300, height: 1200)
        let capsule = CGRect(x: 20, y: 500, width: 260, height: 60)
        for visible in [
            CGRect(x: 0, y: 0, width: 300, height: 100),
            CGRect(x: 0, y: 900, width: 300, height: 100),
            CGRect(x: 500, y: 500, width: 100, height: 100),
        ] {
            #expect(TabBarReflectionGeometry(capsuleInWindow: capsule, sourceInWindow: source,
                                             visibleSourceInWindow: visible) == nil)
        }
    }

    @Test("Visibility is intersected with the scene before mapping")
    func visibilityCannotExtendBeyondTheSource() throws {
        let source = CGRect(x: 30, y: 40, width: 300, height: 500)
        let result = try #require(TabBarReflectionGeometry(
            capsuleInWindow: CGRect(x: 100, y: 500, width: 200, height: 60),
            sourceInWindow: source,
            visibleSourceInWindow: CGRect(x: 0, y: 0, width: 1000, height: 1000)
        ))
        #expect(result.visibleRect == CGRect(origin: .zero, size: source.size))
    }

    @Test("Reach requires a positive overlap and may be zero")
    func reachDoesNotAdmitATouchingOrDistantScene() {
        let source = CGRect(x: 0, y: 0, width: 300, height: 300)
        let capsule = CGRect(x: 20, y: 396, width: 260, height: 60)
        #expect(TabBarReflectionGeometry(capsuleInWindow: capsule, sourceInWindow: source,
                                         visibleSourceInWindow: source) == nil)
        #expect(TabBarReflectionGeometry(capsuleInWindow: capsule, sourceInWindow: source,
                                         visibleSourceInWindow: source, reach: 97) != nil)
        #expect(TabBarReflectionGeometry(capsuleInWindow: source, sourceInWindow: source,
                                         visibleSourceInWindow: source, reach: 0) != nil)
    }

    @Test("Invalid rectangle inputs never reach shader uniforms", arguments: [0, 1, 2])
    func rejectsInvalidRectangles(_ input: Int) {
        let valid = CGRect(x: 10, y: 20, width: 100, height: 200)
        let invalid = [
            CGRect.zero,
            CGRect.null,
            CGRect.infinite,
            CGRect(x: 0, y: 0, width: 0, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: 0),
            CGRect(x: 0, y: 0, width: -100, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: -100),
            CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: CGFloat.infinity, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: CGFloat.nan),
            CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0,
                   width: CGFloat.greatestFiniteMagnitude, height: 100),
        ]
        for rect in invalid {
            var inputs = [valid, valid, valid]
            inputs[input] = rect
            #expect(TabBarReflectionGeometry(capsuleInWindow: inputs[0], sourceInWindow: inputs[1],
                                             visibleSourceInWindow: inputs[2]) == nil)
        }
    }

    @Test("Invalid reach values cannot produce sampling bounds",
          arguments: [CGFloat(-1), .nan, .infinity, .greatestFiniteMagnitude])
    func rejectsInvalidReach(_ reach: CGFloat) {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 200)
        #expect(TabBarReflectionGeometry(capsuleInWindow: rect, sourceInWindow: rect,
                                         visibleSourceInWindow: rect, reach: reach) == nil)
    }
}
