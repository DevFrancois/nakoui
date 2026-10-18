import SwiftUI
import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct RootTabIntegrationTests {
    @Test("Tab changes and outer navigation preserve Home state and its real scroll views", arguments: [false, true])
    func retainsHomeAcrossTabsAndNavigation(animationEnabled: Bool) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let state = TabIntegrationState()
        let record = HomeIdentityRecord()
        let host = UIHostingController(rootView: TabIntegrationFixture(
            state: state, record: record, animationEnabled: animationEnabled
        ))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        try #require(await eventually { record.token != nil && self.findTabs(in: host) != nil })
        let tabs = try #require(findTabs(in: host))
        let originalHosts = tabs.viewControllers?.map(ObjectIdentifier.init)
        let home = try #require(tabs.viewControllers?.first)
        try #require(await eventually { self.scrolls(in: home.view).count >= AppTab.allCases.count + 1 })
        try #require(await eventually {
            let insets = tabs.contentSafeAreaInsets
            return insets.left + insets.right + insets.bottom > 0
                && home.view.safeAreaInsets.left >= insets.left
                && home.view.safeAreaInsets.right >= insets.right
                && home.view.safeAreaInsets.bottom >= insets.bottom
        }, "The outer toolbar's insets must reach the retained Home host")
        #expect(abs(state.pager.viewportWidth - tabs.view.bounds.width) < 0.5,
                "The Home paging viewport must still span the full container")
        let originalScrolls = scrolls(in: home.view)
        let originalIDs = Set(originalScrolls.map(ObjectIdentifier.init))
        let originalToken = record.token
        let horizontal = try #require(originalScrolls.first { self.scrolls(in: $0).count == AppTab.allCases.count + 1 })
        let pages = scrolls(in: horizontal).dropFirst().sorted {
            $0.convert($0.bounds, to: horizontal).minX < $1.convert($1.bounds, to: horizontal).minX
        }
        state.pager.setReduceMotion(true)
        state.pager.select(.videos)
        try #require(await eventually { state.pager.selectedTab == .videos && state.pager.isAtRest })
        let videos = pages[AppTab.videos.index]
        videos.setContentOffset(CGPoint(x: 0, y: 320), animated: false)
        try #require(await eventually { abs(videos.contentOffset.y - 320) < 0.5 })

        for selection: RootTab in [.profile, .search, .scanner, .home] {
            let requestCount = tabs.transitionRequestCount
            state.selection = selection
            if animationEnabled {
                try #require(await eventually {
                    tabs.committedSelection == selection && tabs.activeAnimator?.isAnimated == true
                }, "The animated fixture must exercise the delegate's real page animator")
                #expect(tabs.transitionRequestCount == requestCount + 1)
            }
            try #require(await eventually { tabs.committedSelection == selection && tabs.activeAnimator == nil })
        }
        try #require(await eventually { home.view.window != nil })
        #expect(Set(scrolls(in: home.view).map(ObjectIdentifier.init)) == originalIDs)
        #expect(record.token == originalToken)
        #expect(state.pager.selectedTab == .videos)
        #expect(abs(videos.contentOffset.y - 320) < 0.5)
        #expect(tabs.viewControllers?.map(ObjectIdentifier.init) == originalHosts)

        state.navigation.push(QuizKind.classic)
        try #require(await eventually { self.hasMarker("test.tabDestination", in: host.view) })
        if animationEnabled { try await Task.sleep(for: .milliseconds(450)) }
        state.navigation.path.removeLast()
        try #require(await eventually {
            !self.hasMarker("test.tabDestination", in: host.view) && home.view.window != nil
        })
        #expect(findTabs(in: host) === tabs)
        #expect(tabs.viewControllers?.map(ObjectIdentifier.init) == originalHosts)
        #expect(Set(scrolls(in: home.view).map(ObjectIdentifier.init)) == originalIDs)
        #expect(record.token == originalToken)
        #expect(state.pager.selectedTab == .videos)
        #expect(abs(videos.contentOffset.y - 320) < 0.5)
    }

    private func findTabs(in controller: UIViewController) -> RootTabController? {
        if let tabs = controller as? RootTabController { return tabs }
        return controller.children.lazy.compactMap { findTabs(in: $0) }.first
    }

    private func scrolls(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrolls(in: $0) }
    }

    private func hasMarker(_ id: String, in view: UIView) -> Bool {
        view.accessibilityIdentifier == id || view.subviews.contains { hasMarker(id, in: $0) }
    }

    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<150 {
            try await Task.sleep(for: .milliseconds(20))
            if condition() { return true }
        }
        return false
    }
}

@MainActor @Observable
private final class TabIntegrationState {
    var selection: RootTab = .home
    let navigation = RootNavigation()
    let pager = PagerState()
    let scanner = ScannerModel()
    let logo = LogoCollapse()
    let tasks = ForYouTaskList()
}

private struct TabIntegrationFixture: View {
    @Bindable var state: TabIntegrationState
    let record: HomeIdentityRecord
    let animationEnabled: Bool
    @Namespace private var zoom

    var body: some View {
        @Bindable var navigation = state.navigation
        NavigationStack(path: $navigation.path) {
            RootTabContent(selection: $state.selection, scanner: state.scanner, isTabBarVisible: state.navigation.path.isEmpty) {
                HomeRootView(
                    title: "Nako", pager: state.pager, logoCollapse: state.logo,
                    taskList: state.tasks, zoomNamespace: zoom,
                    onSelect: state.pager.select, onUpdate: {}
                ) { EmptyView() }
                .overlay { HomeIdentityProbe(record: record).frame(width: 1, height: 1) }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: QuizKind.self) { kind in
                QuizDestination(kind: kind)
                    .overlay { TabDestinationMarker().frame(width: 1, height: 1) }
            }
        }
        .environment(\.rootNavigation, state.navigation)
        .transaction { $0.disablesAnimations = !animationEnabled }
    }
}

@MainActor
private final class HomeIdentityRecord {
    var token: UUID?
}

private struct HomeIdentityProbe: View {
    @State private var token = UUID()
    let record: HomeIdentityRecord

    var body: some View {
        Color.clear.onAppear { record.token = token }
    }
}

private struct TabDestinationMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.accessibilityIdentifier = "test.tabDestination"
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}
