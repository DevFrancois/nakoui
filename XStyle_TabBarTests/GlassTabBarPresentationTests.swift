import SwiftUI
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

    @Test("A press grows the capsule by the dial's amount, and not at all with the grow off")
    func pressesGrowByTheDial() async throws {
        let fixture = try PresentationFixture()
        let recognizer = try #require(fixture.view.gestureRecognizers?.compactMap {
            $0 as? GlassTabBarTouchRecognizer
        }.first)
        let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
        let search = try #require(buttons.first { $0.tab == .search })
        await drainMainQueue()
        let searchCenter = search.convert(CGPoint(x: search.bounds.midX, y: search.bounds.midY), to: fixture.view)

        fixture.presentation.motion = GlassTabBarMotion(grows: false)
        recognizer.onBegin?(searchCenter)
        #expect(fixture.presentation.scale == CGSize(width: 1, height: 1))

        // The fixture's capsule has room on every side for the calm grow.
        fixture.presentation.motion = .calm
        recognizer.onBegin?(searchCenter)
        #expect(fixture.presentation.scale == CGSize(width: 1.02, height: 1.02))
    }

    @Test("The highlight follows the drawn finger continuously across a boundary after the capsule grows")
    func highlightFollowsTheDrawnFingerAcrossABoundary() async throws {
        let fixture = try PresentationFixture()
        let recognizer = try #require(fixture.view.gestureRecognizers?.compactMap {
            $0 as? GlassTabBarTouchRecognizer
        }.first)
        let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
        await drainMainQueue()
        let highlight = try #require(buttons.first?.superview?.subviews.first {
            $0.backgroundColor == UIColor.tertiarySystemFill
        })
        let home = try #require(buttons.first { $0.tab == .home })
        let scanner = try #require(buttons.first { $0.tab == .scanner })
        // The largest grow moves the drawn boundary furthest from the laid-out one.
        fixture.presentation.motion = .original
        let center = fixture.view.bounds.midX
        recognizer.onBegin?(CGPoint(x: center, y: fixture.view.bounds.midY))
        let scale = fixture.presentation.scale.width
        try #require(scale > 1)

        // Where Home meets Scan once SwiftUI has grown the capsule about its center.
        let drawnBoundary = center + (scanner.frame.minX - center) * scale
        for x in [drawnBoundary - 1, drawnBoundary + 1] {
            fixture.view.trackTouch(state: .changed, at: CGPoint(x: x, y: fixture.view.bounds.midY))
            expectPoint(highlight.center,
                        equals: CGPoint(x: center + (x - center) / scale, y: home.center.y))
        }
    }

    @Test("Shimmer confirms a changed tab on release and never runs while a finger is held")
    func shimmerOnlyConfirmsAChangedTabOnRelease() async throws {
        for axis: NSLayoutConstraint.Axis in [.horizontal, .vertical] {
            let fixture = try PresentationFixture(axis: axis)
            let recognizer = try #require(fixture.view.gestureRecognizers?.compactMap {
                $0 as? GlassTabBarTouchRecognizer
            }.first)
            let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
            let scanner = try #require(buttons.first { $0.tab == .scanner })
            let search = try #require(buttons.first { $0.tab == .search })
            let highlight = try #require(scanner.superview?.subviews.first { $0 is GlassTabBarHighlight })
            let shimmer = try #require(highlight.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
            await drainMainQueue()

            recognizer.onBegin?(scanner.center)
            #expect(shimmer.animation(forKey: "shimmer") == nil)
            fixture.view.trackTouch(state: .changed, at: search.center)
            #expect(shimmer.animation(forKey: "shimmer") == nil)
            fixture.view.trackTouch(state: .ended, at: search.center)
            #expect(buttons.filter(\.isSelected).map(\.tab) == [.search])
            #expect(shimmer.animation(forKey: "shimmer") != nil)

            // A new hold interrupts the prior confirmation immediately.
            recognizer.onBegin?(scanner.center)
            #expect(shimmer.animation(forKey: "shimmer") == nil)
            fixture.view.trackTouch(state: .changed, at: search.center)
            #expect(shimmer.animation(forKey: "shimmer") == nil)
            fixture.view.trackTouch(state: .ended, at: search.center)
            #expect(shimmer.animation(forKey: "shimmer") == nil, "Releasing on the selected tab has no change to confirm")

            recognizer.onBegin?(scanner.center)
            fixture.view.trackTouch(state: .cancelled, at: scanner.center)
            #expect(shimmer.animation(forKey: "shimmer") == nil)
            #expect(buttons.filter(\.isSelected).map(\.tab) == [.search])
        }
    }

    @Test("Shimmer follows committed tab order despite reversed drags, release snaps and rapid activations")
    func shimmerDirectionFollowsCommittedTabOrder() async throws {
        for (axis, direction): (NSLayoutConstraint.Axis, UIUserInterfaceLayoutDirection) in [
            (.horizontal, .leftToRight), (.horizontal, .rightToLeft), (.vertical, .leftToRight),
        ] {
            let fixture = try PresentationFixture(axis: axis, direction: direction)
            // Keep the real highlight spring while making finger positions exact.
            fixture.presentation.motion.grows = false
            let recognizer = try #require(fixture.view.gestureRecognizers?.compactMap {
                $0 as? GlassTabBarTouchRecognizer
            }.first)
            let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
            let home = try #require(buttons.first { $0.tab == .home })
            let scanner = try #require(buttons.first { $0.tab == .scanner })
            let profile = try #require(buttons.first { $0.tab == .profile })
            let search = try #require(buttons.first { $0.tab == .search })
            let highlight = try #require(home.superview?.subviews.first { $0 is GlassTabBarHighlight })
            await drainMainQueue()

            let step = axis == .vertical ? CGPoint(x: 0, y: 8)
                : CGPoint(x: direction == .rightToLeft ? -8 : 8, y: 0)
            let forward = direction != .rightToLeft
            let beyondProfile = CGPoint(x: profile.center.x + step.x, y: profile.center.y + step.y)
            recognizer.onBegin?(home.center)
            fixture.view.trackTouch(state: .changed, at: search.center)
            fixture.view.trackTouch(state: .changed, at: beyondProfile)
            fixture.view.trackTouch(state: .ended, at: beyondProfile)
            // The finger reversed and the release snaps backward, but Home → Profile is forward.
            try expectShimmerDirection(in: highlight, axis: axis, forward: forward)

            // Commit again before the first spring or shimmer can settle. This
            // release snaps forward even though Profile → Scan moves backward.
            let beyondScanner = CGPoint(x: scanner.center.x - step.x, y: scanner.center.y - step.y)
            recognizer.onBegin?(profile.center)
            fixture.view.trackTouch(state: .changed, at: beyondScanner)
            fixture.view.trackTouch(state: .ended, at: beyondScanner)
            try expectShimmerDirection(in: highlight, axis: axis, forward: !forward)

            #expect(search.accessibilityActivate())
            try expectShimmerDirection(in: highlight, axis: axis, forward: forward)
            #expect(home.accessibilityActivate())
            try expectShimmerDirection(in: highlight, axis: axis, forward: !forward)
        }
    }

    @Test("One held finger can move, reverse and pause before committing only its final tab")
    func continuousHoldCommitsOnlyOnRelease() async throws {
        for (axis, direction): (NSLayoutConstraint.Axis, UIUserInterfaceLayoutDirection) in [
            (.horizontal, .leftToRight), (.horizontal, .rightToLeft), (.vertical, .leftToRight),
        ] {
            let fixture = try PresentationFixture(axis: axis, direction: direction, reduceMotion: true)
            let recognizer = try #require(fixture.view.gestureRecognizers?.compactMap {
                $0 as? GlassTabBarTouchRecognizer
            }.first)
            let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
            let home = try #require(buttons.first { $0.tab == .home })
            let scanner = try #require(buttons.first { $0.tab == .scanner })
            let profile = try #require(buttons.first { $0.tab == .profile })
            let search = try #require(buttons.first { $0.tab == .search })
            let highlight = try #require(home.superview?.subviews.first { $0 is GlassTabBarHighlight })
            var committedTabs: [RootTab] = []
            fixture.view.onSelect = { committedTabs.append($0) }
            await drainMainQueue()

            recognizer.onBegin?(home.center)
            let withinHome = CGPoint(x: home.center.x + (scanner.center.x - home.center.x) * 0.25,
                                     y: home.center.y + (scanner.center.y - home.center.y) * 0.25)
            for point in [withinHome, profile.center, search.center, scanner.center] {
                fixture.view.trackTouch(state: .changed, at: point)
                expectPoint(highlight.center, equals: point)
                #expect(buttons.filter(\.isSelected).map(\.tab) == [.home])
                #expect(committedTabs.isEmpty, "Moving the held finger must not navigate")
            }
            let scannerSymbol = try #require(scanner.subviews.compactMap { $0 as? UIImageView }.first)
            let homeSymbol = try #require(home.subviews.compactMap { $0 as? UIImageView }.first)
            let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
            #expect(scannerSymbol.tintColor.resolvedColor(with: darkTraits)
                    == UIColor.label.resolvedColor(with: darkTraits))
            #expect(homeSymbol.tintColor.resolvedColor(with: darkTraits)
                    != scannerSymbol.tintColor.resolvedColor(with: darkTraits))

            // A pause and an unchanged parent update must preserve this same hold.
            await drainMainQueue()
            fixture.configure()
            fixture.view.select(.home, animated: false)
            expectPoint(highlight.center, equals: scanner.center)
            let finalPoint = CGPoint(x: profile.center.x + (search.center.x - profile.center.x) * 0.2,
                                     y: profile.center.y + (search.center.y - profile.center.y) * 0.2)
            fixture.view.trackTouch(state: .changed, at: finalPoint)
            expectPoint(highlight.center, equals: finalPoint)
            #expect(committedTabs.isEmpty)

            fixture.view.trackTouch(state: .ended, at: finalPoint)
            #expect(committedTabs == [.profile])
            #expect(buttons.filter(\.isSelected).map(\.tab) == [.profile])
            #expect(highlight.frame == profile.frame)
            fixture.view.trackTouch(state: .ended, at: finalPoint)
            #expect(committedTabs == [.profile], "A completed hold can commit only once")
        }
    }

    @Test("A held finger keeps controlling the highlight off the bar and commits there unless cancelled")
    func heldFingerCanSelectOffBarOrCancel() async throws {
        for (axis, direction): (NSLayoutConstraint.Axis, UIUserInterfaceLayoutDirection) in [
            (.horizontal, .leftToRight), (.horizontal, .rightToLeft), (.vertical, .leftToRight),
        ] {
            let fixture = try PresentationFixture(axis: axis, direction: direction, reduceMotion: true)
            let recognizer = try #require(fixture.view.gestureRecognizers?.compactMap {
                $0 as? GlassTabBarTouchRecognizer
            }.first)
            let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
            let home = try #require(buttons.first { $0.tab == .home })
            let profile = try #require(buttons.first { $0.tab == .profile })
            let search = try #require(buttons.first { $0.tab == .search })
            let highlight = try #require(home.superview?.subviews.first { $0 is GlassTabBarHighlight })
            let isVertical = axis == .vertical
            let outsideSearch = isVertical
                ? CGPoint(x: -150, y: search.center.y) : CGPoint(x: search.center.x, y: -150)
            var committedTabs: [RootTab] = []
            fixture.view.onSelect = { committedTabs.append($0) }
            await drainMainQueue()

            recognizer.onBegin?(outsideSearch)
            fixture.view.trackTouch(state: .changed, at: search.center)
            fixture.view.trackTouch(state: .ended, at: search.center)
            #expect(committedTabs.isEmpty)
            #expect(highlight.frame == home.frame)

            recognizer.onBegin?(home.center)
            fixture.view.trackTouch(state: .changed, at: outsideSearch)
            expectPoint(highlight.center, equals: search.center)
            let low = isVertical ? CGPoint(x: -150, y: -500) : CGPoint(x: -500, y: -150)
            let high = isVertical ? CGPoint(x: -150, y: 1000) : CGPoint(x: 1000, y: -150)
            let lowButton = direction == .rightToLeft ? search : home
            let highButton = direction == .rightToLeft ? home : search
            for (point, button) in [(low, lowButton), (high, highButton)] {
                fixture.view.trackTouch(state: .changed, at: point)
                #expect(highlight.frame == button.frame, "Faraway fingers clamp the fill to the nearest endpoint")
                #expect(committedTabs.isEmpty)
            }
            fixture.view.trackTouch(state: .changed, at: profile.center)
            expectPoint(highlight.center, equals: profile.center)
            fixture.view.trackTouch(state: .changed, at: outsideSearch)
            expectPoint(highlight.center, equals: search.center)
            #expect(committedTabs.isEmpty)
            fixture.view.trackTouch(state: .ended, at: outsideSearch)
            #expect(committedTabs == [.search])

            recognizer.onBegin?(home.center)
            fixture.view.trackTouch(state: .changed, at: low)
            fixture.view.trackTouch(state: .cancelled, at: low)
            fixture.view.trackTouch(state: .ended, at: home.center)
            #expect(committedTabs == [.search])
            #expect(highlight.frame == search.frame)
        }
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

    @Test("A hold survives the bar settling after sliding back and the toolbar zooming it back in")
    func holdsSurviveTheBarsOwnSlide() async throws {
        let fixture = try PresentationFixture()
        let recognizer = try #require(fixture.view.gestureRecognizers?.compactMap {
            $0 as? GlassTabBarTouchRecognizer
        }.first)
        let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
        let search = try #require(buttons.first { $0.tab == .search })
        var committedTabs: [RootTab] = []
        fixture.view.onSelect = { committedTabs.append($0) }
        await drainMainQueue()

        recognizer.onBegin?(search.convert(CGPoint(x: search.bounds.midX, y: search.bounds.midY), to: fixture.view))
        let heldScale = fixture.presentation.scale
        try #require(heldScale.width > 1 && heldScale.height > 1)

        // A spring's last fraction of a point, then a bounce's overshoot: the
        // slide carries the touch anchor and the visuals, not the placement.
        for slide: CGFloat in [0.009, -6] {
            fixture.anchor.frame.origin.y = slide
            fixture.visualContainer.frame.origin.y = slide
            fixture.view.setNeedsLayout()
            fixture.view.layoutIfNeeded()
            await drainMainQueue()
            #expect(fixture.presentation.scale == heldScale, "The bar's own slide must not drop a held finger")
        }

        // The tail of the toolbar zooming the bar back in about its slot's
        // center, as measured in the app: 326 points wide drawn 325.927.
        let zoom = 325.9273472536356 / 326
        fixture.toolbar.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        fixture.view.setNeedsLayout()
        fixture.view.layoutIfNeeded()
        await drainMainQueue()
        #expect(fixture.presentation.scale == heldScale, "The toolbar showing the bar again must not drop a held finger")
        #expect(committedTabs.isEmpty, "Holding must not commit a destination")
    }

    @Test("Narrow proposals keep the vertical bar full width and its tracking anchor aligned")
    func hostedNarrowBarsRetainAValidTrackingAnchor() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for (axis, width): (NSLayoutConstraint.Axis, CGFloat) in [
            (.horizontal, 180), (.horizontal, 176), (.vertical, 60), (.vertical, 48), (.vertical, 44),
        ] {
            let expectedWidth: CGFloat = axis == .vertical ? 60 : width
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: NarrowGlassTabBarFixture(axis: axis, width: width))
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }

            try #require(await eventually {
                host.view.layoutIfNeeded()
                guard let view = self.findBar(in: host.view) else { return false }
                return abs(view.bounds.width - expectedWidth) < 0.5 && view.bounds.height > 0
            }, "The vertical capsule must retain its full width even under the toolbar's compact proposal")
            let view = try #require(findBar(in: host.view))
            let recognizer = try #require(view.gestureRecognizers?.compactMap {
                $0 as? GlassTabBarTouchRecognizer
            }.first)
            let controls = try #require(view.accessibilityElements as? [GlassTabBarButton])
            let home = try #require(controls.first { $0.tab == .home })
            let search = try #require(controls.first { $0.tab == .search })
            await drainMainQueue()
            let selectionFill = try #require(search.superview?.subviews.first {
                $0.backgroundColor == UIColor.tertiarySystemFill
            })
            let restingFrame = view.convert(view.bounds, to: window)
            expectPoint(selectionFill.center, equals: home.center)

            // A mismatched anchor rejects this begin callback. The selection fill
            // must follow the finger even when Reduce Motion suppresses scaling.
            // The outer end clamps to Search's center even as the capsule grows.
            let finger = axis == .vertical
                ? CGPoint(x: search.frame.midX, y: search.frame.maxY - 2)
                : CGPoint(x: search.frame.maxX - 2, y: search.frame.midY)
            recognizer.onBegin?(finger)
            #expect(selectionFill.frame == search.frame)
            #expect(selectionFill.backgroundColor == UIColor.secondarySystemFill,
                    "A valid anchor must move and brighten the fill behind the finger candidate")
            if !UIAccessibility.isReduceMotionEnabled {
                #expect(try await eventually {
                    let pressedFrame = view.convert(view.bounds, to: window)
                    return axis == .vertical ? pressedFrame.height > restingFrame.height + 0.5
                        : pressedFrame.width > restingFrame.width + 0.5
                }, "A valid press must reach the SwiftUI glass at every supported narrow width")
            }
            #expect(controls.filter(\.isSelected).map(\.tab) == [.home])
        }
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

    private func expectShimmerDirection(in highlight: UIView, axis: NSLayoutConstraint.Axis,
                                        forward: Bool) throws {
        let shimmer = try #require(highlight.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
        let group = try #require(shimmer.animation(forKey: "shimmer") as? CAAnimationGroup)
        let sweep = try #require(group.animations?.compactMap { $0 as? CABasicAnimation }.first)
        #expect(sweep.keyPath == (axis == .vertical ? "position.y" : "position.x"))
        let start = try #require(sweep.fromValue as? NSNumber).doubleValue
        let end = try #require(sweep.toValue as? NSNumber).doubleValue
        #expect(forward ? start < 0 && end > 0 : start > 0 && end < 0,
                "The ripple must travel from the previous committed tab toward the new tab")
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

    private func findBar(in view: UIView) -> GlassTabBarView? {
        if let bar = view as? GlassTabBarView { return bar }
        return view.subviews.lazy.compactMap { findBar(in: $0) }.first
    }

    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}

