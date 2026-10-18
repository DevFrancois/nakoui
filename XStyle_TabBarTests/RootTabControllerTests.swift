import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct RootTabControllerTests {
    @Test("Tab direction follows visible order with fixed travel, including skipped tabs")
    func directionUsesCommittedOrderAndAxis() {
        let forward = RootTabAnimator.Motion(from: .home, to: .profile, axis: .horizontal, isRightToLeft: false)
        #expect(forward.x == 30 && forward.y == 0)
        let reverse = RootTabAnimator.Motion(from: .search, to: .home, axis: .horizontal, isRightToLeft: false)
        #expect(reverse.x == -30 && reverse.y == 0)
        let rtl = RootTabAnimator.Motion(from: .home, to: .search, axis: .horizontal, isRightToLeft: true)
        #expect(rtl.x == -30 && rtl.y == 0)
        let vertical = RootTabAnimator.Motion(from: .home, to: .search, axis: .vertical, isRightToLeft: true)
        #expect(vertical.x == 0 && vertical.y == 30)
        let unchanged = RootTabAnimator.Motion(from: .home, to: .home, axis: .vertical, isRightToLeft: false)
        #expect(unchanged.x == 0 && unchanged.y == 0)
    }

    @Test("Programmatic tab selection invokes the native transition delegate")
    func programmaticSelectionUsesDelegate() async throws {
        try await withController { controller, pages in
            let requests = controller.transitionRequestCount
            update(controller, selection: .profile)
            #expect(controller.transitionRequestCount == requests + 1)
            #expect(controller.selectedViewController === pages[2])
            #expect(controller.activeAnimator?.isAnimated == true)
            #expect(controller.activeAnimator?.motion.x == 30)
            #expect(controller.isTabBarHidden)
            #expect(!pages[0].view.isUserInteractionEnabled)
            #expect(pages[0].view.accessibilityElementsHidden)
            #expect(pages[2].view.isUserInteractionEnabled)
            #expect(!pages[2].view.accessibilityElementsHidden)
            try await Task.sleep(for: .milliseconds(380))
            #expect(controller.activeAnimator == nil)
            #expect(pages[2].view.transform == .identity)
            #expect(pages[2].view.alpha == 1)
        }
    }

    @Test("Repeated same-selection updates do not interrupt a running transition")
    func identicalUpdatesPreserveTransition() async throws {
        try await withController { controller, _ in
            update(controller, selection: .scanner)
            let animator = try #require(controller.activeAnimator)
            let requests = controller.transitionRequestCount
            update(controller, selection: .scanner)
            #expect(controller.activeAnimator === animator)
            #expect(controller.transitionRequestCount == requests)
        }
    }

    @Test("Rapid selections finish native contexts and immediately select the last destination")
    func rapidReversalDoesNotQueueSelections() async throws {
        try await withController { controller, pages in
            let requests = controller.transitionRequestCount
            update(controller, selection: .profile)
            try await Task.sleep(for: .milliseconds(60))
            update(controller, selection: .search)
            #expect(controller.committedSelection == .search)
            #expect(controller.selectedViewController === pages[3])
            try await Task.sleep(for: .milliseconds(40))
            update(controller, selection: .home)
            #expect(controller.committedSelection == .home)
            #expect(controller.selectedViewController === pages[0])
            #expect(controller.activeAnimator?.motion.x == -30)
            #expect(controller.transitionRequestCount == requests + 3)
            try await Task.sleep(for: .milliseconds(380))
            #expect(controller.activeAnimator == nil)
            #expect(controller.selectedViewController === pages[0])
            #expect(pages.allSatisfy { $0.view.transform == .identity && $0.view.alpha == 1 })
        }
    }

    @Test("Changing the toolbar axis settles motion and uses the vertical axis next")
    func axisChangeSettlesImmediately() async throws {
        try await withController { controller, pages in
            update(controller, selection: .profile)
            update(controller, selection: .profile, axis: .vertical)
            #expect(controller.activeAnimator == nil)
            #expect(pages[2].view.transform == .identity)
            update(controller, selection: .home, axis: .vertical)
            #expect(controller.committedSelection == .home)
            // UIKit supplies a just-requested transition context on its next
            // callback turn. The settled context must finish before another
            // native animation starts, without losing the latest selection.
            try await Task.sleep(for: .milliseconds(50))
            #expect(controller.selectedViewController === pages[0])
            #expect(controller.activeAnimator?.motion.x == 0)
            #expect(controller.activeAnimator?.motion.y == -30)
        }
    }

    @Test("Selections before UIKit starts the first animation coalesce to the latest destination")
    func selectionsBeforeContextArrivesStaySynchronized() async throws {
        try await withController { controller, pages in
            update(controller, selection: .scanner)
            update(controller, selection: .search)
            update(controller, selection: .profile)
            #expect(controller.committedSelection == .profile)
            try await Task.sleep(for: .milliseconds(50))
            #expect(controller.selectedViewController === pages[2])
            // Direction follows the previous committed Search selection, even
            // though the superseded Search page never reached a display frame.
            #expect(controller.activeAnimator?.motion.x == -30)
            try await Task.sleep(for: .milliseconds(380))
            #expect(controller.activeAnimator == nil)
            #expect(controller.selectedViewController === pages[2])
            #expect(pages.allSatisfy { $0.view.transform == .identity && $0.view.alpha == 1 })
        }
    }

    @Test("A coalesced no-op discards its snapshot before the next ordinary transition")
    func coalescedSelectionDoesNotReuseAStaleSnapshot() async throws {
        try await withController { controller, pages in
            update(controller, selection: .scanner)
            update(controller, selection: .home)
            update(controller, selection: .scanner)
            try await Task.sleep(for: .milliseconds(80))
            #expect(controller.selectedViewController === pages[1])
            #expect(controller.activeAnimator == nil)

            update(controller, selection: .profile)
            let animator = try #require(controller.activeAnimator)
            #expect(!animator.usesPresentationSnapshot,
                    "A new ordinary transition must animate the real Scan page, not an old Home snapshot")
        }
    }

    @Test("Enabling Reduce Motion while a native context is pending prevents the next animation")
    func reduceMotionAppliesToPendingSelections() async throws {
        try await withController { controller, pages in
            update(controller, selection: .scanner)
            update(controller, selection: .search)
            update(controller, selection: .search, reduceMotion: true)
            #expect(controller.committedSelection == .search)
            try await Task.sleep(for: .milliseconds(80))
            #expect(controller.selectedViewController === pages[3])
            #expect(controller.activeAnimator == nil)
            #expect(pages[3].view.transform == .identity)
            #expect(pages[3].view.alpha == 1)
        }
    }

    @Test("An animator settled before its native context arrives is released")
    func prestartSettlementReleasesAnimator() async throws {
        try await withController { controller, _ in
            update(controller, selection: .scanner)
            weak let interrupted = controller.activeAnimator
            #expect(interrupted != nil)
            update(controller, selection: .scanner, axis: .vertical)
            try await Task.sleep(for: .milliseconds(380))
            #expect(controller.activeAnimator == nil)
            #expect(interrupted == nil,
                    "Unstarted property-animator closures must not retain their transition animator")
        }
    }

    @Test("Reduce Motion selects without page deformation")
    func reduceMotionSwitchesImmediately() async throws {
        try await withController { controller, pages in
            update(controller, selection: .search, reduceMotion: true)
            #expect(controller.selectedViewController === pages[3])
            #expect(controller.activeAnimator?.isAnimated != true)
            #expect(pages[3].view.transform == .identity)
            #expect(pages[3].view.alpha == 1)
        }
    }

    private func update(
        _ controller: RootTabController,
        selection: RootTab,
        axis: NSLayoutConstraint.Axis = .horizontal,
        reduceMotion: Bool = false
    ) {
        controller.update(selection: selection, layoutAxis: axis, isRightToLeft: false,
                          reduceMotion: reduceMotion, isEnabled: true, isVisible: true, animated: true)
    }

    private func withController(
        _ body: (RootTabController, [UIViewController]) async throws -> Void
    ) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let pages = RootTab.allCases.map { _ in UIViewController() }
        for page in pages { page.view.backgroundColor = .systemBackground }
        let controller = RootTabController(viewControllers: pages, selection: .home)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        defer {
            controller.update(selection: controller.committedSelection, layoutAxis: .horizontal,
                              isRightToLeft: false, reduceMotion: true, isEnabled: false,
                              isVisible: false, animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }
        try await Task.sleep(for: .milliseconds(50))
        try await body(controller, pages)
    }
}
