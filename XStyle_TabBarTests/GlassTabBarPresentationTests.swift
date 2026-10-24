import SwiftUI
import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct GlassTabBarPresentationTests {
    @Test("Available reflection factories build a working portal and accept only an independent source")
    func reflectionUsesAnIndependentSource() throws {
        // The experimental renderer intentionally disappears on runtimes that
        // do not provide these classes. Present factories must not be rejected
        // just because their optional metadata differs between macOS and iOS.
        guard NSClassFromString("CAPortalLayer") != nil,
              NSClassFromString("CAFilter") != nil else { return }
        let fixture = try PresentationFixture()
        let glass = try #require(fixture.view.subviews.compactMap { $0 as? UIVisualEffectView }.first)
        let reflection = try #require(glass.contentView.layer.sublayers?.compactMap {
            $0 as? GlassTabBarReflectionLayer
        }.first)
        let portal = try #require(reflection.sublayers?.first { $0.name == "tabBar.reflection.portal" })
        #expect(portal.filters?.count == 3)
        #expect(reflection.isHidden)

        let source = UIView(frame: fixture.window.bounds)
        fixture.window.addSubview(source)
        fixture.view.setReflectionSource(source)
        #expect(!reflection.isHidden)

        // Capturing an ancestor would feed the reflection back into itself.
        fixture.view.setReflectionSource(fixture.visualContainer)
        #expect(reflection.isHidden)
        fixture.view.setReflectionSource(source)
        #expect(!reflection.isHidden)
        fixture.view.setReflectionSource(nil)
        #expect(reflection.isHidden)
    }

    @Test("Native interaction belongs to the whole capsule and respects Reduce Motion")
    func nativeInteractionBelongsToTheWholeCapsule() throws {
        for axis: NSLayoutConstraint.Axis in [.horizontal, .vertical] {
            for reduceMotion in [false, true] {
                let fixture = try PresentationFixture(axis: axis, reduceMotion: reduceMotion)
                fixture.view.updateGlass(.dark, interactive: true)
                let glass = try #require(fixture.view.subviews.compactMap { $0 as? UIVisualEffectView }.first)
                let effect = try #require(glass.effect as? UIGlassEffect)
                let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
                #expect(effect.isInteractive == !reduceMotion)
                #expect(glass.bounds == fixture.view.bounds)
                #expect(buttons.allSatisfy { $0.isDescendant(of: glass.contentView) },
                        "Native feedback must carry the menu content, not a separate selection-only surface")
                #expect(fixture.view.hitTest(CGPoint(x: 20, y: 20), with: nil) === glass.contentView)
            }
        }
    }

    @Test("The capsule material stays constant while a held finger previews and commits tabs")
    func materialColorRemainsStableWhileTracking() async throws {
        for axis: NSLayoutConstraint.Axis in [.horizontal, .vertical] {
            let fixture = try PresentationFixture(axis: axis)
            fixture.view.updateGlass(.dark, interactive: true)
            let glass = try #require(fixture.view.subviews.compactMap { $0 as? UIVisualEffectView }.first)
            let backing = try #require(glass.contentView.subviews.first {
                $0.layer.name == "tabBar.materialBacking"
            })
            let color = try #require(backing.backgroundColor)
            let recognizer = try #require(fixture.view.gestureRecognizers?.compactMap {
                $0 as? GlassTabBarTouchRecognizer
            }.first)
            let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
            let home = try #require(buttons.first { $0.tab == .home })
            let search = try #require(buttons.first { $0.tab == .search })
            await drainMainQueue()

            recognizer.onBegin?(home.center)
            #expect(backing.backgroundColor == color)
            for button in buttons {
                fixture.view.trackTouch(state: .changed, at: button.center)
                #expect(backing.backgroundColor == color)
            }
            // SwiftUI may refresh the appearance without ending the hold.
            fixture.view.updateGlass(.dark, interactive: true)
            #expect(backing.backgroundColor == color)
            fixture.view.trackTouch(state: .ended, at: search.center)
            #expect(backing.backgroundColor == color)
            #expect((glass.effect as? UIGlassEffect)?.isInteractive == true)
        }
    }

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

        // Native glass can transform the visual subtree; the sibling anchor stays put.
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

    @Test("The highlight covers the tab beneath a physical finger after native visual scaling")
    func highlightCoversTheDrawnTabAcrossABoundary() async throws {
        for (axis, direction): (NSLayoutConstraint.Axis, UIUserInterfaceLayoutDirection) in [
            (.horizontal, .leftToRight), (.horizontal, .rightToLeft), (.vertical, .leftToRight),
        ] {
            let fixture = try PresentationFixture(axis: axis, direction: direction)
            let recognizer = try #require(fixture.view.gestureRecognizers?.compactMap {
                $0 as? GlassTabBarTouchRecognizer
            }.first)
            let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
            let home = try #require(buttons.first { $0.tab == .home })
            let scanner = try #require(buttons.first { $0.tab == .scanner })
            let highlight = try #require(home.superview?.subviews.first { $0 is GlassTabBarHighlight })
            await drainMainQueue()

            recognizer.onBegin?(home.center)
            // Native UIKit glass can deform the controls inside the unchanged root.
            let content = try #require(home.superview)
            content.transform = CGAffineTransform(scaleX: 1.08, y: 1.06)
            let boundary = CGPoint(x: (home.center.x + scanner.center.x) / 2,
                                   y: (home.center.y + scanner.center.y) / 2)
            let drawnBoundary = content.convert(boundary, to: fixture.window)
            let step = axis == .vertical ? CGPoint(x: 0, y: 1)
                : CGPoint(x: direction == .rightToLeft ? -1 : 1, y: 0)
            for (offset, tab): (CGFloat, GlassTabBarButton) in [(-1, home), (1, scanner)] {
                let physicalPoint = CGPoint(x: drawnBoundary.x + step.x * offset,
                                            y: drawnBoundary.y + step.y * offset)
                let localPoint = fixture.view.convert(physicalPoint, from: fixture.window)
                fixture.view.trackTouch(state: .changed, at: localPoint)
                #expect(highlight.frame == tab.frame, "Use UIKit's transformed local point without applying another scale")
                #expect(buttons.filter(\.isSelected).map(\.tab) == [.home])
            }
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
            let shimmer = try #require(findShimmer(in: highlight.layer))
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

    @Test("Shimmer follows committed tab order despite reversed drags and rapid activations")
    func shimmerDirectionFollowsCommittedTabOrder() async throws {
        for (axis, direction): (NSLayoutConstraint.Axis, UIUserInterfaceLayoutDirection) in [
            (.horizontal, .leftToRight), (.horizontal, .rightToLeft), (.vertical, .leftToRight),
        ] {
            let fixture = try PresentationFixture(axis: axis, direction: direction)
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
            // The finger reversed from Search, but Home → Profile is forward.
            try expectShimmerDirection(in: highlight, axis: axis, forward: forward)

            // Commit again before the first spring or shimmer can settle.
            // Profile → Scan must use the new committed origin.
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

    @Test("A held highlight stays on each tab through finger jitter and commits only on release")
    func heldHighlightSnapsByTabAndCommitsOnlyOnRelease() async throws {
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
            for (fraction, tab): (CGFloat, GlassTabBarButton) in [
                (0.15, home), (0.49, home), (0.2, home),
                (0.51, scanner), (0.7, scanner), (0.55, scanner),
            ] {
                let point = CGPoint(x: home.center.x + (scanner.center.x - home.center.x) * fraction,
                                    y: home.center.y + (scanner.center.y - home.center.y) * fraction)
                fixture.view.trackTouch(state: .changed, at: point)
                #expect(highlight.frame == tab.frame, "The fill must stay on the tab until the finger crosses the midpoint")
                #expect(buttons.filter(\.isSelected).map(\.tab) == [.home])
                #expect(committedTabs.isEmpty)
            }
            for tab in [profile, search, scanner] {
                fixture.view.trackTouch(state: .changed, at: tab.center)
                #expect(highlight.frame == tab.frame)
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
            #expect(highlight.frame == profile.frame)
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

    @Test("Appearance edits preserve a held preview and release, and resetting restores default colors")
    func appearanceEditsPreserveTrackingAndRestoreDefaults() async throws {
        let fixture = try PresentationFixture(axis: .vertical, reduceMotion: true)
        fixture.view.updateAppearance(.light, defaults: .light)
        let recognizer = try #require(fixture.view.gestureRecognizers?.compactMap {
            $0 as? GlassTabBarTouchRecognizer
        }.first)
        let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
        let identities = buttons.map(ObjectIdentifier.init)
        let frames = buttons.map(\.frame)
        let home = try #require(buttons.first { $0.tab == .home })
        let scanner = try #require(buttons.first { $0.tab == .scanner })
        let homeSymbol = try #require(home.subviews.compactMap { $0 as? UIImageView }.first)
        let scannerSymbol = try #require(scanner.subviews.compactMap { $0 as? UIImageView }.first)
        let highlight = try #require(home.superview?.subviews.first { $0 is GlassTabBarHighlight })
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let originalSelected = homeSymbol.tintColor.resolvedColor(with: traits)
        let originalInactive = scannerSymbol.tintColor.resolvedColor(with: traits)
        let originalFill = try #require(highlight.backgroundColor).resolvedColor(with: traits)
        var committedTabs: [RootTab] = []
        fixture.view.onSelect = { committedTabs.append($0) }
        await drainMainQueue()

        recognizer.onBegin?(home.center)
        fixture.view.trackTouch(state: .changed, at: scanner.center)
        #expect(highlight.frame == scanner.frame)

        var appearance = GlassTabBarAppearance.light
        appearance.selectedIconColor = .init(red: 0.9, green: 0.15, blue: 0.2)
        appearance.inactiveIconColor = .init(red: 0.1, green: 0.5, blue: 0.4)
        appearance.inactiveIconOpacity = 0.7
        appearance.selectionColor = .init(red: 0.2, green: 0.3, blue: 0.4)
        appearance.selectionOpacity = 0.2
        appearance.trackingSelectionOpacity = 0.4
        fixture.view.updateAppearance(appearance, defaults: .light)
        fixture.view.layoutIfNeeded()

        let updatedButtons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
        #expect(updatedButtons.map(ObjectIdentifier.init) == identities)
        #expect(updatedButtons.map(\.frame) == frames)
        #expect(buttons.filter(\.isSelected).map(\.tab) == [.home])
        #expect(buttons.filter { $0.accessibilityTraits.contains(.selected) }.map(\.tab) == [.home])
        #expect(highlight.frame == scanner.frame, "Editing appearance must preserve the active preview")
        #expect(scannerSymbol.tintColor == appearance.selectedIconColor.uiColor())
        #expect(homeSymbol.tintColor == appearance.inactiveIconColor.uiColor(opacity: appearance.inactiveIconOpacity))
        #expect(highlight.backgroundColor == appearance.selectionColor.uiColor(opacity: appearance.trackingSelectionOpacity))
        #expect(committedTabs.isEmpty)

        fixture.view.trackTouch(state: .ended, at: scanner.center)
        fixture.view.trackTouch(state: .ended, at: scanner.center)
        #expect(committedTabs == [.scanner], "The original hold must commit its preview exactly once")
        #expect(buttons.filter(\.isSelected).map(\.tab) == [.scanner])
        #expect(highlight.backgroundColor == appearance.selectionColor.uiColor(opacity: appearance.selectionOpacity))

        fixture.view.updateAppearance(.light, defaults: .light)
        #expect(scannerSymbol.tintColor.resolvedColor(with: traits) == originalSelected)
        #expect(homeSymbol.tintColor.resolvedColor(with: traits) == originalInactive)
        #expect(highlight.backgroundColor?.resolvedColor(with: traits) == originalFill)
        #expect(highlight.frame == scanner.frame)
        #expect(buttons.filter(\.isSelected).map(\.tab) == [.scanner])
        #expect(committedTabs == [.scanner], "Resetting appearance must not navigate")
    }

    @Test("A hold survives repeated SwiftUI updates and scaling, then cancels when the toolbar moves")
    func holdsSurviveVisualUpdatesButNotPlacementChanges() async throws {
        let fixture = try PresentationFixture()
        let recognizer = try #require(fixture.view.gestureRecognizers?.compactMap {
            $0 as? GlassTabBarTouchRecognizer
        }.first)
        let buttons = try #require(fixture.view.accessibilityElements as? [GlassTabBarButton])
        let home = try #require(buttons.first { $0.tab == .home })
        let search = try #require(buttons.first { $0.tab == .search })
        let highlight = try #require(home.superview?.subviews.first { $0 is GlassTabBarHighlight })
        var committedTabs: [RootTab] = []
        fixture.view.onSelect = { committedTabs.append($0) }
        await drainMainQueue()

        let searchCenter = search.convert(CGPoint(x: search.bounds.midX, y: search.bounds.midY),
                                          to: fixture.view)
        let physicalFinger = fixture.view.convert(searchCenter, to: fixture.window)
        recognizer.onBegin?(searchCenter)

        fixture.configure()
        fixture.view.select(.home, animated: false)
        fixture.visualContainer.transform = CGAffineTransform(scaleX: 1.04, y: 1.03)
        fixture.view.setNeedsLayout()
        fixture.view.layoutIfNeeded()
        await drainMainQueue()

        fixture.view.trackTouch(state: .changed, at: fixture.view.convert(physicalFinger, from: fixture.window))
        #expect(highlight.frame == search.frame, "Visual scaling and unchanged parent updates must preserve the hold")
        #expect(buttons.filter(\.isSelected).map(\.tab) == [.home])
        #expect(committedTabs.isEmpty, "Holding must not commit a destination")

        fixture.toolbar.center.y += 40
        fixture.view.setNeedsLayout()
        fixture.view.layoutIfNeeded()
        await drainMainQueue()

        #expect(highlight.frame == home.frame, "Real toolbar movement must cancel the preview")
        fixture.view.trackTouch(state: .ended, at: fixture.view.convert(physicalFinger, from: fixture.window))
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
        let highlight = try #require(search.superview?.subviews.first { $0 is GlassTabBarHighlight })
        var committedTabs: [RootTab] = []
        fixture.view.onSelect = { committedTabs.append($0) }
        await drainMainQueue()

        let physicalFinger = fixture.view.convert(search.center, to: fixture.window)
        recognizer.onBegin?(search.center)

        // A spring's last fraction of a point, then a bounce's overshoot: the
        // slide carries the touch anchor and the visuals, not the placement.
        for slide: CGFloat in [0.009, -6] {
            fixture.anchor.frame.origin.y = slide
            fixture.visualContainer.frame.origin.y = slide
            fixture.view.setNeedsLayout()
            fixture.view.layoutIfNeeded()
            await drainMainQueue()
            fixture.view.trackTouch(state: .changed, at: fixture.view.convert(physicalFinger, from: fixture.window))
            #expect(highlight.frame == search.frame, "The bar's own slide must not drop a held finger")
        }

        // The tail of the toolbar zooming the bar back in about its slot's
        // center, as measured in the app: 326 points wide drawn 325.927.
        let zoom = 325.9273472536356 / 326
        fixture.toolbar.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        fixture.view.setNeedsLayout()
        fixture.view.layoutIfNeeded()
        await drainMainQueue()
        fixture.view.trackTouch(state: .changed, at: fixture.view.convert(physicalFinger, from: fixture.window))
        #expect(highlight.frame == search.frame, "The toolbar showing the bar again must not drop a held finger")
        #expect(committedTabs.isEmpty, "Holding must not commit a destination")
        fixture.view.trackTouch(state: .ended, at: fixture.view.convert(physicalFinger, from: fixture.window))
        #expect(committedTabs == [.search], "The original hold must still commit when the finger lifts")
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
                $0 is GlassTabBarHighlight
            })
            expectPoint(selectionFill.center, equals: home.center)
            let restingColor = selectionFill.backgroundColor

            // A mismatched anchor rejects this begin callback. The selection fill
            // must still preview the finger's tab at every supported width.
            let finger = axis == .vertical
                ? CGPoint(x: search.frame.midX, y: search.frame.maxY - 2)
                : CGPoint(x: search.frame.maxX - 2, y: search.frame.midY)
            recognizer.onBegin?(finger)
            #expect(selectionFill.frame == search.frame)
            #expect(selectionFill.backgroundColor != restingColor,
                    "A valid anchor must move and brighten the fill behind the finger candidate")
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
        let shimmer = try #require(findShimmer(in: highlight.layer))
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

    private func findShimmer(in layer: CALayer) -> CAGradientLayer? {
        if let gradient = layer as? CAGradientLayer, gradient.name == "tabBar.releaseShimmer" { return gradient }
        return layer.sublayers?.lazy.compactMap { findShimmer(in: $0) }.first
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