private struct NarrowGlassTabBarFixture: View {
    let axis: NSLayoutConstraint.Axis
    let width: CGFloat

    var body: some View {
        GlassTabBar(selection: .constant(.home), layoutAxis: axis)
            .frame(width: width)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dynamicTypeSize(.large)
            .environment(\.locale, Locale(identifier: "en"))
            // An empty store, so motion dials left set in the app don't reach the bar.
            .defaultAppStorage(UserDefaults(suiteName: "GlassTabBarPresentationTests")!)
    }
}

@MainActor
private final class PresentationFixture {
    let window: UIWindow
    let toolbar: UIView
    let visualContainer = UIView()
    let anchor = UIView()
    /// Where the toolbar placed the bar; the bar's own slide moves only the
    /// touch anchor and the visual container.
    let placement = UIView()
    let presentation = GlassTabBarPresentation()
    let view: GlassTabBarView
    let axis: NSLayoutConstraint.Axis
    let direction: UIUserInterfaceLayoutDirection
    let reduceMotion: Bool

    init(axis: NSLayoutConstraint.Axis = .horizontal,
         direction: UIUserInterfaceLayoutDirection = .leftToRight,
         reduceMotion: Bool = false) throws {
        self.axis = axis
        self.direction = direction
        self.reduceMotion = reduceMotion
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        let size = axis == .vertical ? CGSize(width: 60, height: 244) : CGSize(width: 360, height: 64)
        toolbar = UIView(frame: CGRect(x: (window.bounds.width - size.width) / 2, y: 200,
                                      width: size.width, height: size.height))
        view = GlassTabBarView(selection: .home, presentation: presentation)
        window.addSubview(toolbar)
        visualContainer.frame = toolbar.bounds
        anchor.frame = toolbar.bounds
        placement.frame = toolbar.bounds
        view.frame = toolbar.bounds
        toolbar.addSubview(placement)
        toolbar.addSubview(anchor)
        toolbar.addSubview(visualContainer)
        visualContainer.addSubview(view)
        presentation.coordinateView = anchor
        presentation.placementView = placement
        configure()
        window.layoutIfNeeded()
        view.layoutIfNeeded()
    }

    func configure() {
        view.updateEnvironment(
            locale: Locale(identifier: "en"),
            contentSizeCategory: .large,
            layoutDirection: direction,
            layoutAxis: axis,
            reduceMotion: reduceMotion,
            isEnabled: true
        )
    }
}
