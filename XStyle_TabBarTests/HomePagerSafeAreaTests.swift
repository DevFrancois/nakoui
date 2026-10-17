import SwiftUI
import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct HomePagerSafeAreaTests {
    @Test("Incoming For you narrows beside the rail, then retains its settled width during a cancelled departure")
    func onlyIncomingForYouNarrowsDuringDrag() async throws {
        let fixture = try makeHost(edge: .trailing)
        defer { fixture.window.isHidden = true }
        let host = fixture.host
        let pager = fixture.pager
        let width: CGFloat = 466
        try #require(await eventually {
            let scrolls = scrollViews(in: host.view)
            return scrolls.count == AppTab.allCases.count + 1
                && abs(pager.viewportWidth - width) < 0.5
                && scrolls.dropFirst().allSatisfy { $0.contentSize.width > 0 }
        })
        let horizontal = try #require(scrollViews(in: host.view).first)
        let pages = scrollViews(in: horizontal).filter { $0 !== horizontal }.sorted {
            $0.convert($0.bounds, to: horizontal).minX < $1.convert($1.bounds, to: horizontal).minX
        }
        let incoming = pages[AppTab.bookmarks.index]
        let originalIDs = Set(pages.map(ObjectIdentifier.init))
        let insets = host.view.safeAreaInsets
        let railWidth = insets.right
        let restingWidth = width - insets.left - insets.right
        try #require(railWidth > 0 && railWidth < width / 2)

        pager.setReduceMotion(true)
        pager.select(.videos)
        try #require(await eventually { pager.selectedTab == .videos && pager.isAtRest })
        // UIKit offsets drive the real SwiftUI layout. Hold the gesture phase
        // open while stepping so crossing halfway cannot commit the source.
        pager.scrollPhaseDidChange(from: .idle, to: .interacting, geometry: PagerGeometry(offset: width, width: width))
        var arrivalWidths: [CGFloat] = []
        for distance in [railWidth + 28, railWidth, railWidth * 0.75, railWidth * 0.5, railWidth * 0.25, 0] {
            horizontal.setContentOffset(
                CGPoint(x: distance - horizontal.adjustedContentInset.left, y: horizontal.contentOffset.y),
                animated: false
            )
            let expectedRight = max(railWidth - distance, 0)
            let expectedWidth = width - insets.left - expectedRight
            try #require(await eventually {
                abs(incoming.contentSize.width - expectedWidth) < 1
                    && abs(incoming.adjustedContentInset.right - expectedRight) < 1
                    && abs(incoming.convert(incoming.bounds, to: host.view).minX + distance) < 1
            }, "Incoming For you must narrow continuously at distance \(distance). \(describe(incoming, in: host.view))")
            arrivalWidths.append(incoming.contentSize.width)
            #expect(pager.selectedTab == .videos, "The gesture's source must remain Videos until the drag settles")
            if expectedRight > 0 {
                let frame = incoming.convert(incoming.bounds, to: host.view)
                #expect(abs(frame.maxX - incoming.adjustedContentInset.right - (width - railWidth)) < 1,
                        "For you's trailing content edge must stay against the rail")
            }
            for page in pages.dropFirst() {
                #expect(abs(page.contentSize.width - restingWidth) < 1,
                        "Every other page must retain its settled width during the incoming For you drag")
            }
        }
        #expect((arrivalWidths.first ?? 0) - (arrivalWidths.last ?? 0) > railWidth - 1)
        pager.scrollPhaseDidChange(from: .interacting, to: .idle, geometry: PagerGeometry(offset: 0, width: width))
        try #require(await eventually { pager.selectedTab == .bookmarks && pager.isAtRest })

        // Reverse direction from the newly settled For you page and cancel.
        // Even crossing the midpoint must not widen a departing For you.
        pager.scrollPhaseDidChange(from: .idle, to: .interacting, geometry: PagerGeometry(offset: 0, width: width))
        for distance in [railWidth * 0.25, railWidth * 0.5, railWidth, width * 0.7, width * 0.4, railWidth * 0.5, 0] {
            horizontal.setContentOffset(
                CGPoint(x: distance - horizontal.adjustedContentInset.left, y: horizontal.contentOffset.y),
                animated: false
            )
            try #require(await eventually {
                abs(pager.progress * width - distance) < 1
                    && pages.allSatisfy { abs($0.contentSize.width - restingWidth) < 1 }
            }, "All surfaces, including departing For you, must retain settled width while a swipe reverses. Distance \(distance), widths \(pages.map { $0.contentSize.width })")
            #expect(pager.selectedTab == .bookmarks)
        }
        pager.scrollPhaseDidChange(from: .interacting, to: .idle, geometry: PagerGeometry(offset: 0, width: width))
        try #require(await eventually { pager.selectedTab == .bookmarks && pager.isAtRest })
        #expect(Set(scrollViews(in: horizontal).filter { $0 !== horizontal }.map(ObjectIdentifier.init)) == originalIDs)
        #expect(abs(horizontal.contentSize.width - width * CGFloat(pages.count)) < 0.5,
                "The width effect must preserve the full horizontal page stride")
    }

    @Test("Departing For you and every other page retain their settled widths during tap transitions", arguments: [RailEdge.leading, .trailing])
    func outgoingAndOrdinaryPagesKeepSettledWidths(_ edge: RailEdge) async throws {
        let fixture = try makeHost(edge: edge, animationDuration: 0.6)
        defer { fixture.window.isHidden = true }
        let host = fixture.host
        let pager = fixture.pager
        let width: CGFloat = 466
        try #require(await eventually {
            scrollViews(in: host.view).count == AppTab.allCases.count + 1
                && abs(pager.viewportWidth - width) < 0.5
        })
        let horizontal = try #require(scrollViews(in: host.view).first)
        let pages = scrollViews(in: horizontal).filter { $0 !== horizontal }.sorted {
            $0.convert($0.bounds, to: horizontal).minX < $1.convert($1.bounds, to: horizontal).minX
        }
        let insets = host.view.safeAreaInsets
        let restingWidth = width - insets.left - insets.right
        try #require(await eventually { pages.allSatisfy { abs($0.contentSize.width - restingWidth) < 1 } })
        pager.setReduceMotion(false)

        // A distant departure covers compressed travel; the second transition
        // has ordinary pages at both ends and must not apply the effect at all.
        for destination in [AppTab.quizz, .videos] {
            let source = pager.selectedTab
            pager.select(destination)
            var movingOffsets: [CGFloat] = []
            var incorrectWidths: [String] = []
            for _ in 0..<300 {
                try await Task.sleep(for: .milliseconds(5))
                let offset = horizontal.contentOffset.x + horizontal.adjustedContentInset.left
                if pager.tapTransition != nil {
                    if movingOffsets.last.map({ abs($0 - offset) > 1 }) ?? true {
                        movingOffsets.append(offset)
                    }
                    let monitored = source == .bookmarks ? pages[...] : pages.dropFirst()
                    for page in monitored where abs(page.contentSize.width - restingWidth) >= 1 {
                        incorrectWidths.append("offset=\(offset), width=\(page.contentSize.width), expected=\(restingWidth)")
                    }
                }
                if pager.selectedTab == destination && pager.isAtRest { break }
            }
            #expect(movingOffsets.count >= 2, "The test must observe multiple rendered positions during the tap")
            #expect(incorrectWidths.isEmpty, "Only an incoming For you may change width. \(incorrectWidths.joined(separator: "; "))")
            try #require(await eventually { pager.selectedTab == destination && pager.isAtRest })
            #expect(pages.dropFirst().allSatisfy { abs($0.contentSize.width - restingWidth) < 1 })
        }
    }

    @Test("A distant tap narrows the incoming page during its final visible travel beside the rail")
    func distantTapUsesDisplayedPositionForRailOverlap() async throws {
        // Give the narrow rail-overlap band several display frames even on
        // a busy simulator. Geometry is tested independently of duration.
        let fixture = try makeHost(edge: .trailing, animationDuration: 1.5)
        defer { fixture.window.isHidden = true }
        let host = fixture.host
        let pager = fixture.pager
        let width: CGFloat = 466
        try #require(await eventually {
            scrollViews(in: host.view).count == AppTab.allCases.count + 1
                && abs(pager.viewportWidth - width) < 0.5
        })

        let scrolls = scrollViews(in: host.view)
        let horizontal = try #require(scrolls.first)
        let pages = scrolls.dropFirst().sorted {
            $0.convert($0.bounds, to: horizontal).minX < $1.convert($1.bounds, to: horizontal).minX
        }
        let incomingPage = pages[AppTab.bookmarks.index]
        let originalID = ObjectIdentifier(incomingPage)
        let viewportInsets = host.view.safeAreaInsets
        let railWidth = viewportInsets.right
        try #require(railWidth > 0)

        pager.setReduceMotion(true)
        pager.select(.quizz)
        try #require(await eventually { pager.selectedTab == .quizz && pager.isAtRest })
        pager.setReduceMotion(false)
        pager.select(.bookmarks)
        try #require(pager.tapTransition?.source == .quizz && pager.tapTransition?.destination == .bookmarks)

        var matchingWidths: [CGFloat] = []
        var observations: [String] = []
        // A four-page native scroll is displayed as one page of travel. Read
        // that scroll's real offset, independently of PagerState.progress and
        // HomePageMargins. UIKit frames omit the SwiftUI visual-effect offset.
        let pageDistance = CGFloat(AppTab.quizz.index - AppTab.bookmarks.index)
        for _ in 0..<400 {
            try await Task.sleep(for: .milliseconds(5))
            let offset = horizontal.contentOffset.x + horizontal.adjustedContentInset.left
            let displayedDistance = offset / pageDistance
            if pager.tapTransition != nil,
               displayedDistance > railWidth * 0.25,
               displayedDistance < railWidth * 0.75 {
                let expectedRight = railWidth - displayedDistance
                let expectedWidth = width - viewportInsets.left - expectedRight
                let contentWidth = incomingPage.contentSize.width
                let insets = incomingPage.adjustedContentInset
                observations.append("distance=\(displayedDistance), width=\(contentWidth)/\(expectedWidth), right=\(insets.right)/\(expectedRight)")
                // Geometry and SwiftUI layout can be one display frame apart
                // during a real animation. A raw four-page position still
                // misses this middle band by at least a quarter of the rail.
                let frameTolerance: CGFloat = 12
                if abs(contentWidth - expectedWidth) < frameTolerance,
                   abs(insets.right - expectedRight) < frameTolerance,
                   abs(insets.left - viewportInsets.left) < 1,
                   matchingWidths.last.map({ abs($0 - contentWidth) > 1 }) ?? true {
                    matchingWidths.append(contentWidth)
                }
            }
            if pager.selectedTab == .bookmarks && pager.isAtRest { break }
        }

        #expect(matchingWidths.count >= 2,
                "At least two distinct rendered widths must follow the compressed page's middle rail overlap, before the native layout frame arrives. \(observations.joined(separator: "; "))")
        try #require(await eventually {
            pager.selectedTab == .bookmarks && pager.isAtRest
                && abs(incomingPage.contentSize.width - (width - viewportInsets.left - viewportInsets.right)) < 1
        }, "The animated return must finish with the content inside both safe-area edges")
        #expect(scrollViews(in: host.view).contains { ObjectIdentifier($0) == originalID })
        #expect(abs(horizontal.contentSize.width - width * CGFloat(pages.count)) < 0.5)
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
        try #require(await eventually {
            abs(pager.viewportWidth - 466) < 0.5
                && scrollViews(in: host.view).contains { abs($0.contentSize.width - 5 * 466) < 1 }
        })
        let horizontal = try #require(scrollViews(in: host.view).first {
            abs($0.contentSize.width - 5 * 466) < 1
        })
        let pages = scrollViews(in: horizontal).filter { $0 !== horizontal }.sorted {
            $0.convert($0.bounds, to: horizontal).minX < $1.convert($1.bounds, to: horizontal).minX
        }
        try #require(pages.count == AppTab.allCases.count)
        let incoming = pages[AppTab.bookmarks.index]
        try #require(await eventually { incoming.contentSize.height > incoming.bounds.height })

        incoming.setContentOffset(
            CGPoint(x: incoming.contentOffset.x, y: startingOffset - incoming.adjustedContentInset.top),
            animated: false
        )
        try #require(await eventually {
            abs(incoming.contentOffset.y + incoming.adjustedContentInset.top - startingOffset) < 0.5
        }, "The page must begin at the requested vertical scroll position")

        pager.setReduceMotion(true)
        pager.select(.videos)
        try #require(await eventually { pager.selectedTab == .videos && pager.isAtRest })
        let initialInset = incoming.adjustedContentInset.top
        let initialOffset = incoming.contentOffset.y
        let initialOrigin = incoming.convert(CGPoint.zero, to: host.view).y
        let initialContentHeight = incoming.contentSize.height
        #expect(abs(initialOffset + initialInset - startingOffset) < 0.5)
        pager.setReduceMotion(false)
        pager.select(.bookmarks)

        var offsets: [CGFloat] = []
        var insets: [CGFloat] = []
        var origins: [CGFloat] = []
        var contentHeights: [CGFloat] = []
        var observations: [String] = []
        for _ in 0..<240 {
            try await Task.sleep(for: .milliseconds(5))
            let x = horizontal.contentOffset.x + horizontal.adjustedContentInset.left
            let offset = incoming.contentOffset.y
            let inset = incoming.adjustedContentInset.top
            let origin = incoming.convert(CGPoint.zero, to: host.view).y
            let contentHeight = incoming.contentSize.height
            offsets.append(offset)
            insets.append(inset)
            origins.append(origin)
            contentHeights.append(contentHeight)
            let observation = "x=\(x), y=\(offset), inset=\(inset), origin=\(origin), height=\(contentHeight)"
            if observations.last != observation {
                observations.append(observation)
            }
            if pager.selectedTab == .bookmarks && pager.isAtRest { break }
        }
        try #require(offsets.count > 10, "The test must sample a real animation")
        #expect(offsets.allSatisfy { abs($0 - initialOffset) < 0.5 },
                "Horizontal paging must not alter vertical contentOffset. \(observations.joined(separator: "; "))")
        #expect(insets.allSatisfy { abs($0 - initialInset) < 0.5 },
                "Horizontal paging must not alter the top adjusted inset. \(observations.joined(separator: "; "))")
        #expect(origins.allSatisfy { abs($0 - initialOrigin) < 0.5 },
                "The native content origin must stay vertically fixed below the real safeAreaBar. \(observations.joined(separator: "; "))")
        #expect(contentHeights.allSatisfy { abs($0 - initialContentHeight) < 0.5 },
                "Width-only surface motion must not repeatedly change the content height or its scroll range. \(observations.joined(separator: "; "))")
        #expect(pager.selectedTab == .bookmarks && pager.isAtRest)
    }

    enum RailEdge: String, Sendable {
        case leading
        case trailing
    }

    private func makeHost(edge: RailEdge, animationDuration: Double? = nil) throws -> (
        window: UIWindow, host: UIHostingController<SafeAreaPagerFixture>, pager: PagerState
    ) {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        let pager = PagerState()
        let host = UIHostingController(rootView: SafeAreaPagerFixture(pager: pager, animationDuration: animationDuration))
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        host.view.frame = CGRect(x: 0, y: 0, width: 466, height: 700)
        host.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0, left: edge == .leading ? 84 : 0, bottom: 0, right: edge == .trailing ? 84 : 0
        )
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return (window, host, pager)
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        let ownScroll = (view as? UIScrollView).map { [$0] } ?? []
        return ownScroll + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func describe(_ page: UIScrollView, in root: UIView) -> String {
        "frame=\(page.convert(page.bounds, to: root)), content=\(page.contentSize), inset=\(page.adjustedContentInset)"
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        var matches = 0
        for _ in 0..<150 {
            try? await Task.sleep(for: .milliseconds(20))
            matches = condition() ? matches + 1 : 0
            if matches == 2 { return true }
        }
        return false
    }
}

private struct SafeAreaPagerFixture: View {
    let pager: PagerState
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
        .environment(\.layoutDirection, .leftToRight)
        .transaction { transaction in
            if transaction.animation != nil, let animationDuration {
                transaction.animation = .linear(duration: animationDuration)
            }
        }
    }
}

private struct HomeChromePagerFixture: View {
    let pager: PagerState
    private let logoCollapse = LogoCollapse()
    private let taskList = ForYouTaskList()
    private let scanner = ScannerModel()
    @State private var rootTab: RootTab = .home
    @Namespace private var zoomNamespace

    var body: some View {
        NavigationStack {
            RootTabContent(selection: $rootTab, scanner: scanner) {
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
        .environment(\.layoutDirection, .leftToRight)
    }
}
