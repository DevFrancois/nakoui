import SwiftUI
import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct HomePagerLayoutTests {
    @Test("The same pager resizes its pages when a wide display folds and reopens")
    func foldingResizesRenderedPagesWithoutReplacingTheirScrollViews() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        defer { window.isHidden = true }

        let pager = PagerState()
        let host = UIHostingController(rootView: PagerLayoutFixture(pager: pager))
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        host.additionalSafeAreaInsets.right = 64

        func resize(to width: CGFloat) {
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 700)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        resize(to: 736)
        try #require(await eventually {
            scrollViews(in: host.view).count == AppTab.allCases.count + 1
                && abs(pager.viewportWidth - 736) < 0.5
        })
        let scrolls = scrollViews(in: host.view)
        let horizontal = try #require(scrolls.first)
        let pages = scrolls.dropFirst().sorted {
            $0.convert($0.bounds, to: horizontal).minX < $1.convert($1.bounds, to: horizontal).minX
        }
        let originalPageIDs = pages.map(ObjectIdentifier.init)
        #expect(abs(horizontal.contentSize.width - 736 * CGFloat(pages.count)) < 0.5)

        // A nonzero category also catches a stale page stride after resizing.
        pager.setReduceMotion(true)
        pager.select(.videos)
        try #require(await eventually { pager.selectedTab == .videos && pager.isAtRest })
        let videoPage = pages[AppTab.videos.index]
        videoPage.setContentOffset(CGPoint(x: 0, y: 320), animated: false)
        try #require(await eventually { abs(videoPage.contentOffset.y - 320) < 0.5 })

        for width: CGFloat in [466, 736, 466] {
            resize(to: width)
            try #require(await eventually {
                abs(horizontal.bounds.width - width) < 0.5
                    && abs(horizontal.contentSize.width - width * CGFloat(pages.count)) < 0.5
                    && pages.allSatisfy { abs($0.bounds.width - width) < 0.5 }
                    && pager.isAtRest
            }, "All rendered pages must adopt the new viewport width \(width)")

            #expect(Set(scrollViews(in: host.view).dropFirst().map(ObjectIdentifier.init)) == Set(originalPageIDs))
            #expect(pager.selectedTab == .videos)
            #expect(abs(horizontal.contentOffset.x + horizontal.adjustedContentInset.left - width) < 0.5)
            // Lazy rows can refine their height estimates during resizing.
            // Check that the existing scroll position survives without
            // requiring an identical pixel offset after that refinement.
            #expect(videoPage.contentOffset.y + videoPage.adjustedContentInset.top > 200)
        }
    }

    @Test("Animated distant taps and the latest queued tap keep working after repeated folds")
    func animatedDistantTapsAfterRepeatedFolds() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        defer { window.isHidden = true }

        let pager = PagerState()
        let host = UIHostingController(rootView: PagerLayoutFixture(pager: pager))
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        host.additionalSafeAreaInsets.right = 64

        for width: CGFloat in [736, 466, 736, 466] {
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 700)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try #require(await eventually {
                abs(pager.viewportWidth - width) < 0.5 && pager.isAtRest
                    && scrollViews(in: host.view).count == AppTab.allCases.count + 1
            })
            let horizontal = try #require(scrollViews(in: host.view).first)
            #expect(abs(horizontal.contentSize.width - width * CGFloat(AppTab.allCases.count)) < 0.5)
            #expect(pager.selectedTab == .bookmarks)

            // These are real SwiftUI ScrollPosition animations, with their
            // native geometry and phase callbacks driving PagerState.
            pager.setReduceMotion(false)
            pager.select(.quizz)
            #expect(pager.tapTransition?.destination == .quizz)
            try #require(await eventually {
                let offset = horizontal.contentOffset.x + horizontal.adjustedContentInset.left
                return pager.phase == .animating && offset > 1 && offset < 4 * width - 1
            }, "The distant jump must animate through the rendered scroll view at width \(width)")

            pager.select(.articles)
            pager.select(.likes)
            #expect(pager.pendingTab == .likes)
            try #require(await eventually { pager.selectedTab == .likes && pager.isAtRest },
                         "The latest queued tap must complete after resizing to \(width)")
            #expect(pager.highlightedTab == .likes)
            #expect(pager.tapTransition == nil)
            #expect(pager.pendingTab == nil)
            #expect(abs(horizontal.contentOffset.x + horizontal.adjustedContentInset.left - 3 * width) < 0.5)

            // A second distant transition proves the completed queue did not
            // leave hit testing or the pager's state locked.
            pager.select(.bookmarks)
            try #require(await eventually { pager.selectedTab == .bookmarks && pager.isAtRest })
            #expect(pager.highlightedTab == .bookmarks)
            #expect(pager.tapTransition == nil)
            #expect(abs(horizontal.contentOffset.x + horizontal.adjustedContentInset.left) < 0.5)
        }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        let ownScrollView = (view as? UIScrollView).map { [$0] } ?? []
        return ownScrollView + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        var consecutiveMatches = 0
        for _ in 0..<150 {
            try await Task.sleep(for: .milliseconds(20))
            consecutiveMatches = condition() ? consecutiveMatches + 1 : 0
            if consecutiveMatches == 2 { return true }
        }
        return false
    }
}

private struct PagerLayoutFixture: View {
    let pager: PagerState
    private let logoCollapse = LogoCollapse()
    private let taskList = ForYouTaskList()
    @Namespace private var zoomNamespace

    var body: some View {
        HomePager(
            pager: pager,
            logoCollapse: logoCollapse,
            taskList: taskList,
            topInset: 0,
            zoomNamespace: zoomNamespace,
            onUpdate: {}
        )
    }
}
