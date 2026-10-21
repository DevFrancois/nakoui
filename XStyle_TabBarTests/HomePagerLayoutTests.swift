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

    @Test("The full-width pager follows changing safe areas without replacing pages")
    func safeAreaChangesPreserveFullWidthPagesAndHeaderLayout() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        defer { window.isHidden = true }

        let pager = PagerState()
        let host = UIHostingController(rootView: PagerHeaderLayoutFixture(pager: pager))
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        host.view.frame = CGRect(x: 0, y: 0, width: 736, height: 700)
        host.additionalSafeAreaInsets.right = 80
        host.view.layoutIfNeeded()

        try #require(await eventually {
            scrollViews(in: host.view).count == AppTab.allCases.count + 1
                && abs(pager.viewportWidth - 736) < 0.5
        })
        let horizontal = try #require(scrollViews(in: host.view).first)
        let pages = scrollViews(in: host.view).dropFirst().sorted {
            $0.convert($0.bounds, to: horizontal).minX < $1.convert($1.bounds, to: horizontal).minX
        }
        let originalPageIDs = Set(pages.map(ObjectIdentifier.init))
        let header = try #require(view(withIdentifier: LayoutMarker.headerIdentifier, in: host.view))

        pager.setReduceMotion(true)
        pager.select(.videos)
        try #require(await eventually { pager.selectedTab == .videos && pager.isAtRest })
        let videoPage = pages[AppTab.videos.index]
        let headerBottom = header.convert(header.bounds, to: host.view).maxY
        let contentTop = videoPage.convert(CGPoint.zero, to: host.view).y
        #expect(contentTop >= headerBottom - 0.5, "The native safe-area bar must keep the first row below the header")
        #expect(contentTop <= headerBottom + 1, "The header must be reserved once, without duplicating its inset")

        func validateLayout(after inset: UIEdgeInsets) async throws {
            host.additionalSafeAreaInsets = inset
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try #require(await eventually {
                abs(horizontal.bounds.width - 736) < 0.5
                    && abs(horizontal.contentSize.width - 736 * CGFloat(pages.count)) < 0.5
                    && pages.allSatisfy { abs($0.bounds.width - 736) < 0.5 }
                    && abs(videoPage.adjustedContentInset.left - host.view.safeAreaInsets.left) < 0.5
                    && abs(videoPage.adjustedContentInset.right - host.view.safeAreaInsets.right) < 0.5
                    && pager.isAtRest
            }, "The full-width viewport and independent content insets must follow \(inset)")

            #expect(Set(scrollViews(in: host.view).dropFirst().map(ObjectIdentifier.init)) == originalPageIDs)
            #expect(pager.selectedTab == .videos)
            #expect(pager.highlightedTab == .videos)
            #expect(abs(horizontal.contentOffset.x + horizontal.adjustedContentInset.left - 736) < 0.5)
            let visibleContent = videoPage.convert(videoPage.bounds.inset(by: videoPage.adjustedContentInset), to: host.view)
            let updatedHeaderBottom = header.convert(header.bounds, to: host.view).maxY
            #expect(visibleContent.minY >= updatedHeaderBottom - 0.5)
        }

        // Safe-area changes must keep the native header and full-width pages
        // aligned even when the viewport's dimensions stay the same.
        for inset in [
            UIEdgeInsets(top: 0, left: 96, bottom: 0, right: 0),
            UIEdgeInsets(top: 0, left: 32, bottom: 0, right: 112),
            UIEdgeInsets(top: 40, left: 0, bottom: 24, right: 64),
            .zero,
        ] {
            try await validateLayout(after: inset)
        }
    }

    @Test("A feed scrolled through SwiftUI preserves its post when safe areas change")
    func swiftUIScrollPositionSurvivesSafeAreaChanges() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        defer { window.isHidden = true }

        let request = FeedScrollRequest()
        let host = UIHostingController(rootView: FeedScrollLayoutFixture(request: request))
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        host.view.frame = CGRect(x: 0, y: 0, width: 736, height: 700)
        host.additionalSafeAreaInsets.right = 80
        host.view.layoutIfNeeded()
        try #require(await eventually { scrollViews(in: host.view).count == 1 })
        let feed = try #require(scrollViews(in: host.view).first)
        let originalID = ObjectIdentifier(feed)

        request.post = 8
        var previousOffset: CGFloat = -1
        try #require(await eventually {
            let offset = feed.contentOffset.y + feed.adjustedContentInset.top
            defer { previousOffset = offset }
            return offset > 500 && abs(offset - previousOffset) < 0.5
        }, "ScrollViewReader must reach the requested post before changing safe areas")
        let originalOffset = feed.contentOffset.y + feed.adjustedContentInset.top

        for inset in [
            UIEdgeInsets(top: 0, left: 96, bottom: 0, right: 0),
            UIEdgeInsets(top: 0, left: 32, bottom: 0, right: 112),
            UIEdgeInsets(top: 40, left: 0, bottom: 24, right: 64),
            .zero,
        ] {
            host.additionalSafeAreaInsets = inset
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let settled = try await eventually {
                abs(feed.contentOffset.y + feed.adjustedContentInset.top - originalOffset) < 1
            }
            let offset = feed.contentOffset.y + feed.adjustedContentInset.top
            try #require(settled, "SwiftUI must keep the same post after \(inset); offset \(offset), expected \(originalOffset)")
            #expect(scrollViews(in: host.view).map(ObjectIdentifier.init) == [originalID])
        }
    }

    @Test("The selected trailing category stays visible after folds and inset-only changes")
    func selectedCategoryStaysVisibleWhenItsViewportNarrows() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        defer { window.isHidden = true }

        // Selection never changes in this fixture. Only the available space
        // changes, so a selection-only reveal callback cannot pass this test.
        let host = UIHostingController(rootView: CategoryStripLayoutFixture())
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        host.view.frame = CGRect(x: 0, y: 0, width: 736, height: 300)
        host.view.layoutIfNeeded()
        try #require(await eventually { scrollViews(in: host.view).count == 1 })
        let strip = try #require(scrollViews(in: host.view).first)
        let originalID = ObjectIdentifier(strip)
        try #require(await eventually { strip.bounds.width > strip.contentSize.width && strip.contentSize.width > 0 })

        for (width, inset): (CGFloat, UIEdgeInsets) in [
            (466, .zero),
            (736, .zero),
            (736, UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 280)),
            (736, UIEdgeInsets(top: 0, left: 280, bottom: 0, right: 0)),
            (466, UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 64)),
        ] {
            host.additionalSafeAreaInsets = inset
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 300)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let settled = try await eventually {
                let expectedWidth = host.view.bounds.width - host.view.safeAreaInsets.left - host.view.safeAreaInsets.right
                let offset = strip.contentOffset.x + strip.adjustedContentInset.left
                let visibleWidth = strip.bounds.width - strip.adjustedContentInset.left - strip.adjustedContentInset.right
                let remaining = strip.contentSize.width - (offset + visibleWidth)
                return abs(visibleWidth - expectedWidth) < 0.5 && remaining <= 0.5
            }
            try #require(settled, "Quizz, the final category, must remain fully visible at width \(width) with insets \(inset)")
            #expect(scrollViews(in: host.view).map(ObjectIdentifier.init) == [originalID])
        }
    }

    @Test("Every page keeps its resting width and rail inset during tap transitions", arguments: [RailEdge.leading, .trailing])
    func tapTransitionsKeepRestingWidths(_ edge: RailEdge) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        defer { window.isHidden = true }
        let pager = PagerState()
        let host = UIHostingController(rootView: PagerLayoutFixture(pager: pager, animationDuration: 0.6))
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        host.view.frame = CGRect(x: 0, y: 0, width: 466, height: 700)
        host.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0, left: edge == .leading ? 84 : 0, bottom: 0, right: edge == .trailing ? 84 : 0
        )
        host.view.layoutIfNeeded()

        try #require(try await eventually {
            scrollViews(in: host.view).count == AppTab.allCases.count + 1
                && pager.viewportWidth == host.view.bounds.width
        })
        let horizontal = try #require(scrollViews(in: host.view).first)
        let pages = scrollViews(in: horizontal).filter { $0 !== horizontal }.sorted {
            $0.convert($0.bounds, to: horizontal).minX < $1.convert($1.bounds, to: horizontal).minX
        }
        let insets = host.view.safeAreaInsets
        let restingWidth = host.view.bounds.inset(by: insets).width
        func isResting(_ page: UIScrollView) -> Bool {
            page.contentSize.width == restingWidth
                && page.adjustedContentInset.left == insets.left
                && page.adjustedContentInset.right == insets.right
        }
        try #require(try await eventually { pages.allSatisfy(isResting) })
        pager.setReduceMotion(false)

        // A distant departure covers compressed travel, then ordinary pages
        // at both ends, then a return to For you.
        for destination in [AppTab.quizz, .videos, .bookmarks] {
            pager.select(destination)
            var movingOffsets: [CGFloat] = []
            var incorrect: [String] = []
            for _ in 0..<300 {
                try await Task.sleep(for: .milliseconds(5))
                let offset = horizontal.contentOffset.x + horizontal.adjustedContentInset.left
                if pager.tapTransition != nil {
                    if movingOffsets.last != offset {
                        movingOffsets.append(offset)
                    }
                    for (index, page) in pages.enumerated() where !isResting(page) {
                        incorrect.append("page \(index) at offset \(offset): width \(page.contentSize.width), inset \(page.adjustedContentInset)")
                    }
                }
                if pager.selectedTab == destination && pager.isAtRest { break }
            }
            #expect(movingOffsets.count >= 2, "The test must observe multiple rendered positions during the tap")
            #expect(incorrect.isEmpty, "No page may change its width or rail inset while paging. \(incorrect.joined(separator: "; "))")
            try #require(try await eventually { pager.selectedTab == destination && pager.isAtRest })
            #expect(pages.allSatisfy(isResting))
        }
    }

    @Test("The real Home header keeps vertical content still throughout horizontal tap animations", arguments: [CGFloat(0), 320])
    func realHomeChromeDoesNotMoveVerticalContentDuringPaging(_ startingOffset: CGFloat) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        defer { window.isHidden = true }
        let pager = PagerState()
        let host = UIHostingController(rootView: HomeChromePagerFixture(pager: pager))
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        host.view.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
        host.additionalSafeAreaInsets.right = 84
        host.view.layoutIfNeeded()
        let pagerContentWidth = host.view.bounds.width * CGFloat(AppTab.allCases.count)
        try #require(try await eventually {
            pager.viewportWidth == host.view.bounds.width
                && scrollViews(in: host.view).contains { $0.contentSize.width == pagerContentWidth }
        })
        let horizontal = try #require(scrollViews(in: host.view).first { $0.contentSize.width == pagerContentWidth })
        let pages = scrollViews(in: horizontal).filter { $0 !== horizontal }.sorted {
            $0.convert($0.bounds, to: horizontal).minX < $1.convert($1.bounds, to: horizontal).minX
        }
        try #require(pages.count == AppTab.allCases.count)
        let incoming = pages[AppTab.bookmarks.index]
        try #require(try await eventually { incoming.contentSize.height > incoming.bounds.height })

        incoming.setContentOffset(
            CGPoint(x: incoming.contentOffset.x, y: startingOffset - incoming.adjustedContentInset.top),
            animated: false
        )
        try #require(try await eventually {
            incoming.contentOffset.y + incoming.adjustedContentInset.top == startingOffset
        }, "The page must begin at the requested vertical scroll position")

        pager.setReduceMotion(true)
        pager.select(.videos)
        try #require(try await eventually { pager.selectedTab == .videos && pager.isAtRest })
        let initialInset = incoming.adjustedContentInset.top
        let initialOffset = incoming.contentOffset.y
        let initialOrigin = incoming.convert(CGPoint.zero, to: host.view).y
        let initialContentHeight = incoming.contentSize.height
        #expect(initialOffset + initialInset == startingOffset)
        pager.setReduceMotion(false)
        pager.select(.bookmarks)

        var horizontalOffsets: Set<CGFloat> = []
        var offsets: [CGFloat] = []
        var insets: [CGFloat] = []
        var origins: [CGFloat] = []
        var contentHeights: [CGFloat] = []
        var observations: [String] = []
        // Keeps sampling after the pager settles, through the logo row's
        // own animation.
        var samplesAfterRest = 0
        for _ in 0..<400 where samplesAfterRest < 60 {
            try await Task.sleep(for: .milliseconds(5))
            let x = horizontal.contentOffset.x + horizontal.adjustedContentInset.left
            let offset = incoming.contentOffset.y
            let inset = incoming.adjustedContentInset.top
            let origin = incoming.convert(CGPoint.zero, to: host.view).y
            let contentHeight = incoming.contentSize.height
            horizontalOffsets.insert(x)
            offsets.append(offset)
            insets.append(inset)
            origins.append(origin)
            contentHeights.append(contentHeight)
            let observation = "x=\(x), y=\(offset), inset=\(inset), origin=\(origin), height=\(contentHeight), width=\(incoming.contentSize.width), bounds=\(incoming.bounds.size), adjusted=\(incoming.adjustedContentInset), safe=\(incoming.safeAreaInsets)"
            if observations.last != observation {
                observations.append(observation)
            }
            if pager.selectedTab == .bookmarks && pager.isAtRest { samplesAfterRest += 1 }
        }
        try #require(horizontalOffsets.count >= 2, "The test must sample a real animation")
        #expect(offsets.allSatisfy { $0 == initialOffset },
                "Horizontal paging must not alter vertical contentOffset. \(observations.joined(separator: "; "))")
        #expect(insets.allSatisfy { $0 == initialInset },
                "Horizontal paging must not alter the top adjusted inset. \(observations.joined(separator: "; "))")
        #expect(origins.allSatisfy { $0 == initialOrigin },
                "The native content origin must stay vertically fixed below the real safeAreaBar. \(observations.joined(separator: "; "))")
        #expect(contentHeights.allSatisfy { $0 == initialContentHeight },
                "Horizontal paging must not change the content height or its scroll range. \(observations.joined(separator: "; "))")
        #expect(pager.selectedTab == .bookmarks && pager.isAtRest)
    }

    enum RailEdge: String, Sendable {
        case leading
        case trailing
    }

    private func view(withIdentifier identifier: String, in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == identifier { return root }
        for child in root.subviews {
            if let found = view(withIdentifier: identifier, in: child) { return found }
        }
        return nil
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
    /// Slows animated transitions so a test can sample them.
    var animationDuration: Double? = nil
    private let logoCollapse = LogoCollapse()
    private let taskList = ForYouTaskList()
    @Namespace private var zoomNamespace

    var body: some View {
        HomePager(
            pager: pager,
            logoCollapse: logoCollapse,
            taskList: taskList,
            zoomNamespace: zoomNamespace,
            onUpdate: {}
        )
        .transaction { transaction in
            if transaction.animation != nil, let animationDuration {
                transaction.animation = .linear(duration: animationDuration)
            }
        }
    }
}

