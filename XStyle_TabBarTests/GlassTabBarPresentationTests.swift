import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct GlassTabBarPresentationTests {
    @Test("Tracking requires an attached anchor in the same window with matching dimensions")
    func rejectsUnavailableCoordinateSpaces() throws {
        let fixture = try PresentationFixture()
        let presentation = fixture.presentation
        let view = fixture.view
        let anchor = fixture.anchor
        #expect(presentation.coordinateSpace(for: view) === anchor)

        presentation.coordinateView = nil
        #expect(presentation.coordinateSpace(for: view) == nil)
        presentation.coordinateView = anchor

        anchor.removeFromSuperview()
        #expect(presentation.coordinateSpace(for: view) == nil)
        fixture.toolbar.addSubview(anchor)

        view.removeFromSuperview()
        #expect(presentation.coordinateSpace(for: view) == nil)
        fixture.visualContainer.addSubview(view)

        let otherWindow = UIWindow(windowScene: try #require(fixture.window.windowScene))
        otherWindow.frame = fixture.window.frame
        otherWindow.addSubview(anchor)
        #expect(presentation.coordinateSpace(for: view) == nil)
        fixture.toolbar.addSubview(anchor)

        for mismatch in [CGSize(width: view.bounds.width - 1, height: view.bounds.height),
                         CGSize(width: view.bounds.width, height: view.bounds.height + 1)] {
            anchor.bounds.size = mismatch
            #expect(presentation.coordinateSpace(for: view) == nil)
        }
        anchor.bounds.size = view.bounds.size
        #expect(presentation.coordinateSpace(for: view) === anchor)
    }

    @Test("Visual scaling preserves physical finger coordinates but toolbar movement remains observable")
    func separatesVisualDeformationFromToolbarMovement() throws {
        let fixture = try PresentationFixture()
        let originalPoint = CGPoint(x: 72, y: 20)
        let fingerInWindow = fixture.anchor.convert(originalPoint, to: fixture.window)
        let originalFrame = fixture.anchor.convert(fixture.anchor.bounds, to: fixture.window)
        let originalLocalPoint = fixture.view.convert(fingerInWindow, from: fixture.window)

        // SwiftUI scales the entire visual subtree; the sibling anchor stays put.
        fixture.visualContainer.transform = CGAffineTransform(scaleX: 1.04, y: 1.03)
        let scaledLocalPoint = fixture.view.convert(fingerInWindow, from: fixture.window)
        #expect(abs(scaledLocalPoint.x - originalLocalPoint.x) > 1)
        let anchor = try #require(fixture.presentation.coordinateSpace(for: fixture.view))
        expectPoint(fixture.view.convert(scaledLocalPoint, to: anchor), equals: originalPoint)
        #expect(anchor.convert(anchor.bounds, to: fixture.window) == originalFrame)
        #expect(fixture.view.convert(fixture.view.bounds, to: fixture.window).width > originalFrame.width)

        let movement = CGPoint(x: 36, y: 24)
        fixture.toolbar.center.x += movement.x
        fixture.toolbar.center.y += movement.y
        let movedFrame = anchor.convert(anchor.bounds, to: fixture.window)
        expectPoint(movedFrame.origin, equals: CGPoint(x: originalFrame.minX + movement.x,
                                                      y: originalFrame.minY + movement.y))
        let pointAfterMovement = fixture.view.convert(fingerInWindow, from: fixture.window)
        expectPoint(fixture.view.convert(pointAfterMovement, to: anchor),
                    equals: CGPoint(x: originalPoint.x - movement.x, y: originalPoint.y - movement.y))
    }

    @Test("A newer press wins over a queued layout reset; the current reset still settles the glass")
    func deferredResetsRespectNewerPresses() async {
        let presentation = GlassTabBarPresentation()
        presentation.track(scale: CGSize(width: 1.02, height: 1.02), animated: false)
        presentation.resetAfterLayout()
        let newPress = CGSize(width: 1.04, height: 1.03)
        presentation.track(scale: newPress, animated: false)

        await drainMainQueue()
        #expect(presentation.scale == newPress)

        presentation.resetAfterLayout()
        await drainMainQueue()
        #expect(presentation.scale == CGSize(width: 1, height: 1))
    }

    @Test("View updates defer observed releases and cannot overwrite a newer touch")
    func viewUpdatesDeferReleasesWithoutClobberingNewPresses() async {
        let presentation = GlassTabBarPresentation()
        let heldScale = CGSize(width: 1.04, height: 1.03)
        presentation.track(scale: heldScale, animated: false)

        presentation.updateView {
            presentation.release(animated: true)
            #expect(presentation.scale == heldScale,
                    "The representable update must not mutate its observed presentation")
        }
        #expect(presentation.scale == heldScale)
        await drainMainQueue()
        #expect(presentation.scale == CGSize(width: 1, height: 1))

        presentation.track(scale: heldScale, animated: false)
        presentation.updateView {
            presentation.release(animated: true)
            #expect(presentation.scale == heldScale)
        }
        let newerPress = CGSize(width: 1.02, height: 1.04)
        presentation.track(scale: newerPress, animated: false)
        await drainMainQueue()
        #expect(presentation.scale == newerPress)
    }

    @Test("A hold survives repeated SwiftUI updates and scaling, then cancels when the toolbar moves")
    func holdsSurviveVisualUpdatesButNotPlacementChanges() async throws {
        let fixture = try PresentationFixture()
        let recognizer = try #require(fixture.view.gestureRecognizers?.compactMap {
            $0 as? GlassTabBarTouchRecognizer
        }.first)
        let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
        let search = try #require(buttons.first { $0.tab == .search })
        var committedTabs: [RootTab] = []
        fixture.view.onSelect = { committedTabs.append($0) }
        await drainMainQueue()

        let searchCenter = search.convert(CGPoint(x: search.bounds.midX, y: search.bounds.midY),
                                          to: fixture.view)
        recognizer.onBegin?(searchCenter)
        let heldScale = fixture.presentation.scale
        try #require(heldScale.width > 1 && heldScale.height > 1)

        fixture.configure()
        fixture.view.select(.home, animated: false)
        fixture.visualContainer.transform = CGAffineTransform(scaleX: heldScale.width, y: heldScale.height)
        fixture.view.setNeedsLayout()
        fixture.view.layoutIfNeeded()
        await drainMainQueue()

        #expect(fixture.presentation.scale == heldScale)
        #expect(buttons.filter(\.isSelected).map(\.tab) == [.home])
        #expect(committedTabs.isEmpty, "Holding must not commit a destination")

        fixture.toolbar.center.y += 40
        fixture.view.setNeedsLayout()
        fixture.view.layoutIfNeeded()
        await drainMainQueue()

        #expect(fixture.presentation.scale == CGSize(width: 1, height: 1))
        #expect(buttons.filter(\.isSelected).map(\.tab) == [.home])
        #expect(committedTabs.isEmpty, "Moving the toolbar must cancel without navigation")
    }

    @Test("Removing the SwiftUI anchor cannot keep its UIView alive through presentation state")
    func doesNotRetainRemovedAnchor() {
        let presentation = GlassTabBarPresentation()
        weak var removedAnchor: UIView?
        autoreleasepool {
            let anchor = UIView()
            removedAnchor = anchor
            presentation.coordinateView = anchor
        }
        #expect(removedAnchor == nil)
        #expect(presentation.coordinateView == nil)
    }

    private func expectPoint(_ actual: CGPoint, equals expected: CGPoint) {
        #expect(abs(actual.x - expected.x) < 0.001)
        #expect(abs(actual.y - expected.y) < 0.001)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor
private final class PresentationFixture {
    let window: UIWindow
    let toolbar: UIView
    let visualContainer = UIView()
    let anchor = UIView()
    let presentation = GlassTabBarPresentation()
    let view: GlassTabBarView

    init() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        toolbar = UIView(frame: CGRect(x: (window.bounds.width - 360) / 2, y: 200, width: 360, height: 64))
        view = GlassTabBarView(selection: .home, presentation: presentation)
        window.addSubview(toolbar)
        visualContainer.frame = toolbar.bounds
        anchor.frame = toolbar.bounds
        view.frame = toolbar.bounds
        toolbar.addSubview(anchor)
        toolbar.addSubview(visualContainer)
        visualContainer.addSubview(view)
        presentation.coordinateView = anchor
        configure()
        window.layoutIfNeeded()
        view.layoutIfNeeded()
    }

    func configure() {
        view.updateEnvironment(
            locale: Locale(identifier: "en"),
            contentSizeCategory: .large,
            layoutDirection: .leftToRight,
            layoutAxis: .horizontal,
            reduceMotion: false,
            isEnabled: true
        )
    }
}