private struct PagerHeaderLayoutFixture: View {
    let pager: PagerState

    var body: some View {
        PagerLayoutFixture(pager: pager)
            .safeAreaBar(edge: .top, spacing: 0) {
                LayoutMarker()
                    .frame(height: TopMenuMetrics.expandedHeight)
            }
    }
}

private struct LayoutMarker: UIViewRepresentable {
    static let headerIdentifier = "test.header"

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.accessibilityIdentifier = Self.headerIdentifier
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct CategoryStripLayoutFixture: View {
    var body: some View {
        VStack {
            CategoryChipStrip(
                selection: CGFloat(AppTab.quizz.index),
                selectedTab: AppTab.quizz,
                isSelectionLocked: true,
                onSelect: { _ in }
            )
            Spacer()
        }
    }
}

@MainActor
@Observable
private final class FeedScrollRequest {
    var post: Int?
}

private struct FeedScrollLayoutFixture: View {
    let request: FeedScrollRequest
    private let taskList = ForYouTaskList()
    @Namespace private var zoomNamespace

    var body: some View {
        ScrollViewReader { proxy in
            FeedPage(tab: .videos, zoomNamespace: zoomNamespace, taskList: taskList)
                .onChange(of: request.post) { _, post in
                    if let post { proxy.scrollTo(post, anchor: .top) }
                }
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            LayoutMarker()
                .frame(height: TopMenuMetrics.expandedHeight)
        }
    }
}

private struct HomeChromePagerFixture: View {
    let pager: PagerState
    private let logoCollapse = LogoCollapse()
    private let taskList = ForYouTaskList()
    private let scanner = ScannerModel()
    private let scannerSheet = SheetController(initialDetent: .hidden)
    private let sheetSettings = PreviewFixtures.makeSettings()
    private let scanHistory = PreviewFixtures.makeHistory()
    @State private var rootTab: RootTab = .home
    @Namespace private var zoomNamespace

    var body: some View {
        NavigationStack {
            RootTabContent(selection: $rootTab, scanner: scanner, scannerSheet: scannerSheet, sheetSettings: sheetSettings,
                           scanHistory: scanHistory) {
                HomeRootView(
                    title: "Nako", pager: pager, logoCollapse: logoCollapse,
                    taskList: taskList, zoomNamespace: zoomNamespace,
                    onSelect: pager.select, onUpdate: {}
                ) {
                    EmptyView()
                }
            }
            .navigationTitle("Nako")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }
}
